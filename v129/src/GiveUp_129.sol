// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

/* 
GIVEUP CRYPTO
bezu0012@gmail.com
https://twitter.com/bezu0012
testnet MVP: https://giveup.vercel.app/ 
*/

/*////////////////////////////////////////////////////////  
CHANGE LOG: 
Apr 24: commenting & guidance, prepare for security _review
////////////////////////////////////////////////////////*/

/*////////////////////////////////////////////////////////  
Brief: only import needed functions
Change from:   import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
Ref:        https://g.co/gemini/share/117b1dc6710b
////////////////////////////////////////////////////////*/

import {GiveUpLib1} from "./lib/GLib_Base1.sol";
import {GiveUpLib2} from "./lib/GLib_Base2.sol";
import "./GlobalVariables_12x.sol";
import "./BackerTokenInterface.sol";
import {TokenTemplate1} from "./TokenTemplate1.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // https://forum.openzeppelin.com/t/cannot-find-reentrancyguard-in-openzeppelin-contracts-security/38710

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// temporary import for debug
import {console, console2} from "forge-std/Test.sol";

interface IERC20 {
    function symbol() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external;
}

/**
 * @title main smart contract of GiveUp Platform
 * @author @Bezu0012
 * @notice purposes: to create and monitize 3 types of campaign:
 * - "donate or tip campaign": raiser will get all fund and reward backer, alchemist campaign result token as rememberance.
 * - "collaboration campaign": this is so call normal campaign where raiser collaborate with alchemist to tokenize thoughts and actions: raised fund after deducting platform fee will be pool with campaign token (similar to newly created ERC20 token in pump.fun). How to set the share percentage for each participant (raiser, alchemist, backer) are detailed in ... (todo 1). The reward and penalty rule for removing the initial liquidity or adding new liquidity are detailed in contract TokenTemplate1 -> function removeInitialLiquidity.
 * - "non profit campaign": similar to collaboration campaign but raiser get 0% of fund. The differences to all other campaign type are: 1. no limit in time and fund target, 2. raiser can't pay out in NON PROFIT campaign (they have to have Alchemist doing that) 3. Alchemist can trigger pay out anytime (community just need to control Alchemist through reporting fraud function coded in smart contract).
 * @dev NOTE: not yet fully tested and audit.
 */
contract GiveUp129 is BackerTokenInterface, ReentrancyGuard, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // immutable variables
    string public i_nativeTokenSymbol; // e.g ETH for Ethereum blockchain

    /*////////////////////////////////////////////////////////  
    STATE VARIABLES 
    ////////////////////////////////////////////////////////*/
    address payable public contractOwner; // person/platform deploy this contract,
    address payable public penaltyContract; // deplay sending withdrawal fund as penalty for early withdrawer. (note: not yet used)

    // Note: WE'LL USE MULTISIG IN MAINNET FOR contractOwner, penaltyContract

    uint256 public campaignTax; // % fee raiser will pay for this smart contract platform when their campaign is successfully paid out. Todo 2: change precision from interger to decimals e.g 0.1% etc.

    uint256 public nextCId; // normal campaign ID start at MAX_RULES (1000)
    uint256 public ruleId = 0; // rule campaign's ID start from 0 - 999, total 1000
    address payable public rulerAddr; // ruler address which can set rule campaign, MUST BE multisig
    uint256 public delayBlockNumberToPreventFrontRun = 3; // TODO 3: apply time lock mechanism or whatsoever to prevent front-running attack

    /////// campaign variables ///////
    mapping(uint256 => Campaign) public campaigns; // ALL CAMPAIGNS ARE HERE
    mapping(uint256 => MappingCampaignIdTo) mappingCId; // related information of a campaign, reference by campaignId
    mapping(address => uint256) private nextCampaignCounter; // return the total campaign created by an address
    mapping(uint256 => bool) private campaignExist; // projectExist
    mapping(address => mapping(uint256 => uint256)) private campaignsOfAddress; // store campaignId created by an address with indexing! e.g address 0xd3ef....2398 -> 0 (first index) -> 1001 (have campaign Id 1001)

    /////// whitelisted token variables ///////
    address[] public WLAddresses; // white listed token addresses, note: refer to how Uniswap store list of pairs
    mapping(address => bool) private isTokenWhitelisted;
    // @dev & NOTE: string for priority is hardcoded via constant FIRST_TOKEN, SECOND_TOKEN, THIRD_TOKEN in GlobalVariables_12x.sol to map with firstTokenTarget, firstTokenFunded ect.
    mapping(address => string) private tokenAddrToPriority;
    mapping(string => address) private priorityToTokenAddr;

    /////// campaign data (voted, rate, fraud report) variables ///////
    /**
     * Note about voting:
     * - 1 address can vote for multiple options of 1 campaign but not duplicate option.
     * - Vote option: 0 is general campaign itself, 1 - 4 is for specific option of a campaign (hard code max 4 options)
     * - 1 campaign can have max 4 options (not count 0 mean general vote mean not interested in specific option, suitable for backer who just want to donate and don't care which option will win)
     *
     */
    mapping(uint256 => mapping(address => mapping(uint256 => VoteData))) private campaignOptionsVoted; // e.g. campaignId => voter @ => vote counter/ vote order => VoteData.
    mapping(uint256 => mapping(uint256 => address)) private campaignVoter; // campaignId => sequence index => address: quick indexing Voter address of the campaign. (backer is also a voter but voter may not be a backer). Use together with voterCount in struct C_Funded.
    mapping(uint256 => mapping(uint256 => RateDetail)) private rate; // campaignId -> rate index within the range of mappingCId[_id].fraudRateIndexes.rateId -> RateDetail : save normal rating of every participant in campaign.
    mapping(uint256 => mapping(uint256 => RateDetail)) private fraud; // campaignId -> fraud index within the range of fraudReportId in mappingCId[_id].fraudRateIndexes.fraudReportId -> RateDetail of that fraud report. In general, fraud is a special case of rate.
    mapping(uint256 => mapping(address => FraudReport)) private backerFraudReport; // campaignId -> backer's address -> FraudReport: useful to know if a backer has already reported fraud.

    ContractFunded private contractFundedInfo; // total fund of all campaigns

    /*////////////////////////////////////////////////////////  
    EVENTS 
    ////////////////////////////////////////////////////////*/
    event Action(uint256 id, string actionType, address indexed executor, uint256 timestamp);
    event GeneralLog(string message);

    // NOTE: RESERVED FOR NEW STATE VARIABLES IN THE FUTURE
    // e.g:
    // uint256 public newStateVariable;
    // mapping(address => bool) public newMapping;
    // NOTE: ONLY ADD NEW STATE VARIABLES AT THE END OF THE LIST
    // TO AVOID AFFECTING STORAGE STRUCTURE OF CONTRACT

    modifier ownerOnly() {
        // require(msg.sender == contractOwner, "You're not Contract Owner");
        // require(msg.sender == owner(), "You're not Contract Owner");
        require(msg.sender == contractOwner && msg.sender == owner(), "You're not Contract Owner"); // temp for testnet, sê note in _syncContractOwner()
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _campaignTax, string memory _nativeTokenSymbol) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        contractOwner = payable(msg.sender);
        campaignTax = _campaignTax;
        i_nativeTokenSymbol = _nativeTokenSymbol;
        nextCId = MAX_RULES;
    }

    /**
     * Note: Do muốn giữ lại biến contractOwner trong giai đoạn test nên phải có hàm này để sync lại. Nếu trong code (kể cả test code) có bất kỳ hàm nào khác thay đổi quyền sở hữu, hãy đảm bảo gọi _syncContractOwner() sau khi thay đổi.
     * Khi triển khai chính thức sẽ dùng hẳn hàm owner() của thư viện openzeppelin để thống nhất theo chuẩn
     * @dev sync contractOwner with owner()
     */
    function _syncContractOwner() internal {
        contractOwner = payable(owner());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function transferOwnership(address newOwner) public virtual override onlyOwner {
        super.transferOwnership(newOwner);
        _syncContractOwner();
    }

    /**
     * set Campaign Final Token name and symbol: only Raiser and Community can call this function
     * 1. Raiser can set campaign final token name and symbol before campaign started
     * 2. Community can set campaign final token name and symbol after campaign started and token symbol is empty
     */
    function setCampaignFinalTokenNameAndSymbol(string memory _name, string memory _symbol, uint256 _forCampaignId)
        public
        returns (bool)
    {
        GiveUpLib1.setCampaignFinalTokenNameAndSymbol(
            _name, _symbol, _forCampaignId, mappingCId, campaigns[_forCampaignId], msg.sender
        );
        return true;
    }

    /**
     * for raiser to propose Alchemist
     * @dev NOTE CAUTION: raiser must propose his prefer Alchemist before campaign start. However if raiser choose address(0) mean raiser need backers' community or platform's community to take over to propose Alchemist for him to pay out.
     */
    function raiserChangeAlchemist(uint256 _id, address payable _alchemistAddr) public {
        require(campaigns[_id].cId.raiser == msg.sender, "You're not Raiser");
        require(campaigns[_id].cInfo.startAt > block.timestamp, "Can not propose Alchemist after campaign start");
        require(!mappingCId[_id].alchemist.isApproved, "Alchemist is already APPROVED");
        require(
            campaigns[_id].cId.haveFundTarget == 100 || campaigns[_id].cId.haveFundTarget == 0
                || (_alchemistAddr != address(0) && _alchemistAddr != msg.sender),
            "_alchemistAddr address must not be address(0) or raiser themself when 0 < haveFundTarget < 100"
        );
        mappingCId[_id].alchemist.addr = _alchemistAddr;
    }

    /**
     * @dev NOTE: Because by default community is allow to propose Alchemist in Non Profit campaign only, if raiser don't want that to happen, they have to manually turn off this option before their campaign start.
     */
    function turnOffCommunityProposeAlchemist(uint256 _id) public {
        require(campaigns[_id].cId.raiser == msg.sender, "You're not Raiser");
        require(
            campaigns[_id].cInfo.startAt > block.timestamp,
            "Raiser can't turn off community propose Alchemist option after campaign start"
        );
        mappingCId[_id].alchemist.raiserPrivilegeInNoTargetCampaign = true;
    }

    /**
     * Community (include campaign's backers and platform's community) after having a community address, can propose Alchemist of a campaign in 2 scenarios:
     * 1. Non profit campaign (haveFundTarget = 0) & raiserPrivilegeInNoTargetCampaign = false.
     * 2. ANY campaign that raiser was fraud or cheating.
     * Todo: present setCommunityAddress function is manual (should automate in future)
     */
    function communityProposeAlchemist(uint256 _id, address payable _alchemistAddr) public {
        require(msg.sender == mappingCId[_id].community.presentAddr, "Invalid Community Address");
        require(
            (mappingCId[_id].alchemist.addr == address(0) && mappingCId[_id].alchemist.isApproved)
                || (campaigns[_id].cId.haveFundTarget == 0 && !mappingCId[_id].alchemist.raiserPrivilegeInNoTargetCampaign),
            "Unallowed scenarios / Raiser don't want community to propose Alchemist (but community can change it by reporting fraud and make percentage of fraud report greater than the threadhold)"
        );
        mappingCId[_id].alchemist.addr = _alchemistAddr;
    }

    /**
     * Note about Setting, Resetting & Approving ALchemist rule:
     * - Raiser can set the prefered Alchemist when campaign created.
     * - haveFundTarget = 100 (no Alchemist involved), Raiser don't need to update Alchemist to pay out. Any Alchemist adderss works.
     * If Alchemist is involved in payout process, then it'll be proposed by raiser/ community and set by platform to avoid manipulation.
     * - haveFundTarget < 100, Raiser has the 1st priority to propose their selected Alchemist for platform to approve and set.
     * - haveFundTarget = 0, GIVEUP community have 2nd priority to propose Alchemist.
     * - Platform/ operator then proceed to change Alchemist after proposal's result.
     * NOTICE: IF CAMPAIGN IS ACCUSED OF FRAUD OR CHEATING, ALCHEMIST WILL BE SET TO ADDRESS(0) TO PREVENT RAISER TO PAY OUT UNTIL EVERY ACCUSATION IS RESOLVED.
     * - Normal workflow: at testnet, operator just manually approve whatever Alchemist address proposed by setting isAlchemistApproved to true.
     * - Resetting Alchemist: anytime when community take over and want to change Alchemist address, Operator can help to reset the Alchemist.
     * - Use composition of Alchemist address and isAlchemistApproved to manage status of Alchemist. e.g: (address(0), true) = resetting state, (address(0), false) = not approved yet, (some address X, true) = approved and ready to work.
     * Todo: change from manual to automatic
     */
    function approveAlchemist(uint256 _id, bool _vetoFraudCampaign, string memory _proof) public ownerOnly {
        if (!_vetoFraudCampaign) {
            mappingCId[_id].alchemist.isApproved = true;
        } else if (_vetoFraudCampaign) {
            mappingCId[_id].alchemist.isApproved = true; // don't set to false
            mappingCId[_id].alchemist.addr = payable(address(0));
            mappingCId[_id].notes.push(_proof);
        }
    }

    /**
     * @param _communityAddr: address of community, address(0) is resetting/unapproved state and vice ver sa
     * @param _proofOption: proof of community address suggestion (optional)
     */
    function setCommunityAddress(uint256 _campaignId, address _communityAddr, string memory _proofOption)
        public
        ownerOnly
    {
        mappingCId[_campaignId].community.presentAddr = _communityAddr;
        mappingCId[_campaignId].community.proofs.push(_proofOption);
    }

    /**
     * used when a campaign want to change token symbol
     */
    function resetTokenSymbol(uint256 _campaignId) public ownerOnly {
        require(mappingCId[_campaignId].resultToken.tokenAddr == address(0), "Token already created");
        mappingCId[_campaignId].resultToken.tokenSymbol = "";
    }

    /**
     * Signing Campaign Acceptance Rule: Campaign Acceptance are the proofs that raiser &/or alchemist aggree to provide to everyone publicly. Rule to decide who can sign acceptance:
     * If haveFundTarget > 0, who has the higher share will be able to sign acceptance, in case 50% - 50%, we'll give this privilege to alchemist.
     * - 0 < haveFundTarget <= 50: Only Alchemist can sign acceptance.
     * - 50 < haveFundTarget <= 100 : Only Raiser can sign acceptance.
     * - TODO BIG TODO: If haveFundTarget = 0: Raiser have the right to propose code "FOL" within timeframe to convert campaign success to platform's token and open campaign (~ voting) for this action, if success, platform will sign it with code "FOL" as final acceptance. Raiser can not self sign acceptance to prevent manipulation. He need alchemist to rate the campaign and sign acceptance.
     */
    function signAcceptance(uint256 _id, string memory _acceptance) public {
        GiveUpLib2.signAcceptance(campaigns[_id], payable(mappingCId[_id].alchemist.addr), _acceptance);
    }

    /**
     * @dev Allows a backer of a campaign to report fraud.
     * @param _id The ID of the campaign.
     * @param _fraudProof The proof of fraud provided by the backer.
     * @dev This function returns the result (true/false), the fraud report id and the realtimepercentage of fraud (native token weighted, e.g. 10 mean 10% of fraud)
     */
    function backerAddFraudReport(uint256 _id, string memory _fraudProof)
        public
        returns (bool success, uint256 index, uint256 fraudRealtimePct)
    {
        (success, index, fraudRealtimePct) =
            GiveUpLib1.backerReportFraud(_id, true, _fraudProof, campaigns, mappingCId, fraud, backerFraudReport);
        if (success) {
            emit Action(index, "(index): BACKER ADD FRAUD REPORT", msg.sender, block.timestamp);
        } else {
            emit Action(index, "Failed! Fraud report may already exist", msg.sender, block.timestamp);
        }
        return (success, index, fraudRealtimePct);
    }

    /**
     * counter action of backerAddFraudReport
     * @dev Backer remove his/her previous fraud report.
     * @param _id The ID of the campaign.
     * @param _reason The reason provided by the backer.
     * @dev This function returns the result, the fraud id and the realtimepercentage of fraud (native token weighted)
     */
    function backerRemoveFraudReport(uint256 _id, string memory _reason)
        public
        returns (bool success, uint256 index, uint256 fraudRealtimePct)
    {
        (success, index, fraudRealtimePct) =
            GiveUpLib1.backerReportFraud(_id, false, _reason, campaigns, mappingCId, fraud, backerFraudReport);
        if (success) {
            emit Action(index, "(index): BACKER REMOVE FRAUD REPORT", msg.sender, block.timestamp);
        } else {
            emit Action(index, "Failed! Fraud report may already removed", msg.sender, block.timestamp);
        }
        return (success, index, fraudRealtimePct);
    }

    function addWhiteListToken(address _tokenAddress, string memory _tokenPriority) public ownerOnly {
        require(!isTokenWhitelisted[_tokenAddress], "Token is already whitelisted");
        require(priorityToTokenAddr[_tokenPriority] == address(0), "Priority is already used");
        require(_tokenAddress != address(0), "Token address can not be address(0)");

        isTokenWhitelisted[_tokenAddress] = true;
        WLAddresses.push(_tokenAddress);
        tokenAddrToPriority[_tokenAddress] = _tokenPriority;
        priorityToTokenAddr[_tokenPriority] = _tokenAddress;
    }

    /**
     * TODO: present code assume whitelist token is normal address, need checking if whitelist token is payable
     */
    // IMPORTANT NOTE: if a token was whitelisted, was acrued in campaign but incidently removed from whitelist then fund will be stuck !!! => strict policy about whitelist token
    function removeWhiteListToken(address _tokenAddress) public ownerOnly {
        require(isTokenWhitelisted[_tokenAddress], "Token is not whitelisted");
        isTokenWhitelisted[_tokenAddress] = false;
        string memory tokenPriority = tokenAddrToPriority[_tokenAddress];
        priorityToTokenAddr[tokenPriority] = address(0);
        tokenAddrToPriority[_tokenAddress] = "";
        (, uint256 index) = GiveUpLib1.findAddressIndex(_tokenAddress, WLAddresses, new address payable[](0));
        WLAddresses[index] = WLAddresses[WLAddresses.length - 1];
        WLAddresses.pop();
    }

    /**
     * NOTE: This contract don't have receive(), fallback() function to avoid directly receive native token.
     * This contract can receive native token through donateToCampaign function or unexpected selfdestruct().
     * TODO: Handling when this contract receives ETH from other sender who use selfdestruct().
     */

    // @dev: used by admin to manually transfer non whitelisted token (handle mis sent tokens etc.)
    // Note: incidentSenders of ERC20 can not self withdrawing atm because it's too complex
    // QUESTION: can token.transfer(to, amount) transfer any token?
    // function transferERC20(ERC20 token, address to, uint256 amount) public ownerOnly {
    function transferERC20(IERC20 token, address to, uint256 amount) public ownerOnly {
        require(!isTokenWhitelisted[address(token)], "CAN NOT TOUCH WhiteList Token");

        uint256 erc20balance = token.balanceOf(address(this));
        require(amount <= erc20balance, "transfer amount > balance");
        emit Action(0, "transferERC20", to, block.timestamp);
        token.transfer(to, amount); // revert on failure, do not return true when transfer success
    }

    /**
     * @param _haveFundTarget : percentage for raiser, 0% = non profit/long term, 100=100% = tip/donation/no return ect, 0 < _haveFundTarget < 100 is called normal campaign
     * @param _content 0.campaignType, 1.title, 2.description, 3.image
     * @param _options can be blank for basic campaign purpose, max 4 options
     * @param _timeline startAt, deadline
     * @param _group Ids of campaigns that this campaign want to be part of, AGREE WITH or claim to be in the same group
     * @param _deList Ids of campaigns that this campaign want to ANTI
     * @param _fund 0.target, 1.firstTokenTarget, 2.secondTokenTarget, 3.thirdTokenTarget, 4.equivalentUSDTarget
     * @param _pctForBackers percentage for backers, 0% = donate campaign and don't reward token as rememberance, > 0% usually used for new token creation (meme), see general notes or guidance for detail. Note This is VIP parameter: raiser & alchemist only get the remain after deducting _pctForBackers, e.g: _pctForBackers = 100, raiser & alchemist will get 0% (NOTHING) of fund raised; _pctForBackers = 0, raiser & alchemist will get 100% of fund raised; _pctForBackers = 50, raiser & alchemist will get 50% of fund raised etc.
     * @param _alchemistAddr : address(0) mean backer / platform community will appoint a new alchemist. Coordination with _haveFundTarget, e.g if 0 <_haveFundTarget < 100, _alchemistAddr must not be address(0) or raiser to avoid manipulation.
     */
    function createCampaign(
        uint256 _haveFundTarget,
        string[] memory _content,
        string[] memory _options,
        uint256[] memory _timeline,
        uint256[] memory _group,
        uint256[] memory _deList,
        uint256[] memory _fund,
        uint256 _pctForBackers,
        address payable _alchemistAddr
    ) public returns (uint256) {
        require(0 <= _haveFundTarget && _haveFundTarget <= 100, "_haveFundTarget Invalid percentage");
        require(0 <= _pctForBackers && _pctForBackers <= 100, "_pctForBackers Invalid percentage");
        require(
            _haveFundTarget == 0 || (_alchemistAddr != address(0) && _alchemistAddr != msg.sender),
            "_alchemistAddr address must not be address(0) or raiser themself when 0 < haveFundTarget < 100"
        );
        uint256 settingId = ruleId; // start the process of setting campaign id.
        if (msg.sender != rulerAddr) {
            settingId = nextCId;
        }
        Campaign storage campaign = campaigns[settingId];
        bool result = GiveUpLib2.createCampaign(
            _haveFundTarget, _pctForBackers, _content, _options, _timeline, _group, _deList, _fund, settingId, campaign
        );

        if (result) {
            campaignExist[settingId] = true;

            uint256 campaignCounter = nextCampaignCounter[msg.sender]; // e.g 1st campaign of a raiser will make campaignCounter = 0
            campaignsOfAddress[msg.sender][campaignCounter] = settingId; // so we can know raiser's 1st campaign will have id = settingId (e.g. 1099)
            nextCampaignCounter[msg.sender]++;

            // alchemist[settingId] = 0x0000000000000000000000000000000000000000;
            mappingCId[settingId].alchemist.addr = _alchemistAddr;
            if (msg.sender == rulerAddr) {
                ruleId += 1;
            } else {
                nextCId += 1;
            }
            contractFundedInfo.totalFundedCampaign += 1; 
            campaign.cId.pctForBackers = _pctForBackers;

            emit Action(settingId, "CAMPAIGN CREATED", msg.sender, block.timestamp);
            return settingId; // nextCId - 1;
        } else {
            return 0; // note: platform owner should create a rule campaign to avoid conflict between campaign id 0 (rule campaign) and 0 (error)
        }
    }

    /**
     * @dev Update campaign information before campaign start
     * @param _id The ID of the campaign to update.
     * @param _haveFundTarget The new target for fund raising.
     * @param _pctForBackers The percentage for backers.
     * @param _stringFields The string fields to update.
     * @param _intFields The integer fields to update.
     * @param _arrayFields The array fields to update.
     * @param _stringValues The string values to update.
     * @param _uintValues The uint values to update.
     * @param _group The group ids to update.
     * @param _deList The deList ids to update.
     * @return bool: true if the campaign was updated successfully, false otherwise.
     */
    function updateCampaign(
        uint256 _id,
        uint256 _haveFundTarget,
        uint256 _pctForBackers,
        string[] memory _stringFields,
        string[] memory _intFields,
        string[] memory _arrayFields,
        string[] memory _stringValues,
        uint256[] memory _uintValues,
        uint256[] memory _group,
        uint256[] memory _deList
    ) public returns (bool) {
        require(0 <= _haveFundTarget && _haveFundTarget <= 100, "_haveFundTarget Invalid percentage");
        require(0 <= _pctForBackers && _pctForBackers <= 100, "_pctForBackers Invalid percentage");
        Campaign storage campaign = campaigns[_id];
        bool result = GiveUpLib2.updateCampaign(
            _haveFundTarget,
            _pctForBackers,
            _stringFields,
            _intFields,
            _arrayFields,
            _stringValues,
            _uintValues,
            _group,
            _deList,
            campaign
        );
        if (result) {
            emit Action(_id, "CAMPAIGN UPDATED", msg.sender, block.timestamp);
        }
        return result;
    }

    /**
     * For raiser to DELETE a campaign and refund all backers and change the status to "DELETED".
     * presently contract owner can delete for management purpose, later will assign role to operator and limit right of contract owner
     * - generally raiser can only delete campaign when it's fall out of raising timeframe. 
     * - raiser can not delete campaign with haveFundTarget > 0 and met the target ("APPROVED").
     * - raiser can not delete campaign if it already received fund -> todo: at present operator can delete it but we should expand this right to alchemist of that campaign. 
     * -> (IDEA?: deploy new PAUSED status as grace time that can allow raiser to delete campaign whenever and whatever he wants)
     */
    function deleteCampaign(uint256 _id) public nonReentrant returns (bool) {
        PackedVars1 memory packedVars1;
        packedVars1.uintVars[0] = _id;
        packedVars1.uintVars[1] = RAISER_DELETE_ALL_CODE; //  code 100 = RAISER_DELETE_ALL_CODE: to set requestRefund with value "DELETED"
        packedVars1.addressVars[0] = contractOwner;
        packedVars1.addressVars[1] = penaltyContract;
        packedVars1.stringVars[0] = i_nativeTokenSymbol;
        packedVars1.earlyWithdraw = false;
        packedVars1.uintVars[2] = delayBlockNumberToPreventFrontRun; // (not yet implement)
        packedVars1.addressVars[2] = payable(msg.sender);

        // check condition inside GiveUpLib2.requestRefund, if requestRefund revert, deleteCampaign will also revert & return false
        GiveUpLib2.requestRefund(
            packedVars1,
            campaigns[_id],
            campaignOptionsVoted,
            contractFundedInfo,
            mappingCId[_id],
            tokenAddrToPriority,
            campaignVoter
        );

        emit Action(_id, "CAMPAIGN DELETED", msg.sender, block.timestamp);

        return true;
    }

    // GUIDE: this function is used to donate native token to a campaign, donate 0 amount will be defined as basic "vote" for an option they like, > 0 amount will be defined as "advance vote" or "donation/contribution" which help to support a campaign stronger. The contributor can choose vote option to go with the contribution.
    /*
    campaign can always receive native token as default
    */
    function donateToCampaign(
        uint256 _id, // campaign id
        uint256 _option, // detail in GlobalVariables_12x.sol
        uint256 _feedback // point to another campaign id that contain full feedback details
    ) public payable returns (bool) {
        require(campaignExist[_id], "Campaign not found");
        require(_option >= 0 && _option <= 4, "Invalid option");
        Campaign storage campaign = campaigns[_id];
        require(
            (
                campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN && block.timestamp <= campaign.cInfo.deadline
                    && block.timestamp >= campaign.cInfo.startAt
            ) || campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED_UNLIMITED,
            string(
                abi.encodePacked(
                    "Campaign' status: ",
                    GiveUpLib1.campaignStatusToString(campaign.cStatus.campaignStatus),
                    " -> Campaign can NOT be donated."
                )
            )
        );

        GiveUpLib2.addOptionsVoted(_id, _option, i_nativeTokenSymbol, campaignOptionsVoted, campaignVoter, campaign);

        if (msg.value > 0) {
        // then updating related campaign's information:
            campaign.cFunded.raisedFund.amtFunded += msg.value;
            mappingCId[_id].BackerNativeTokenFunded[payable(msg.sender)] += msg.value; 

            ///////////// HERE IS THE PLACE WE HOLD FUND OF THIS CAMPAIGN ////////////////
            campaign.cBacker[campaign.cFunded.raisedFund.totalDonating] = C_Backer({
                backer: payable(msg.sender),
                qty: msg.value,
                tokenSymbol: i_nativeTokenSymbol,
                tokenAddr: address(0), // when donating native token, tokenAddr will be address(0)
                fundInfo: FundInfo({
                    contributeAtTimestamp: block.timestamp,
                    requestRefundBlockNumber: 0,
                    refundTimestamp: 0,
                    refunded: false,
                    timeLockStatus: TimeLockStatus.No
                }),
                voteOption: _option,
                feedback: _feedback
            });
            
            campaign.cFunded.raisedFund.totalDonating += 1; 
            campaign.cFunded.raisedFund.presentDonating += 1; 
            contractFundedInfo.cTotalNativeToken += msg.value;

            // if OptionNativeTokenFunded is initialized then add it up else initialize it with this donation
            if (
                mappingCId[_id].OptionNativeTokenFunded[_option] != 0 
            ) {
                mappingCId[_id].OptionNativeTokenFunded[_option] += msg.value; 
            } else {
                mappingCId[_id].OptionNativeTokenFunded[_option] = msg.value; 
            }

            // for non profit campaign -> set status to APPROVED_UNLIMITED
            if (campaign.cId.haveFundTarget == 0) {
                if (campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN) {
                    campaign.cStatus.campaignStatus = campaignStatusEnum.APPROVED_UNLIMITED;
                }
            } else {
                // for campaign have fund target (>0)
                uint256 result = GiveUpLib1.checkFundedTarget(campaign);
                if (result == 1 || result == 3) {
                    campaign.cStatus.campaignStatus = campaignStatusEnum.APPROVED;
                    emit Action(
                        _id,
                        "CAMPAIGN BACKED & INIT APPROVED (campaign success!)", // this contribution is final one that make this campaign success
                        msg.sender,
                        block.timestamp
                    );
                    return true;
                }
            }
        }
        // emit event correspondingly to msg.value
        else if (msg.value == 0) {
            emit Action(_id, "CAMPAIGN VOTED", msg.sender, block.timestamp);
            return true;
        }

        emit Action(_id, "CAMPAIGN BACKED", msg.sender, block.timestamp);
        return true;
    }

    // GUIDE: this function is used to donate NON native token which was whitelisted (i.e ERC20) to (a specifict option of) a campaign ...
    function donateWhiteListTokenToCampaign(
        uint256 _id,
        uint256 _option, // see note in similar function donateToCampaign
        uint256 _amount,
        address _tokenAddr,
        uint256 _feedback // point to another campaign id that contain full feedback details
    ) public payable nonReentrant returns (bool) {
        require(isTokenWhitelisted[_tokenAddr], "Token not whitelisted (not yet accepted)"); // v129
        require(campaignExist[_id], "Campaign not found");
        require(_option >= 0 && _option <= 4, "Invalid option");
        Campaign storage campaign = campaigns[_id]; 
        require(
            (
                campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN && block.timestamp <= campaign.cInfo.deadline
                    && block.timestamp >= campaign.cInfo.startAt
            ) || campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED_UNLIMITED,
            string(
                abi.encodePacked(
                    "Campaign' status: ",
                    GiveUpLib1.campaignStatusToString(campaigns[_id].cStatus.campaignStatus),
                    " -> Campaign can NOT be donated."
                )
            )
        );

        GiveUpLib2.addOptionsVoted(
            _id, _option, IERC20(_tokenAddr).symbol(), campaignOptionsVoted, campaignVoter, campaign
        ); 

        if (_amount > 0) {
            if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode(FIRST_TOKEN))) {
                campaign.cFunded.raisedFund.firstTokenFunded += _amount;
                contractFundedInfo.cTotalFirstToken += _amount;
            } else if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode(SECOND_TOKEN))) {
                campaign.cFunded.raisedFund.secondTokenFunded += _amount;
                contractFundedInfo.cTotalSecondToken += _amount;
            } else if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode(THIRD_TOKEN))) {
                campaign.cFunded.raisedFund.thirdTokenFunded += _amount;
                contractFundedInfo.cTotalThirdToken += _amount;
            } else {
                emit GeneralLog(string(abi.encodePacked(tokenAddrToPriority[_tokenAddr])));
            }

            // update backer info ...
            mappingCId[_id].BackerTokenFunded[payable(msg.sender)][_tokenAddr] += _amount; 

            ///////////// HERE IS THE PLACE WE HOLD FUND OF THIS CAMPAIGN ////////////////
            campaign.cBacker[campaign.cFunded.raisedFund.totalDonating] = C_Backer({
                backer: payable(msg.sender),
                qty: _amount,
                tokenSymbol: IERC20(_tokenAddr).symbol(),
                tokenAddr: _tokenAddr,
                fundInfo: FundInfo({
                    contributeAtTimestamp: block.timestamp,
                    requestRefundBlockNumber: 0,
                    refundTimestamp: 0,
                    refunded: false,
                    timeLockStatus: TimeLockStatus.No
                }),
                voteOption: _option,
                feedback: _feedback
            }); 

            // NOTE: policy: DON'T REFUND 'ROTTEN' token!
            if (keccak256(abi.encode(IERC20(_tokenAddr).symbol())) == keccak256(abi.encode("ROTTEN"))) {
                campaign.cBacker[campaign.cFunded.raisedFund.totalDonating].fundInfo.refunded = true;
            } 

            campaign.cFunded.raisedFund.totalDonating += 1; 
            campaign.cFunded.raisedFund.presentDonating += 1;

            // if OptionTokenFunded is initialized then add it up else initialize it with this donation
            if (
                mappingCId[_id].OptionTokenFunded[_option][_tokenAddr] != 0 
            ) {
                mappingCId[_id].OptionTokenFunded[_option][_tokenAddr] += _amount; 
            } else {
                mappingCId[_id].OptionTokenFunded[_option][_tokenAddr] = _amount; 
            }

            // if non profit campaign -> set status to APPROVED_UNLIMITED
            if (campaign.cId.haveFundTarget == 0) {
                if (campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN) {
                    campaign.cStatus.campaignStatus = campaignStatusEnum.APPROVED_UNLIMITED;
                } 
            } else {
                // for campaign have fund target (>0)
                uint256 result = GiveUpLib1.checkFundedTarget(campaign);
                if (result == 1 || result == 3) {
                    campaign.cStatus.campaignStatus = campaignStatusEnum.APPROVED;
                    emit Action(
                        _id,
                        "CAMPAIGN BACKED & INIT APPROVED", // this contribution is final one that make this campaign success
                        msg.sender,
                        block.timestamp
                    );
                    return true;
                }
            }
        } 
        // emit event correspondingly to _amount
        else if (_amount == 0) {
            emit Action(_id, "CAMPAIGN VOTED", msg.sender, block.timestamp);
            return true;
        }

        emit Action(_id, "CAMPAIGN BACKED", msg.sender, block.timestamp);

        // NOTE: later if we have price Oracle feed to calculate equivalentUSDFunded, just update checkFundedTargetNotMet function

        if (_amount > 0) {
            IERC20(_tokenAddr).transferFrom(msg.sender, address(this), _amount);
        }

        return true;
    }

    /**
     * requestRefund: for backer to withdraw the funds, if withraw after campaign was failed, set _earlyWithdraw = false, if withdraw when campaign is going on, set _earlyWithdraw = true
     * (IDEA ???: Early withdraw will get penalty in type of delay withdrawal, withrew fund will be hold in another staking smart contract but withdrawer will not get the staking rewards.)
     * NOTE: 'ROTTEN' TOKEN WILL NOT BE REFUNDED! They're garbage token until the right time come...
     * raiser can also use this function to refund all donators (...use RAISER_DELETE_ALL_CODE)
     */
    function requestRefund(
        uint256 _id, // campaign ID
        bool _earlyWithdraw,
        uint256 _voteOption // see note in similar function donateToCampaign
    ) public nonReentrant returns (string memory) {
        PackedVars1 memory packedVars1;
        packedVars1.uintVars[0] = _id;
        packedVars1.uintVars[1] = _voteOption;
        packedVars1.addressVars[0] = contractOwner;
        packedVars1.addressVars[1] = penaltyContract;
        packedVars1.stringVars[0] = i_nativeTokenSymbol;
        packedVars1.earlyWithdraw = _earlyWithdraw;
        packedVars1.uintVars[2] = delayBlockNumberToPreventFrontRun; // not yet implement
        packedVars1.addressVars[2] = payable(msg.sender); 

        (string memory reportString, bool isTimeLock, TimeLockStatus returnTimeLockStatus) = GiveUpLib2.requestRefund(
            packedVars1,
            campaigns[_id],
            campaignOptionsVoted,
            contractFundedInfo,
            mappingCId[_id],
            tokenAddrToPriority,
            campaignVoter
        );

        // below timelock note is just draft (whole if block can be commented and not affect anything)
        // isTimeLock == true mean there're time lock and withdrawer need to wait
        // isTimeLock is false here, mean refunds have successully made
        // if refund was not success, function will revert
        if (isTimeLock) {
            if (returnTimeLockStatus == TimeLockStatus.Registered) {
                reportString = string(
                    abi.encodePacked(
                        "Successfully registered early withdrawal at timelock index ",
                        reportString,
                        ". Please wait and make withdraw again AFTER ",
                        GiveUpLib2.toString(delayBlockNumberToPreventFrontRun),
                        " block numbers!"
                    )
                );
            } else if (returnTimeLockStatus == TimeLockStatus.Waiting) {
                reportString = string(
                    abi.encodePacked(
                        "You are in waiting period of ",
                        GiveUpLib2.toString(delayBlockNumberToPreventFrontRun),
                        " block numbers, please wait until it's over!. Index: ",
                        reportString
                    )
                );
            }
            emit Action(_id, reportString, msg.sender, block.timestamp);
        }

        return reportString;
    }

/** for raiser / alchemist to pay out campaign (closing a successfull campaign). In general, this action will:
 * - Withdraw raised fund to beneficiary upon rules
 * - Create campaign result token to act as rememberance token or add to liquidity pool
 * - For detail, see guidance in GLib_Base2.sol -> payOutCampaign, performPayout, createTokenContractForParticipantsSelfWithdraw function and TokenTemplate1 contract as a whole
 */
    function payOutCampaign(uint256 _id) public nonReentrant returns (TokenTemplate1 resultToken, uint256 liquidity) {
        PackedVars1 memory packedVars1;
        packedVars1.uintVars[0] = campaignTax;
        packedVars1.addressVars[0] = contractOwner;
        packedVars1.addressVars[1] = payable(priorityToTokenAddr[FIRST_TOKEN]);
        packedVars1.addressVars[2] = payable(priorityToTokenAddr[SECOND_TOKEN]);
        packedVars1.addressVars[3] = payable(priorityToTokenAddr[THIRD_TOKEN]);

        (resultToken, liquidity) =
            GiveUpLib2.payOutCampaign(campaigns[_id], mappingCId[_id], packedVars1, contractFundedInfo, msg.sender);
        if (address(resultToken) != address(0)) {
            if (campaigns[_id].cId.haveFundTarget == 100 && liquidity == 0) {
                if (!campaigns[_id].cFunded.raiserPaidOut.processed) {
                    emit Action(
                        _id,
                        "TRIGGERED DONATION CAMPAIGN PAIDOUT SUCCESS, PARTICIPANTS CAN CLAIM TOKEN THEMSELVES HERE: ",
                        address(resultToken),
                        block.timestamp
                    );
                }
            } else if (campaigns[_id].cId.haveFundTarget < 100 && liquidity > 0) {
                emit Action(
                    _id,
                    "TRIGGERED CAMPAIGN PAIDOUT SUCCESS, ALL PARTICIPANTS can interact with their LP token share in newly created token contract",
                    address(resultToken),
                    block.timestamp
                );
            }
        } else {
            emit Action(_id, "PAYOUT CAMPAIGN FAILED", msg.sender, block.timestamp);
        }
    }

    /**
     * claimTokenToBacker is used for backer or alchemist to claim their rememberance token in donation/tip campaign, this is one time claim
     */
    function claimTokenToBacker(uint256 _id) public {
        require(mappingCId[_id].resultToken.tokenAddr != address(0), "No result token for this campaign");
        TokenTemplate1 resultToken = TokenTemplate1(payable(mappingCId[_id].resultToken.tokenAddr));
        resultToken.claimTokenToBacker(address(msg.sender));
        // OR:
        // (bool success, ) = address(resultToken).call(
        //     abi.encodeWithSignature("claimTokenToBacker(address)", msg.sender)
        // );
        // require(success, "claimTokenToBacker failed");
    }

    function changeTax(uint256 _taxPct) public ownerOnly returns (uint256) {
        require(_taxPct >= 0 && _taxPct <= 100, "Invalid percentage");
        campaignTax = _taxPct;
        return campaignTax;
    }

    function changePenaltyContract(address payable _newContract) public ownerOnly {
        require(_newContract != address(0), "Invalid contract address");
        penaltyContract = _newContract;
    }

    /**
     * note: just testing ...
     */
    function changeDelayBlockNumberToPreventFrontRun(uint256 _delayBlockNumber) public ownerOnly {
        require(_delayBlockNumber > 0, "Must > 0"); // v129
        delayBlockNumberToPreventFrontRun = _delayBlockNumber;
    }

    function changeRulerAddr(address _newAddr) public {
        require(msg.sender == contractOwner || msg.sender == rulerAddr, "You're not Authorized");
        require(_newAddr != address(0), "Invalid contract address");
        rulerAddr = payable(_newAddr);
    }

    /////// public getter function  ///////

    // next campaign ID of a raiser's address (also the total campaign because includes all campaigns created by an address)
    function getNextCampaignCounterOfAddress(address raiser) public view returns (uint256) {
        return nextCampaignCounter[raiser];
    }

    // get campaignId created by an address with indexing! e.g address 0xd3ef....2398 -> 0 (first index) -> 1001 (have campaign Id 1001 at 1st index)
    function getCIdFromAddressAndIndex(address raiser, uint256 index) public view returns (uint256) {
        return campaignsOfAddress[raiser][index];
    }

    function getIsTokenWhitelisted(address _tokenAddress) public view returns (bool) {
        return isTokenWhitelisted[_tokenAddress];
    }

    function getCampaignExist(uint256 campaignId) public view returns (bool) {
        return campaignExist[campaignId];
    }

    function getTokenAddrToPriority(address _tokenAddress) public view returns (string memory) {
        return tokenAddrToPriority[_tokenAddress];
    }

    function getPriorityToTokenAddr(string memory _tokenPriority) public view returns (address) {
        return priorityToTokenAddr[_tokenPriority];
    }

    function getCampaignVoter(uint256 campaignId, uint256 voteIndex) public view returns (address) {
        return campaignVoter[campaignId][voteIndex];
    }

    function getCampaignOptionsVoted(uint256 campaignId, address voter, uint256 voteOrder)
        public
        view
        returns (VoteData memory)
    {
        return campaignOptionsVoted[campaignId][voter][voteOrder];
    }

    /**
     * Note: will be deprecated because we can use getBackerNativeTokenContribution and take 2nd return value(atm) as result
     */
    function getBackerNativeTokenFunded(uint256 campaignId, address backer) public view returns (uint256) {
        return mappingCId[campaignId].BackerNativeTokenFunded[backer];
    }

    /**
     * just get the amount of a whitelist token that have been funded in a campaign by a specific backer, include all options
     */
    function getBackerTokenFunded(uint256 campaignId, address backer, address whiteListToken)
        public
        view
        returns (uint256)
    {
        return mappingCId[campaignId].BackerTokenFunded[backer][whiteListToken];
    }

    function getOptionNativeTokenFunded(uint256 campaignId, uint256 option) public view returns (uint256) {
        return mappingCId[campaignId].OptionNativeTokenFunded[option];
    }

    /**
     * Query the amount of token that have been funded for an option in a campaign. (Note: the option might be funded by many whitelist tokens so you should call this function with all whitelist token)
     * @param campaignId campaign that have the option you want to know its info
     * @param option the option
     * @param whiteListToken the whitelist token funded for the option
     */
    function getOptionTokenFunded(uint256 campaignId, uint256 option, address whiteListToken)
        public
        view
        returns (uint256)
    {
        return mappingCId[campaignId].OptionTokenFunded[option][whiteListToken];
    }

    function getContractFundedInfo() public view returns (ContractFunded memory) {
        return contractFundedInfo;
    }

    function getRemainMappingCampaignIdTo(uint256 _id)
        public
        view
        returns (
            Alchemist memory,
            Community memory,
            MultiPayment memory,
            string[] memory,
            FraudRateIndexes memory,
            CampaignToken memory
        )
    {
        return (
            mappingCId[_id].alchemist,
            mappingCId[_id].community,
            mappingCId[_id].multiPayment,
            mappingCId[_id].notes,
            mappingCId[_id].fraudRateIndexes,
            mappingCId[_id].resultToken
        );
    }

    /**
     * get normal rate detail
     */
    function getRateDetail(uint256 _campaignId, uint256 _rateIndex) public view returns (RateDetail memory) {
        return rate[_campaignId][_rateIndex];
    }

    /**
     * get fraud report detail
     */
    function getRateDetailOfFraudReport(uint256 _campaignId, uint256 _fraudReportId)
        public
        view
        returns (RateDetail memory)
    {
        return fraud[_campaignId][_fraudReportId];
    }

    /* used to get fraud report of backer, especially to know if a backer has already reported fraud */
    function getBackerFraudReport(uint256 _campaignId, address _backer) public view returns (FraudReport memory) {
        return backerFraudReport[_campaignId][_backer];
    }

    /**
     * Returns an array of backers of a campaign. By default, it ONLY return present backers (i.e. not includes refunded backers, includeRefunded == false by default).
     * also be deployed in interface BackerTokenInterface
     */
    function getBackersOfCampaign(uint256 _id, bool includeRefunded) public view returns (C_Backer[] memory) {
        C_Backer[] memory backersOfCampaign = GiveUpLib1.getBackersOfCampaign(campaigns[_id], includeRefunded);
        return backersOfCampaign;
    }

    function getCampaignContributionsFromBacker(uint256 _id, address _backer, bool _refunded)
        public
        view
        returns (uint256, uint256[] memory)
    {
        return GiveUpLib1.getCampaignContributionsFromBacker(campaigns[_id], _backer, _refunded);
    }

    function getCampaigns() public view returns (CampaignNoBacker[] memory) {
        return GiveUpLib1.getNoBackersCampaigns(ruleId, nextCId, campaigns);
    }

    /**
     * get the contribution percentage (in native token) and corresponding amount of a backer in a specific campaign
     * also be deployed in interface BackerTokenInterface
     * percentage is normal percentage (e.g 10% = 10) to avoid precision loss.
     */
    function getBackerNativeTokenContribution(address _backerAddr, uint256 _campaignId)
        public
        view
        returns (uint256 pct, uint256 amt)
    {
        amt = mappingCId[_campaignId].BackerNativeTokenFunded[_backerAddr];
        uint256 totalNativeTokenFunded = campaigns[_campaignId].cFunded.raisedFund.amtFunded;
        if (totalNativeTokenFunded > 0) {
            pct = (amt * 100) / totalNativeTokenFunded;
        }
        return (pct, amt);
    }

    function getCampaignFraudReport(uint256 campaignId, uint256 fraudIndex) public view returns (RateDetail memory) {
        return fraud[campaignId][fraudIndex];
    }

    function getCampaignRateDetail(uint256 campaignId, uint256 rateIndex) public view returns (RateDetail memory) {
        return rate[campaignId][rateIndex];
    }
}
