// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BackerTokenInterface.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./GlobalVariables_12x.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "./ContributionNFT.sol";

import {console, console2} from "forge-std/Test.sol";

// Interface để kiểm tra hàm onERC20Received
interface IERC20Receiver {
    function onERC20Received(address from, uint256 amount, bytes calldata data) external returns (bytes4);
}

/**
 * TODO (1): PLANNING & general task
 *  1. use create2 to deploy contract
 *  2. will be upgradable to transfer ownership to community or upgrade contract to fix bugs, etc.
 *  3. will revise function can be called by operator for community to use.
 *  4. check slippage when adding liquidity
 */
contract TokenTemplate1 is ERC20, ReentrancyGuard {
    // https://docs.uniswap.org/contracts/v2/reference/smart-contracts/v2-deployments
    address public constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; // Uniswap V2 Factory
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router
    address public immutable WETH; // Declare WETH address

    // Todo (2) for the token supply: khống chế tỉ lệ tối đa của số lượng ETH: số lượng token là 1:10000 để hạn chế slippage cho trader
    // Todo (3) tùy chọn thêm cho phép raiser thiết lập "minimum safe lock period for backer", "minimum safe lock period for alchemist", vd 1 tháng, 2 tháng... để linh động hơn.
    uint256 public constant MAX_SUPPLY = 2.1e9 * 1 ether; // cap of total supply: 2.1 billion, 18 decimal places
    uint256 public constant INITIAL_SUPPLY = 1e9 * 1 ether; // 1 billion, 18 decimal places, distributed to backers at the very beginning as exchange for their funding support. 100 million remain will be used for later rewards purpose (such as backer's loyalty, etc.)
    uint256 public constant REWARD_SUPPLY = 1e8 * 1 ether; // 100 million, 18 decimal places, remain will be used for later rewards purpose (such as backer's loyalty, etc.)
    uint256 public constant CALL_OPTION_SUPPLY = MAX_SUPPLY - INITIAL_SUPPLY - REWARD_SUPPLY; // 1 billion, 18 decimal places, max amount for call option
    uint256 public constant BACKER_SAFE_LOCK_PERIOD = 365 days; // 1 year
    uint256 public constant ALCHEMIST_LOCK_PERIOD = 30 days; // 30 days

    address public immutable i_contractOwner; // used in initialized stage
    uint256 public immutable i_realNativeTokenReceived; // used in initialized stage to store real native token received at genesis

    BackerTokenInterface public giveUpMainContract;
    address public operator; // used as admin and will transfer to community later. (NOTE: reserve for later expansion)
    address public firstTokenAddr;
    address public secondTokenAddr;
    address public thirdTokenAddr;
    Liquidity public lp; // liquidity pool
    ContributionNFT public contributionNFT;

    struct TokenShare {
        // share of campaign's result token (for donation campaign) or LP token (for normal campaign, non profit campaign)
        address payable holderAddr; // raiser, alchemist, or backer
        uint256 sharePct; // percentage of share, already * 1e18, e.g 10% = 10e18, when calculate percentage must divide 1e18, when calculate amount must divide 1e20.
        uint256 shareAmt; // amount of that type of token (depend on caimpaign type)
        bool isWithdrawn; // used for both withdrawing LP token or native token
        uint256 withdrawnTime; // timestamp when raiser withdraw (LP or native token)
    }

    struct Liquidity {
        uint256 initialLiq; // initial liquidity when contract created, contributed by raiser, alchemist, backer
        uint256 initialLiqRemain; // realtime initial liquidity remain when genesis contributor withdraw their liquidity.
            // uint256 laterLiq; // later liquidity added after contract created (reserve for future use)
    }

    // Todo (4): sẽ triển khai ghi nhận sự đóng góp cho fromInitialLP và fromWLTokens
    struct NativeTokenAccrued {
        uint256 fromInitialLP; // from initial Liquidity token fee
        uint256 fromWLTokens; // from selling whitelisted token for this campaign
    }

    TokenShare public raiserShare;
    TokenShare public alchemistShare;
    mapping(uint256 => TokenShare) public backerShare;
    CampaignNoBacker public thisCampaign;
    Alchemist public alchemist;
    mapping(uint256 => C_Backer) backer;
    uint256 totalBackers; // total of backer above
    mapping(address => uint256) backerIndex; // index of a specific backer in backer mapping above, starting from 0!

    IUniswapV2Factory uniswapV2Factory = IUniswapV2Factory(UNISWAP_FACTORY);
    IUniswapV2Router02 uniswapV2Router02 = IUniswapV2Router02(UNISWAP_V2_ROUTER);

    address public pair; // main token pair (this token - native token)

    NativeTokenAccrued public nativeTokenAccrued; // fund to support this token contract

    //////// EVENTS ////////
    event RaiserFundsWithdrawn(address indexed raiser, uint256 nativeTokenAmount);
    event TokenSwappedForETH(address indexed token, uint256 tokenAmount, uint256 ethReceived);
    event InitialLiquidityAdded(uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    event InitialLiquidityRemoved(address indexed user, uint256 amountToken, uint256 amountETH, uint256 feeAccrued);

    receive() external payable {}

    modifier onlyOwner() {
        require(msg.sender == i_contractOwner, "Only contract owner can call this function");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator can call this function");
        _;
    }

    modifier onlyRaiser() {
        require(msg.sender == thisCampaign.cId.raiser, "Only raiser can call this function");
        _;
    }

    modifier onlyAlchemist() {
        require(msg.sender == alchemist.addr, "Only alchemist can call this function");
        _;
    }

    modifier onlyBacker(address backerAddr) {
        uint256 index = backerIndex[backerAddr];
        require(totalBackers > 0 && index <= totalBackers, "Backer not found");
        require(msg.sender == backerShare[index].holderAddr, "Not authorized");
        _;
    }

    /**
     * Initialized by those functions in GiveUp contract: performPayout
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _giveUpMainContract,
        address _operator,
        CampaignNoBacker memory _campaignNoBacker,
        Alchemist memory _alchemist
    ) payable ERC20(_name, _symbol) {
        giveUpMainContract = BackerTokenInterface(_giveUpMainContract);
        i_contractOwner = _giveUpMainContract;
        i_realNativeTokenReceived = address(this).balance;
        operator = _operator;
        thisCampaign = _campaignNoBacker;
        alchemist = _alchemist;
        WETH = IUniswapV2Router02(UNISWAP_V2_ROUTER).WETH();
        console2.log("WETH address: ", address(WETH));
        // Calculate raiser share, alchemist share
        // phần tính toán chung
        uint256 pctForRaiserAndAlchemist = 100 - thisCampaign.cId.pctForBackers; // 1st rule: raiser & alchemist get the remain after deducting backer's share
        console2.log("pctForRaiserAndAlchemist: ", pctForRaiserAndAlchemist);
        uint256 backers_initial_token_supply =
            (thisCampaign.cId.haveFundTarget == 100) ? (INITIAL_SUPPLY * thisCampaign.cId.pctForBackers) / 100 : 0;

        if (thisCampaign.cId.haveFundTarget == 100) {
            raiserShare = TokenShare({
                holderAddr: thisCampaign.cId.raiser,
                sharePct: 0, // trong trường hợp này, logic platform quy định raiser không được lấy token của donation campaign
                shareAmt: 0,
                isWithdrawn: false,
                withdrawnTime: 0
            });
            if (alchemist.addr != address(0)) {
                // Alchemist get the token as rememberance, e.g: when raiser set pctForBackers = 90 mean he want to reward alchemist 10% of result token
                alchemistShare = TokenShare({
                    holderAddr: alchemist.addr,
                    // sharePct: (100 - thisCampaign.cId.pctForBackers) / 100,
                    sharePct: (100 - thisCampaign.cId.pctForBackers) * 1e18, // * 1e18, calculation for amount at the end will be divided by 1e18 and 100.
                    shareAmt: INITIAL_SUPPLY - backers_initial_token_supply,
                    isWithdrawn: false,
                    withdrawnTime: 0
                });
            }
        } else if (0 <= thisCampaign.cId.haveFundTarget && thisCampaign.cId.haveFundTarget < 100) {
            require(alchemist.addr != address(0), "Must have Alchemist in this case"); // to avoid loosing fund
            raiserShare = TokenShare({
                holderAddr: thisCampaign.cId.raiser,
                sharePct: (pctForRaiserAndAlchemist * thisCampaign.cId.haveFundTarget) * 1e18 / 100, // raiser get the LP token, already * 1e18, calculation for amount at the end will be divided by 1e18 and 100.
                shareAmt: 0, // can not calculate liquidity shareAmt at this stage because we not yet created pair
                isWithdrawn: false,
                withdrawnTime: 0
            });
            alchemistShare = TokenShare({
                holderAddr: alchemist.addr,
                sharePct: (pctForRaiserAndAlchemist * (100 - thisCampaign.cId.haveFundTarget) * 1e18) / 100, // alchemist get the LP token, already * 1e18, calculation for amount at the end will be divided by 1e18 and 100.
                shareAmt: 0, // can not calculate liquidity shareAmt at this stage because we not yet created pair
                isWithdrawn: false,
                withdrawnTime: 0
            });
            console2.log("100 - thisCampaign.cId.haveFundTarget: ", 100 - thisCampaign.cId.haveFundTarget);
            console2.log("alchemistShare.sharePct: ", alchemistShare.sharePct, alchemistShare.holderAddr);
        } else {
            revert("Invalid haveFundTarget value (maybe it's greater than 100)");
        }

        // Calculate backer share, only record backer with non-zero contribution amount to backersOfCampaign (via option _includeRefunded == false)
        C_Backer[] memory backersOfCampaign = giveUpMainContract.getBackersOfCampaign(thisCampaign.cId.id, false);
        totalBackers = backersOfCampaign.length;

        for (uint256 i = 0; i < totalBackers; i++) {
            backer[i] = backersOfCampaign[i];

            // There 2 cases: donation campaign or not
            uint256 sharePct;
            uint256 shareAmt;
            if (thisCampaign.cId.haveFundTarget == 100) {
                // donation campaign: backer only get this contract token (so called campaign result token) as rememberance
                (sharePct,) = getBackerNativeTokenContribution(backersOfCampaign[i].backer); // result from getBackerNativeTokenContribution not * 1e18
                unchecked {
                    shareAmt = (sharePct * backers_initial_token_supply) / 100;
                }
            } else if (thisCampaign.cId.haveFundTarget < 100) {
                // normal campaign, non profit campaign: backer receive LP token share in the pool, initially held by this contract
                (uint256 sharePctBeforeDeducting,) = getBackerNativeTokenContribution(backersOfCampaign[i].backer);
                sharePct = (sharePctBeforeDeducting * thisCampaign.cId.pctForBackers) * 1e18 / 100; // already * 1e18, calculation for amount at the end will be divided by 1e18 and 100.
                    // can not calculate liquidity shareAmt at this stage because we not yet created pair
            }

            backerShare[i] = TokenShare({
                holderAddr: backersOfCampaign[i].backer,
                sharePct: sharePct,
                shareAmt: shareAmt,
                isWithdrawn: false,
                withdrawnTime: 0
            });
            backerIndex[backersOfCampaign[i].backer] = i;
        }

        // mint INITIAL_SUPPLY tokens to the newly created token contract ONLY when haveFundTarget < 100 (not a donation/tip campaign)
        if (thisCampaign.cId.haveFundTarget < 100) {
            _mint(address(this), INITIAL_SUPPLY);
            // Only in this case then we create liquidity pool include this INITIAL_SUPPLY tokens and native token (ETH/MATIC...)
            pair = uniswapV2Factory.createPair(address(this), WETH);
            require(pair != address(0), "Pair creation failed"); // Check if pair creation was successful
        }
        // contributionNFT = new ContributionNFT(address(this)); // create ContributionNFT (for rememberance purpose)
    }

    /**
     * initWhiteListTokenAddr is used by i_contractOwner only to set whitelisted tokens correspondingly with GiveUp contract at the time created this TokenTemplate1 contract
     * instead of using constant string such as FIRST_TOKEN, SECOND_TOKEN, THIRD_TOKEN use _tokenPriority which 1/2/3
     */
    function initWhiteListTokenAddr(uint256 _tokenPriority, address _addr) public onlyOwner {
        require(_tokenPriority == 1 || _tokenPriority == 2 || _tokenPriority == 3, "Invalid token priority");
        require(_addr != address(0), "Invalid address");
        if (_tokenPriority == 1) {
            firstTokenAddr = _addr;
        } else if (_tokenPriority == 2) {
            secondTokenAddr = _addr;
        } else if (_tokenPriority == 3) {
            thirdTokenAddr = _addr;
        }
    }

    /**
     * transferOperator is used by operator to transfer operator to new address (community in this case)
     * @param _newOperator is the new operator address
     */
    function transferOperator(address _newOperator) external onlyOperator {
        operator = _newOperator;
    }

    /**
     * Contract owner call this function at early stage to add initial liquidity to pool
     * Liquidity pair is: native token (ETH/MATIC...) and this token
     * Once success, it will transfer all liquidity token to this token contract
     * _1: is code for UniswapV2Router02.addLiquidityETH
     */
    function addInitialLiquidityETH_1() external payable onlyOwner returns (uint256) {
        require(pair != address(0), "Pair not set");
        require(msg.value > 0 && msg.value <= thisCampaign.cFunded.raisedFund.amtFunded, "Invalid native token amount");
        require(
            INITIAL_SUPPLY == IERC20(address(this)).balanceOf(address(this)), "Initial supply must be minted already"
        );
        uint256 tokenAmount = INITIAL_SUPPLY;
        IERC20(address(this)).approve(UNISWAP_V2_ROUTER, tokenAmount);
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = IUniswapV2Router01(UNISWAP_V2_ROUTER)
            .addLiquidityETH{value: msg.value}(
            address(this),
            tokenAmount,
            tokenAmount, //  * 99 / 100, // Note: 1% slippage
            msg.value, // * 99 / 100, // Note: 1% slippage, how to minimize reality slippage?
            address(this),
            block.timestamp + 15 minutes
        );

        lp.initialLiq = liquidity;
        lp.initialLiqRemain = liquidity;
        require(liquidity > 0, "Liquidity not created");

        // Chuyển toàn bộ token thanh khoản về contract này !!!
        IERC20(pair).transfer(address(this), IERC20(pair).balanceOf(address(this)));

        emit InitialLiquidityAdded(amountToken, amountETH, liquidity);
        return liquidity;
    }

    /**
     * @dev claimTokenToBacker is used to mint the token of this contract to reward backers of this campaign or Alchemist as a rememberance for their support. This is a one time mint, that mean the backer will claim all token in 1 mint.
     * @dev only available for donation/tip campaign where only raiser get all raised fund.
     * @dev onlyBacker, onlyAlchemist can call this function with amount <= their shareAmt
     * @param to is the recipient (Alchemist or Backer)
     */
    function claimTokenToBacker(address to) external nonReentrant {
        // require(to == msg.sender, "Recipient must be the sender"); // turn off to allow other contract to call this function, e.g recipient can call via this function via GiveUp contract.
        require(
            thisCampaign.cId.haveFundTarget == 100,
            "This is not a donation/tip campaign so you cannot mint this token as rememberance, withdraw your LP tokens instead"
        );

        if (alchemist.addr != address(0) && to == alchemist.addr) {
            require(alchemistShare.shareAmt > 0, "Amount token for alchemist is 0");
            require(
                alchemistShare.shareAmt <= INITIAL_SUPPLY,
                "Amount token for alchemist is greater than INITIAL_SUPPLY !?"
            );
            require(!alchemistShare.isWithdrawn, "Alchemist already claimed");
            alchemistShare.isWithdrawn = true;
            alchemistShare.withdrawnTime = block.timestamp;
            _safeMint(to, alchemistShare.shareAmt);
        } else {
            uint256 index = backerIndex[to];
            require(totalBackers > 0 && index <= totalBackers, "Backer or Alchemist not found");
            require(to == backerShare[index].holderAddr, "Invalid backer or there is no alchemist");
            require(0 < backerShare[index].shareAmt, "Amount token for backer is 0"); // weird situation only
            require(
                backerShare[index].shareAmt <= INITIAL_SUPPLY,
                "Amount token for backer is greater than INITIAL_SUPPLY !?"
            );
            require(!backerShare[index].isWithdrawn, "Backer already claimed");
            backerShare[index].isWithdrawn = true;
            backerShare[index].withdrawnTime = block.timestamp;
            _safeMint(to, backerShare[index].shareAmt);
        }
    }

    /**
     * @dev for donation/tip campaign only
     * @dev raiserWithdrawDonationCampaignFunds is used by raiser to withdraw donation/tip campaign funds
     * @dev only raiser can call this function
     */
    function raiserWithdrawDonationCampaignFunds() public onlyRaiser nonReentrant {
        require(thisCampaign.cId.haveFundTarget == 100, "Not a donation/tip campaign");
        require(!raiserShare.isWithdrawn, "Raiser already withdrawn");

        raiserShare.isWithdrawn = true;
        raiserShare.withdrawnTime = block.timestamp;

        // withdraw native token, already deducted platform fee in GiveUp Lib function createTokenContractForParticipantsSelfWithdraw
        uint256 nativeTokenAmt = thisCampaign.cFunded.raiserPaidOut.nativeTokenAmt;
        if (nativeTokenAmt > 0) {
            (bool success,) = payable(msg.sender).call{value: nativeTokenAmt}("");
            require(success, "Native token transfer failed");
        }

        // withdraw whitelisted token
        withdrawWhitelistedToken(firstTokenAddr, thisCampaign.cFunded.raiserPaidOut.firstTokenAmt);
        withdrawWhitelistedToken(secondTokenAddr, thisCampaign.cFunded.raiserPaidOut.secondTokenAmt);
        withdrawWhitelistedToken(thirdTokenAddr, thisCampaign.cFunded.raiserPaidOut.thirdTokenAmt);

        emit RaiserFundsWithdrawn(msg.sender, nativeTokenAmt);
    }

    /**
     * @dev Withdraw whitelisted token to raiser
     * @param tokenAddr The address of the whitelisted token
     * @param amount The amount of token to withdraw
     */
    function withdrawWhitelistedToken(address tokenAddr, uint256 amount) private onlyRaiser {
        // Check if the amount is greater than 0 and the token address is not zero
        if (amount > 0 && tokenAddr != address(0)) {
            // Use call instead of transfer to avoid reentrancy
            // The `transfer` function can be reentrant, and if the token contract is not well-behaved,
            // it could lead to a reentrancy attack. Using `call` instead avoids this issue.
            (bool success,) = tokenAddr.call(abi.encodeWithSelector(ERC20.transfer.selector, msg.sender, amount));
            require(success, "Token transfer failed");
        }
    }

    /**
     * swapWLTokenToNativeToken is used to swap whitelisted token to native token
     * @param _tokenAddr is the address of whitelisted token
     * @param _amount is the amount of whitelisted token to swap
     * note: not yet tested / todo (5)
     */
    function swapWLTokenToNativeToken(address _tokenAddr, uint256 _amount) external onlyOperator {
        require(
            _tokenAddr == firstTokenAddr || _tokenAddr == secondTokenAddr || _tokenAddr == thirdTokenAddr,
            "Invalid token address"
        );
        require(_amount > 0, "Amount must be greater than 0");
        require(IERC20(_tokenAddr).balanceOf(address(this)) >= _amount, "Insufficient token balance");

        address[] memory path = new address[](2);
        path[0] = _tokenAddr;
        path[1] = WETH;

        uint256 balanceBefore = address(this).balance;

        IERC20(_tokenAddr).approve(address(uniswapV2Router02), _amount);

        IUniswapV2Router02(uniswapV2Router02).swapExactTokensForETH(
            _amount, 0, path, address(this), block.timestamp + 15 minutes
        );

        uint256 balanceAfter = address(this).balance;

        uint256 ethReceived = balanceAfter - balanceBefore;
        require(ethReceived > 0, "No ETH received from swap");

        nativeTokenAccrued.fromWLTokens += ethReceived;

        emit TokenSwappedForETH(_tokenAddr, _amount, ethReceived);
    }

    /**
     * getBackerNativeTokenContribution is used to get backer's native token contribution percentage and amount from GiveUp contract
     * @param _backerAddr is the address of backer
     * @return backer's percentage via native token. percentage is normal percentage (e.g 10% = 10) to avoid precision loss.
     */
    function getBackerNativeTokenContribution(address _backerAddr) public view returns (uint256, uint256) {
        return giveUpMainContract.getBackerNativeTokenContribution(_backerAddr, thisCampaign.cId.id);
    }

    /**
     * @dev ONLY FOR INITIAL LIQUIDITY: Removes initial liquidity from pool (for normal campaign and non profit campaign)
     * @param participant is the address of backer/raiser/alchemist
     * @return amountToken is the amount of token to remove
     * @return amountETH is the amount of native token to remove
     * Rule to remove or withdraw this initial liquidity:
     * - NOTE 1: THE MOST IMPORTANT CAUTION: Once liquidity is removed, only the native token will be sent to the participant's address, the campaign result token will be burnt to reduce the total supply of the token!!!
     * - only raiser/alchemist/backer can remove their initial liquidity together with their limited liquidity's fee accrue. this is one time (100%) removal. ONCE REMOVED, THEY CAN NOT ENTER THE POOL AGAIN!!! THIS IS A GAME OF "THE LAST WINNER STANDS"!!!
     * -- raiser have the priviledge to withdraw his liquidity anytime as a reward for his initiative contribution.
     * -- alchemist must wait for a fix period of 30 days before being able to withdraw his liquidity, similar to real world salary late 30 days payment.
     * -- backer can withdraw his liquidity anytime, but the liquidity amount will be controlled by the time of his contribution:
     *    + longer than BACKER_SAFE_LOCK_PERIOD (365 days): 100% of liquidity and no penalty in native token accrued (just repeat: the campaign result token always be burnt) plus future token reward.
     *    + less than BACKER_SAFE_LOCK_PERIOD (365 days): Only refund the native token capital that minus platform fee, minus amount for raiser and alchemist. THAT MEAN THE ACTUALLY AMOUNT THAT BACKER CAN GET BACK CAN LESS THAN THE AMOUNT HE CONTRIBUTED!!! However, he can withdraw a portion of accrued lp fee to compensate for the loss (if any). E.g: if a backer contributed 10 ETH, 1 ETH is for platform, raiser, alchemist, and the remaining 9 ETH go to liquidity pool. If the backer withdraws before 365 days, he can only get back 9 ETH as capital, and maximum 1 ETH of accrued lp fee.
     * - TODO (6):
     * -- These early participants who holds liquidity token (longer than BACKER_SAFE_LOCK_PERIOD) will be rewarded campaign result token proportionally in REWARD_SUPPLY token pool (as staking reward). After BACKER_SAFE_LOCK_PERIOD, the REWARD_SUPPLY will be 100% distributed to all initial liquidity token holders (including raiser, alchemist and all backers) as a reward for their contribution to the campaign.
     * -- Anyone who holds liquidity token can have the right to buy campaign result token with the discount price (in CALL_OPTION_SUPPLY token pool)
     */
    function removeInitialLiquidity(address participant)
        external
        nonReentrant
        returns (uint256 amountToken, uint256 amountETH)
    {
        require(participant != address(0), "Invalid participant address");
        require(pair != address(0), "Pair not set");
        uint256 sharePct;
        uint256 lockPeriod;
        bool isRaiser = participant == thisCampaign.cId.raiser;
        bool isAlchemist = participant == alchemist.addr;
        bool isBacker = false;
        uint256 minNativeTokenRefund; // for backer only: minimum native token capital backer will receive
        uint256 liquidity;
        uint256 feeAccrued; // the surplus in native token...

        if (isRaiser) {
            require(!raiserShare.isWithdrawn, "Raiser already withdrawn");
            raiserShare.isWithdrawn = true;
            raiserShare.withdrawnTime = block.timestamp;
            sharePct = raiserShare.sharePct;
        } else if (isAlchemist) {
            require(!alchemistShare.isWithdrawn, "Alchemist already withdrawn");
            alchemistShare.isWithdrawn = true;
            alchemistShare.withdrawnTime = block.timestamp;
            sharePct = alchemistShare.sharePct;
            lockPeriod = block.timestamp
                - max(thisCampaign.cFunded.raiserPaidOut.processedTime, thisCampaign.cFunded.alchemistPaidOut.processedTime);
            require(
                lockPeriod >= ALCHEMIST_LOCK_PERIOD,
                "Alchemist must wait for 30 days before withdrawing liquidity as service payment"
            );
        } else {
            uint256 index = backerIndex[participant];
            require(totalBackers > 0 && index <= totalBackers, "Backer not found");
            require(msg.sender == backerShare[index].holderAddr, "Not authorized");
            require(!backerShare[index].isWithdrawn, "Backer already withdrawn");
            backerShare[index].isWithdrawn = true;
            backerShare[index].withdrawnTime = block.timestamp;
            sharePct = backerShare[index].sharePct;
            isBacker = true;
            lockPeriod = block.timestamp
                - max(thisCampaign.cFunded.raiserPaidOut.processedTime, thisCampaign.cFunded.alchemistPaidOut.processedTime);
        }

        require(sharePct > 0, "No share percentage");

        if (isRaiser || isAlchemist) {
            // liquidity = (IERC20(pair).balanceOf(address(this)) * sharePct) / 100;
            liquidity = (IERC20(pair).balanceOf(address(this)) * sharePct) / 1e20; // divide 1e18 then 100 to get real amount.
        } else if (isBacker) {
            unchecked {
                // liquidity = IERC20(pair).balanceOf(address(this)) * sharePct / 100;
                liquidity = (IERC20(pair).balanceOf(address(this)) * sharePct) / 1e20; // divide 1e18 then 100 to get real amount.
            }
        }
        require(liquidity > 0, "Insufficient liquidity");

        IERC20(pair).approve(address(uniswapV2Router02), liquidity);

        (amountToken, amountETH) = uniswapV2Router02.removeLiquidityETH(
            address(this),
            liquidity,
            0, // note about slippage: revise later
            0, // note about slippage: revise later
            address(this), // withdraw to contract first to be sent later
            block.timestamp + 15 minutes // Note: revise later
        );

        require(amountToken > 0 && amountETH > 0, "Removal failed");

        if (isBacker) {
            (, uint256 amtBackerContributed) = getBackerNativeTokenContribution(participant);
            unchecked {
                // minNativeTokenRefund = i_realNativeTokenReceived * sharePct / 100;
                minNativeTokenRefund = (i_realNativeTokenReceived * sharePct) / 1e20; // divide 1e18 then 100 to get real amount.
            } // minNativeTokenRefund = amtBackerContributed - fee for raiser, alchemist
            if (lockPeriod < BACKER_SAFE_LOCK_PERIOD) {
                if (amountETH >= amtBackerContributed) {
                    // keep the surplus for nativeTokenAccrued.fromInitialLP as penalty for early withdrawal

                    /////////////////////////// TODO (7) chưa ghi nhận sự đóng góp này !!! ///////////////////////////
                    feeAccrued = amountETH - amtBackerContributed;
                    nativeTokenAccrued.fromInitialLP += feeAccrued;
                    amountETH = amtBackerContributed;
                    /////////////////////////// IMPORTANT (7) chưa ghi nhận sự đóng góp này !!! ///////////////////////////
                }
            } // todo (8): test thử có khi nào amountETH < minNativeTokenRefund nhiều không? có là bị lỗi
        }

        emit InitialLiquidityRemoved(msg.sender, amountToken, amountETH, feeAccrued);

        // Gửi ETH cho người tham gia
        (bool success,) = participant.call{value: amountETH}("");
        require(success, "ETH transfer failed");

        // Đốt token
        _burn(address(this), amountToken);
    }

    // set địa chỉ của ContributionNFT, GiveUp contract sẽ dùng sau khi gọi TokenTemplate1 thành công
    function setContributionNFTAddress(address _contributionNFTAddress) external onlyOwner {
        contributionNFT = ContributionNFT(_contributionNFTAddress);
    }

    // TODO (9): mint NFT (DRAFTING)
    // please note that there're alot vulnerabilities in function related to contributionNFT because it's just draft.
    // todo (10): via minting NFT workflow let re check sharePct, shareAmt again to make sure no error because there're complexity in handling precision loss
    function claimNFT(address to) external nonReentrant returns (uint256 tokenId) {
        // ... kiểm tra điều kiện ...
        require(address(contributionNFT) != address(0), "ContributionNFT not set");

        uint256 amount;
        string memory participantType;

        if (alchemist.addr != address(0) && to == alchemist.addr) {
            console.log("alchemistShare.sharePct: ", alchemistShare.sharePct, alchemistShare.holderAddr);
            amount = alchemistShare.sharePct > 0 ? 1 : 0;
            participantType = "Alchemist";
        } else {
            uint256 index = backerIndex[to];
            amount = backerShare[index].sharePct > 0 ? 1 : 0;
            participantType = "Backer";
        }
        require(amount > 0, "No contribution");
        // Mint NFT
        tokenId = contributionNFT.mintNFT(to, amount, participantType);
        return tokenId;
        // ... phần còn lại của hàm ...
    }

    ////////////////// getters functions //////////////////

    function getBackerIndex(address _backer) public view returns (uint256) {
        return backerIndex[_backer];
    }

    /**
     * used to mint the result token to qualified address, add checking if the address is a contract or not => note: so contract should not use it.
     */
    function _safeMint(address to, uint256 amount) private {
        require(to != address(0), "Mint to the zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds maximum supply");

        // Kiểm tra xem địa chỉ có phải là hợp đồng hay không
        uint256 size;
        assembly {
            size := extcodesize(to)
        }
        require(
            size == 0
                || ERC165Checker.supportsERC165(to) && ERC165Checker.supportsInterface(to, type(IERC20Receiver).interfaceId),
            "Recipient cannot receive ERC20 tokens"
        );

        _mint(to, amount);

        // Kiểm tra lại tổng cung sau khi mint
        require(totalSupply() <= MAX_SUPPLY, "Minting exceeds maximum supply");
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
