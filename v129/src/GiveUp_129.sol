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
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // https://forum.openzeppelin.com/t/cannot-find-reentrancyguard-in-openzeppelin-contracts-security/38710

interface IERC20 {
    function symbol() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external;
}

/**
 * @title main smart contract of GiveUp Platform
 * @author @Bezu0012
 * @notice purposes: to create and monitize 3 types of campaign: donate, collaborate to tokenize thoughts and actions, non profit.
 */
contract GiveUp129 is BackerTokenInterface, ReentrancyGuard {
    // immutable variables
    string public i_nativeTokenSymbol; // e.g ETH for Ethereum blockchain

    /*////////////////////////////////////////////////////////  
    STATE VARIABLES 
    ////////////////////////////////////////////////////////*/
    address payable public contractOwner; // person/platform deploy this contract,
    address payable public penaltyContract; // deplay sending withdrawal fund as penalty for early withdrawer.

    // Task: WE'LL USE MULTISIG IN MAINNET FOR contractOwner, penaltyContract

    uint256 public campaignTax; // % fee raiser will pay for this smart contract platform when their campaign is successfully paid out

    uint256 public presentCId; // normal campaign ID start at MAX_RULES (1000) // before v129 is numberOfCampaigns
    uint256 public ruleId = 0; // rule's ID start from 0 - 999, total 1000
    address payable public rulerAddr; // ruler address which can set rule campaign, MUST BE multisig
    uint256 public delayBlockNumberToPreventFrontRun = 3;

    // uint256 public numberOfCampaignsExcludeRefunded = 0; // exclude refunded campaign in total campaign
    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => MappingCampaignIdTo) mappingCId; // ref: https://ethereum.stackexchange.com/questions/65980/passing-struct-as-an-argument-in-call
    // further ref about gas: https://forum.openzeppelin.com/t/in-solidity-is-passing-a-structure-to-a-function-more-efficient-than-passing-the-individual-variables/33521/2

    /*////////////////////////////////////////////////////////  
    RESTRUCTURING campaignsOfAddress, whitelistedTokensAddressList, whitelistedTokensSymbolList below to avoid Denial of Service
    mapping(address => uint256[]) public campaignsOfAddress; // return campaign's id list created by an address
    address[] public whitelistedTokensAddressList;
    string[] public whitelistedTokensSymbolList;
    ////////////////////////////////////////////////////////*/
    mapping(address => uint256) private nextCampaignCounter; // return the total campaign created by an address
    mapping(address => mapping(uint256 => uint256)) private campaignsOfAddress; // new in v129: store campaignId created by an address with indexing! e.g address 0xd3ef....2398 -> 0 (first index) -> 1001 (have campaign Id 1001)

    // ... WORKING HERE ...
    address[] public WLAddresses; // white listed token addresses
    mapping(address => bool) private isTokenWhitelisted; // whitelistedTokensAddressList;
    /*////////////////////////////////////////////////////////  
    lead to reducing/changing these variables: whitelistedTokensSymbolList, whitelistedTokens, tokenAddrToSymbol
    and affect function such as: GiveUpLib2.requestRefund ...
    q: NOTE: WLAddresses need test gas fee for big list (1k/ 10k items)
    ////////////////////////////////////////////////////////*/

    // mapping(string => bool) public whitelistedTokensSymbolList; // if true: that token's symbol is whitelisted (this parameter is unimportant and can be cut in future)
    // // accepting whitelist ERC20 token
    // mapping(string => address) public whitelistedTokens;  // token symbol => address
    // mapping(address => string) public tokenAddrToSymbol;

    mapping(uint256 => bool) private campaignExist; // projectExist
    // mapping(uint256 => address) private alchemist; // new in V008, Alchemist is problem solver set by platform's owner

    // NOTICE:
    mapping(address => string) private tokenAddrToPriority;
    mapping(string => address) private priorityToTokenAddr;
    // MUST BE: firstToken, secondToken, thirdToken to map with firstTokenTarget, firstTokenFunded ect.
    // temporary: need to revise in future
    mapping(uint256 => mapping(address => mapping(uint256 => VoteData))) private campaignOptionsVoted; // campaignId => voter @ => vote counter/ vote order => VoteData. 1 address can vote for multiple options of 1 campaign, detail: 0 is general campaign itself, 1 - 4 is for specific option of a campaign (hard code max 4 options)
    mapping(uint256 => mapping(uint256 => RateDetail)) private rate; // v129: campaignId -> rate index within the range of mappingCId[_id].fraudRateIndexes.rateId -> RateDetail : save normal rating of every participant in campaign.
    mapping(uint256 => mapping(uint256 => RateDetail)) private fraud; // v129: campaignId -> fraud index within the range of fraudReportId in mappingCId[_id].fraudRateIndexes.fraudReportId -> RateDetail of that fraud report. In general, fraud is a special case of rate.
    mapping(uint256 => mapping(address => FraudReport)) private backerFraudReport; // v129: campaignId -> backer's address -> FraudReport: useful to know if a backer has already reported fraud.

    /* RESTRUCTURE BELOW MAPPING TO struct MappingCampaignIdTo
    // mapping(uint256 => mapping(address => mapping(string => uint256))) public campaignDonatorTokenFunded; // campaignId => address donator => string wlToken symbol => uint256 amount. Save amount backer donated to a campaign, if campaign success, amount remain as a receipt, if campaign failed and donator withrew -> = 0
    // q: change wlToken symbol to @ (to ensure unique key) as below OR HAVE TO ENSURE symbol is unique?
    mapping(uint256 => mapping(address => mapping(address => uint256))) public campaignDonatorTokenFunded; // campaignId => address donator => string wlToken @ => uint256 amount. Save amount backer donated to a campaign, if campaign success, amount remain as a receipt, if campaign failed and donator withrew -> = 0
    mapping(uint256 => mapping(address => uint256)) public campaignDonatorNativeTokenFunded; // v129

    // mapping(uint256 => mapping(uint256 => mapping(string => uint256))) public campaignOptionTokenFunded; // campaignId => option number start at 0 => string wlToken symbol => uint256 amount. Save amount voter donated to an option of campaign, if campaign success, amount remain as a receipt, if campaign failed and donator withrew -> = 0. Use to know which option will be richest :)
    // q: change wlToken symbol to @ (to ensure unique key) as below OR HAVE TO ENSURE symbol is unique?
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public campaignOptionTokenFunded; // campaignId => option number start at 0 => string wlToken @ => uint256 amount. Save amount voter donated to an option of campaign, if campaign success, amount remain as a receipt, if campaign failed and donator withrew -> = 0. Use to know which option will be richest :)
    mapping(uint256 => mapping(uint256 => uint256)) public campaignOptionNativeTokenFunded; // v129
    */

    /* NEXT: make getter function for backer to access MappingCampaignIdTo info so they can know their constribution. */

    ContractFunded private contractFundedInfo;

    /*////////////////////////////////////////////////////////  
    EVENTS 
    ////////////////////////////////////////////////////////*/
    event Action(uint256 id, string actionType, address indexed executor, uint256 timestamp); // can be captured and processed by off-chain systems to track and analyze the state changes or actions happening within the contract.
    // Include: id of Campaign -> if id == 0 then actionType is function call (or combination of function name, tokenSymbol etc.) because id of Campaign always >= 1000, executor see code / dev's note.

    event GeneralLog(string message);

    modifier ownerOnly() {
        require(msg.sender == contractOwner, "You're not Contract Owner");
        _;
    }

    constructor(uint256 _campaignTax, string memory _nativeTokenSymbol) {
        contractOwner = payable(msg.sender);
        campaignTax = _campaignTax;
        i_nativeTokenSymbol = _nativeTokenSymbol;
        presentCId = MAX_RULES;
    }

    /**
     * set Campaign Final Token name and symbol
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

    // function createCampaignFinalToken(string memory _name, string memory _symbol, uint256 _forCampaignId)
    //     external
    //     returns (address)
    // {
    //     return GiveUpLib1.createCampaignFinalToken(
    //         _name, _symbol, _forCampaignId, mappingCId[_forCampaignId], contractFundedInfo
    //     );
    // }

    /**
     * for raiser to propose Alchemist
     * CAUTION: raiser must propose his prefer Alchemist before campaign start. However if raiser choose address(0) mean raiser need backers' community or platform's community to take over to propose Alchemist for him to pay out.
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
        // alchemist[_id] = alchemistAddr;
        mappingCId[_id].alchemist.addr = _alchemistAddr;
    }

    /**
     * Because by default community is allow to propose Alchemist in Non Profit campaign only, if raiser don't want that to happen, they have to manually turn off this option before their campaign start.
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
     * Community (include campaign's backers and platform's community) can propose Alchemist in 2 scenarios:
     * 1. Non profit campaign (haveFundTarget = 0) & raiserPrivilegeInNoTargetCampaign = false.
     * 2. ANY campaign that raiser was fraud or cheating.
     */
    function communityProposeAlchemist(uint256 _id, address payable _alchemistAddr) public {
        // msg.sender must be approved community address => CHECK HOW TO SET Community address?
        require(msg.sender == mappingCId[_id].community.presentAddr, "Invalid Community Address");
        require(
            (mappingCId[_id].alchemist.addr == address(0) && mappingCId[_id].alchemist.isApproved)
                || (campaigns[_id].cId.haveFundTarget == 0 && !mappingCId[_id].alchemist.raiserPrivilegeInNoTargetCampaign),
            "Unallowed scenarios"
        );
        mappingCId[_id].alchemist.addr = _alchemistAddr;
    }

    /**
     * Setting & Approving ALchemist rule:
     * - Raiser can set the prefered Alchemist when campaign created.
     * - haveFundTarget = 100 (no Alchemist involved), Raiser don't need to update Alchemist to pay out. Any Alchemist adderss works.
     * If Alchemist is involved in payout process, then it'll be proposed by raiser/ community and set by platform to avoid manipulation.
     * - haveFundTarget < 100, Raiser has the 1st priority to propose their selected Alchemist for platform to approve and set.
     * - haveFundTarget = 0, GIVEUP community have 2nd priority to propose Alchemist.
     * - Platform/ operator then proceed to change Alchemist after proposal's result.
     * NOTICE: IF CAMPAIGN IS ACCUSED OF FRAUD OR CHEATING, ALCHEMIST WILL BE SET TO ADDRESS(0) TO PREVENT RAISER TO PAY OUT UNTIL EVERY ACCUSATION IS RESOLVED.
     */
    // function approveAlchemist(uint256 _id, address alchemistAddr) public ownerOnly {
    function approveAlchemist(uint256 _id, bool _vetoFraudCampaign, string memory _proof) public ownerOnly {
        // Just approve whatever Alchemist address proposed by setting isAlchemistApproved to true
        // In case campaign is accused of fraud or cheating, alchemist will be set to address(0) but isAlchemistApproved still set to true as a combination code. Then operator should include proof about campaign's fraud.
        if (!_vetoFraudCampaign) {
            mappingCId[_id].alchemist.isApproved = true;
        } else if (_vetoFraudCampaign) {
            mappingCId[_id].alchemist.isApproved = true; // don't set to false
            mappingCId[_id].alchemist.addr = payable(address(0));
            mappingCId[_id].notes.push(_proof);
        } // else is the case raiser make mistake setting
    }

    /**
     * QUESTION: does Address(0) needed in some cases? such as resetting etc.???
     */
    function setCommunityAddress(uint256 _campaignId, address _communityAddr, string memory _proofOption)
        public
        ownerOnly
    {
        mappingCId[_campaignId].community.presentAddr = _communityAddr;
        mappingCId[_campaignId].community.proofs.push(_proofOption);
    }

    /**
     * Signing Campaign Acceptance Rule: are the proofs that raiser &/or alchemist aggree to provide to everyone publicly. Rule to decide who can sign acceptance:
     * - haveFundTarget = 0: Raiser have the right to propose code "2FOL" within timeframe to convert campaign success to platform's token and open campaign (~ voting) for this action, if success, platform will sign it with code "FOL" as final acceptance. Raiser can not self sign acceptance to prevent manipulation. He need alchemist to rate the campaign and sign acceptance.
     * - 0 < haveFundTarget <= 50: Only Alchemist can sign acceptance.
     * - 50 < haveFundTarget <= 100 : Only Raiser can sign acceptance.
     */
    function signAcceptance(uint256 _id, string memory _acceptance) public {
        // GiveUpLib2.signAcceptance(campaigns[_id], payable(alchemist[_id]), _acceptance);
        GiveUpLib2.signAcceptance(campaigns[_id], payable(mappingCId[_id].alchemist.addr), _acceptance);
    }

    /**
     * @dev Allows a backer of a campaign to report fraud.
     * @param _id The ID of the campaign.
     * @param _fraudProof The proof of fraud provided by the backer.
     * @dev This function returns the result, the fraud report id and the realtimepercentage of fraud (native token weighted)
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

        // // if (GiveUpLib1.checkAddWhiteListToken(tokenAddress, whitelistedTokensAddressList)) {  // old code before v129
        // // string memory symbol = ERC20(tokenAddress).symbol();
        // string memory symbol = IERC20(tokenAddress).symbol(); // Apr 24
        // // whitelistedTokens[symbol] = tokenAddress;
        // tokenAddrToSymbol[tokenAddress] = symbol;

        isTokenWhitelisted[_tokenAddress] = true; // v129
        WLAddresses.push(_tokenAddress); // v129
        tokenAddrToPriority[_tokenAddress] = _tokenPriority;
        priorityToTokenAddr[_tokenPriority] = _tokenAddress;

        // whitelistedTokensAddressList.push(tokenAddress); // v129
        // whitelistedTokensSymbolList.push(symbol); // old code before v129
        // whitelistedTokensSymbolList[symbol] = true; // v129
        // return true;
        // }
        // return false;
    }

    function removeWhiteListToken(
        address _tokenAddress // no need token symbol tokenAddress is enough
    ) public ownerOnly {
        require(isTokenWhitelisted[_tokenAddress], "Token is not whitelisted");
        // uint256 index = GiveUpLib1.checkRemoveWhiteListToken(tokenAddress, whitelistedTokensAddressList);
        // string memory tokenSymbol = whitelistedTokensSymbolList[index];
        // // Move the last element to the index to be removed
        // whitelistedTokensAddressList[index] = whitelistedTokensAddressList[whitelistedTokensAddressList.length - 1];
        // whitelistedTokensSymbolList[index] = whitelistedTokensSymbolList[whitelistedTokensSymbolList.length - 1];

        // // Remove the last element

        // whitelistedTokensAddressList.pop();
        // whitelistedTokensSymbolList.pop();
        isTokenWhitelisted[_tokenAddress] = false;
        // delete whitelistedTokens[tokenSymbol];
        // delete tokenAddrToSymbol[tokenAddress];
        string memory tokenPriority = tokenAddrToPriority[_tokenAddress];
        priorityToTokenAddr[tokenPriority] = address(0);
        tokenAddrToPriority[_tokenAddress] = "";
        (, uint256 index) = GiveUpLib1.findAddressIndex(_tokenAddress, WLAddresses, new address payable[](0));
        WLAddresses[index] = WLAddresses[WLAddresses.length - 1];
        WLAddresses.pop();
    }

    /**
     * Apr 24: obmit receive() function, adjust fallback() function to inform the sender to send native token only through donateToCampaign function.
     * Aug 24: obmit all of them to avoid syntax caution
     * QUESTION: If this contract receives ETH from other sender who use selfdestruct(), how to withdraw/handle this ETH !!!???.
     */

    // CAUTION: used by admin to manually transfer non whitelisted token (handle mis sent tokens etc.)
    // QUESTION: can token.transfer(to, amount) transfer any token?
    // function transferERC20(ERC20 token, address to, uint256 amount) public ownerOnly {
    function transferERC20(IERC20 token, address to, uint256 amount) public ownerOnly {
        require(!isTokenWhitelisted[address(token)], "CAN NOT TOUCH WhiteList Token");
        // IMPORTANT QUESTION: what if a token was whitelisted, was acrued but now it's removed from whitelist? manual transfer this token will lead to intervention of raised fund !!!

        // QUESTION? should we allow incidentSenders of ERC20 to self withdrawing? => not now (because too complex)
        // QUESTION? should we have intermediate contract for the purpose of spam control to hold this withdrawal and apply penalty (prefer to hold and stake minimum 3 months) on it? (not now)

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
     * @param _pctForBackers percentage for backers, 0% = donate campaign, > 0% usually used for new token creation (meme)
     * @param _alchemistAddr v129: choose address(0) mean backer / platform community will appoint a new alchemist. Rule to go with _haveFundTarget: if 0 <_haveFundTarget < 100, _alchemistAddr must not be address(0) or raiser
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
        uint256 settingId = ruleId;
        if (msg.sender != rulerAddr) {
            settingId = presentCId;
        }
        Campaign storage campaign = campaigns[settingId];
        bool result = GiveUpLib2.createCampaign(
            _haveFundTarget, _pctForBackers, _content, _options, _timeline, _group, _deList, _fund, settingId, campaign
        );

        if (result) {
            campaignExist[settingId] = true;

            // replace below v128 code:
            // uint256[] storage campaignOfAddress = campaignsOfAddress[payable(msg.sender)]; // new
            // campaignOfAddress.push(settingId); // new to older version: only save campaign id

            // by this v129 code:
            uint256 campaignCounter = nextCampaignCounter[msg.sender]; // e.g 1st campaign of a raiser will make campaignCounter = 0
            campaignsOfAddress[msg.sender][campaignCounter] = settingId; // so we can know raiser's 1st campaign will have id = settingId (e.g. 1099)
            nextCampaignCounter[msg.sender]++;

            // alchemist[settingId] = 0x0000000000000000000000000000000000000000;
            mappingCId[settingId].alchemist.addr = _alchemistAddr;
            if (msg.sender == rulerAddr) {
                ruleId += 1;
            } else {
                presentCId += 1;
            }
            contractFundedInfo.totalFundedCampaign += 1;
            // campaign.cStatus.pctForBackers = _pctForBackers; // new in w008 12.1
            campaign.cId.pctForBackers = _pctForBackers; // v129

            emit Action(settingId, "CAMPAIGN CREATED", msg.sender, block.timestamp);
            return settingId; // presentCId - 1;
        } else {
            return 0; // new in V006 10.2
        }
    }

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
     * DELETE a campaign will refund all backers and change the status to "DELETED".
     * presently contract owner can delete for management purpose, later will assign role to operator and limit right of contract owner
     * - generally raiser can only delete campaign when it's fall out of raising timeframe. Except campaign with haveFundTarget > 0 and met the target ("APPROVED").
     * -> (NEXT: deloy new PAUSED status as grace time that can allow raiser to delete campaign whenever and whatever he wants)
     */
    function deleteCampaign(uint256 _id) public nonReentrant returns (bool) {
        SimpleRequestRefundVars memory simpleVars;
        simpleVars.uintVars[0] = _id;
        simpleVars.uintVars[1] = RAISER_DELETE_ALL_CODE; //  code 100 = RAISER_DELETE_ALL_CODE: to set requestRefund with value "DELETED"
        simpleVars.addressVars[0] = contractOwner;
        simpleVars.addressVars[1] = penaltyContract;
        simpleVars.stringVars[0] = i_nativeTokenSymbol;
        simpleVars.earlyWithdraw = false;
        simpleVars.uintVars[2] = delayBlockNumberToPreventFrontRun; // 240808

        // check condition inside GiveUpLib2.requestRefund, if requestRefund revert, deleteCampaign will also revert & return default return value which is false
        GiveUpLib2.requestRefund(
            simpleVars,
            campaigns[_id],
            campaignOptionsVoted,
            contractFundedInfo,
            mappingCId[_id],
            // campaignDonatorTokenFunded,
            // campaignOptionTokenFunded,
            // // whitelistedTokens, // v129: depricated,
            // campaignDonatorNativeTokenFunded, // v129
            // campaignOptionNativeTokenFunded, // v129
            tokenAddrToPriority
        );
        // numberOfCampaignsExcludeRefunded

        emit Action(_id, "CAMPAIGN DELETED", msg.sender, block.timestamp);

        return true;
    }

    // GUIDE: this function is used to donate native token to (a specifict option of) a campaign, donate 0 amount will be defined as basic "vote" for an option they like, > 0 amount will be defined as "advance vote" or "donation" which help to support a campaign (w/ option) stronger
    /*
    campaign can always receive native token as default
    */
    function donateToCampaign(
        uint256 _id, // campaign id
        // _option rule:
        /// 0: vote for campaign itself
        /// 1, 2, 3, 4: vote for specific option of a campaign (hard code max 4 options)
        /// 99: use code BACKER_WITHDRAW_ALL_CODE
        ///100: use code RAISER_WITHDRAW_ALL_CODE
        uint256 _option,
        uint256 _feedback // point to another campaign id that contain full feedback details
    ) public payable returns (bool) {
        require(campaignExist[_id], "Campaign not found");
        require(_option >= 0 && _option <= 4, "Invalid option"); // v129
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

        // new in 10.6: this part handle vote options -> SEE NOTE in params usage
        // CAUTION: 30 Oct 23: hard code only handle 4 options -> 12.3 increase to 5 options! Out of that consider invalid -> be careful when vote
        // not use vote result for simplicity
        GiveUpLib2.addOptionsVoted(_id, _option, i_nativeTokenSymbol, campaignOptionsVoted, campaign); // v129

        // check if (msg.value > 0) then updating related campaign's information
        if (msg.value > 0) {
            campaign.cFunded.amtFunded += msg.value;
            // campaignDonatorTokenFunded[_id][payable(msg.sender)][nativeTokenSymbol] += msg.value;  // v129
            // campaignDonatorNativeTokenFunded[_id][payable(msg.sender)] += msg.value; // v129: complex version
            mappingCId[_id].BackerNativeTokenFunded[payable(msg.sender)] += msg.value; // v129: after restructure it's simpler than above
            campaign.cBacker[campaign.cFunded.totalDonating] = C_Backer({
                backer: payable(msg.sender),
                qty: msg.value,
                // acceptedToken: nativeTokenSymbol, // v129 acceptedToken replaced by tokenSymbol, tokenAddr
                tokenSymbol: i_nativeTokenSymbol,
                tokenAddr: address(0), // when donating native token, tokenAddr will be address(0)
                // timestamp: block.timestamp,
                fundInfo: FundInfo({
                    contributeAtTimestamp: block.timestamp,
                    requestRefundBlockNumber: 0,
                    refundTimestamp: 0,
                    refunded: false,
                    timeLockStatus: TimeLockStatus.No
                }),
                // refunded: false,
                voteOption: _option,
                feedback: _feedback
            }); // holding fund
            campaign.cFunded.totalDonating += 1; // new: in 10.6 only count backer w/ >0 amount
            campaign.cFunded.presentDonating += 1; // v129
            contractFundedInfo.cTotalNativeToken += msg.value;

            // new in 10.7: handle campaignOptionTokenFunded regardless of haveFundTarget
            // if it's initialized then add it up else initialize it with this donation
            if (
                mappingCId[_id]
                    // campaignOptionTokenFunded[_id][_option][nativeTokenSymbol] != 0 // v129
                    // campaignOptionNativeTokenFunded[_id][_option] != 0 // v129: complex version
                    .OptionNativeTokenFunded[_option] != 0 // v129: after restructure it's simpler than above
            ) {
                // campaignOptionTokenFunded[_id][_option][nativeTokenSymbol] += msg.value;
                // campaignOptionNativeTokenFunded[_id][_option] += msg.value; // v129: complex version
                mappingCId[_id].OptionNativeTokenFunded[_option] += msg.value; // v129: after restructure it's simpler than above
            } else {
                // campaignOptionTokenFunded[_id][_option][nativeTokenSymbol] = msg.value;
                // campaignOptionNativeTokenFunded[_id][_option] = msg.value; // v129: complex version
                mappingCId[_id].OptionNativeTokenFunded[_option] = msg.value; // v129: after restructure it's simpler than above
            }

            // if fund not important (= 0) -> set status to APPROVED_UNLIMITED
            if (campaign.cId.haveFundTarget == 0) {
                if (campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN) {
                    campaign.cStatus.campaignStatus = campaignStatusEnum.APPROVED_UNLIMITED;
                }
            } else {
                // i.e campaign have fund target
                uint256 result = GiveUpLib1.checkFundedTarget(campaign);
                if (result == 1 || result == 3) {
                    campaign.cStatus.campaignStatus = campaignStatusEnum.APPROVED;
                    emit Action(
                        _id,
                        "CAMPAIGN BACKED & INIT APPROVED (campaign success!)", // this backer is final backer that make this campaign success
                        msg.sender,
                        block.timestamp
                    );
                    return true;
                }
            }
        }
        // new in 10.6, replace campaignOptionTotal, if donate amount = 0 then define it as a "vote", "vote" don't care about token type because the amount is 0 anyway
        else if (msg.value == 0) {
            emit Action(_id, "CAMPAIGN VOTED", msg.sender, block.timestamp);
            return true;
        }

        emit Action(_id, "CAMPAIGN BACKED", msg.sender, block.timestamp);
        return true;
    }

    // GUIDE: this function is used to donate NON native token (i.e ERC20) to (a specifict option of) a campaign ...
    function donateWhiteListTokenToCampaign(
        uint256 _id,
        uint256 _option, // see note in similar function donateToCampaign
        uint256 _amount,
        address _tokenAddr,
        uint256 _feedback // point to another campaign id that contain full feedback details
    ) public payable returns (bool) {
        require(isTokenWhitelisted[_tokenAddr], "Token not whitelisted (not yet accepted)"); // v129
        require(campaignExist[_id], "Campaign not found");
        require(_option >= 0 && _option <= 4, "Invalid option");
        Campaign storage campaign = campaigns[_id]; // v129
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

        // new in 10.6: this part handle vote options -> SEE NOTE in params usage
        // not use vote result for simplicity
        GiveUpLib2.addOptionsVoted(_id, _option, IERC20(_tokenAddr).symbol(), campaignOptionsVoted, campaign); // v129

        // check if (_amount > 0) then process & update related campaign's information
        if (_amount > 0) {
            // ERC20(_tokenAddr).transferFrom(msg.sender, address(this), _amount);
            IERC20(_tokenAddr).transferFrom(msg.sender, address(this), _amount);
            // donator MUST APPROVE SEPARATELY BEFORE DONATE!

            // if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode("firstToken"))) {
            if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode(FIRST_TOKEN))) {
                campaign.cFunded.firstTokenFunded += _amount;
                contractFundedInfo.cTotalFirstToken += _amount;
                // } else if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode("secondToken"))) {
            } else if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode(SECOND_TOKEN))) {
                campaign.cFunded.secondTokenFunded += _amount;
                contractFundedInfo.cTotalSecondToken += _amount;
                // } else if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode("thirdToken"))) {
            } else if (keccak256(abi.encode(tokenAddrToPriority[_tokenAddr])) == keccak256(abi.encode(THIRD_TOKEN))) {
                campaign.cFunded.thirdTokenFunded += _amount;
                contractFundedInfo.cTotalThirdToken += _amount;
            } else {
                emit GeneralLog(string(abi.encodePacked(tokenAddrToPriority[_tokenAddr])));
                // return false;
            }

            // update backer info include: campaignDonatorTokenFunded, campaign.cBacker
            // campaignDonatorTokenFunded[_id][payable(msg.sender)][_tokenAddr] += _amount; // v129: complex version
            mappingCId[_id].BackerTokenFunded[payable(msg.sender)][_tokenAddr] += _amount; // v129: after restructure it's simpler

            campaign.cBacker[campaign.cFunded.totalDonating] = C_Backer({
                backer: payable(msg.sender),
                qty: _amount,
                // acceptedToken: IERC20(_tokenAddr).symbol(), // v129 acceptedToken replaced by tokenSymbol, tokenAddr
                tokenSymbol: IERC20(_tokenAddr).symbol(),
                tokenAddr: _tokenAddr,
                // timestamp: block.timestamp,
                fundInfo: FundInfo({
                    contributeAtTimestamp: block.timestamp,
                    requestRefundBlockNumber: 0,
                    refundTimestamp: 0,
                    refunded: false,
                    timeLockStatus: TimeLockStatus.No
                }),
                // refunded: false,
                voteOption: _option,
                feedback: _feedback
            }); // holding fund

            if (keccak256(abi.encode(IERC20(_tokenAddr).symbol())) == keccak256(abi.encode("ROTTEN"))) {
                // campaign.cBacker[campaign.cFunded.totalDonating].refunded = true;
                campaign.cBacker[campaign.cFunded.totalDonating].fundInfo.refunded = true;
            } // 12.3: policy: DON'T REFUND 'ROTTEN' token!

            campaign.cFunded.totalDonating += 1; // new: in 10.6 only count backer w/ >0 amount
            campaign.cFunded.presentDonating += 1; // v129

            // new in 10.7: handle campaignOptionTokenFunded regardless of haveFundTarget
            // if it's initialized then add it up else initialize it with this donation
            if (
                mappingCId[_id]
                    // campaignOptionTokenFunded[_id][_option][_tokenAddr] != 0 // v129: complex version
                    .OptionTokenFunded[_option][_tokenAddr] != 0 // v129: after restructure it's simpler
            ) {
                // campaignOptionTokenFunded[_id][_option][_tokenAddr] += _amount; // v129: complex version
                mappingCId[_id].OptionTokenFunded[_option][_tokenAddr] += _amount; // v129: after restructure it's simpler
            } else {
                // campaignOptionTokenFunded[_id][_option][_tokenAddr] = _amount; // v129: complex version
                mappingCId[_id].OptionTokenFunded[_option][_tokenAddr] = _amount; // v129: after restructure it's simpler
            }

            // if fund not important (= 0) -> set status to APPROVED_UNLIMITED
            if (campaign.cId.haveFundTarget == 0) {
                if (campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN) {
                    campaign.cStatus.campaignStatus = campaignStatusEnum.APPROVED_UNLIMITED;
                } // different from smart contract/wishCtrl v0.0.5 9_1.sol: first backer/voter init OPEN -> APPROVED_UNLIMITED
            } else {
                // i.e campaign have fund target
                uint256 result = GiveUpLib1.checkFundedTarget(campaign); // check this special case
                if (result == 1 || result == 3) {
                    // at present just set to APPROVED, later will deploy workflow to set APPROVED_UNLIMITED
                    campaign.cStatus.campaignStatus = campaignStatusEnum.APPROVED;
                    emit Action(
                        _id,
                        "CAMPAIGN BACKED & INIT APPROVED", // this backer is final backer that make this campaign success
                        msg.sender,
                        block.timestamp
                    );
                    return true;
                }
            }
            // new in 10.6, replace campaignOptionTotal, only if donate amount = 0 then consider it as a vote and will note it, don't care about token type because the amount is 0 anyway
        } else if (_amount == 0) {
            emit Action(_id, "CAMPAIGN VOTED", msg.sender, block.timestamp);
            return true;
        }

        emit Action(_id, "CAMPAIGN BACKED", msg.sender, block.timestamp);

        // NOTE: later if we have price Oracle feed to calculate equivalentUSDFunded, just update checkFundedTargetNotMet function

        return true;
    }

    /**
     * requestRefund: for backer to withdraw the funds, if withraw after campaign was failed, set _earlyWithdraw = false, if withdraw when campaign is going on, set _earlyWithdraw = true
     * CAUTION: Early withdraw will get penalty in type of delay withdrawal, withrew fund will be hold in another staking smart contract but withdrawer will not get the staking rewards.
     * DO NOT REFUND 'ROTTEN' TOKEN!
     * raiser can also use this function to refund all donators (...use RAISER_DELETE_ALL_CODE)
     */
    function requestRefund(
        uint256 _id, // campaign ID
        bool _earlyWithdraw,
        uint256 _voteOption // see note in similar function donateToCampaign
    ) public nonReentrant returns (string memory) {
        SimpleRequestRefundVars memory simpleVars;
        simpleVars.uintVars[0] = _id;
        simpleVars.uintVars[1] = _voteOption;
        simpleVars.addressVars[0] = contractOwner;
        simpleVars.addressVars[1] = penaltyContract;
        simpleVars.stringVars[0] = i_nativeTokenSymbol;
        simpleVars.earlyWithdraw = _earlyWithdraw;
        simpleVars.uintVars[2] = delayBlockNumberToPreventFrontRun; // v129 240808
        simpleVars.addressVars[2] = payable(msg.sender); // v129 240811


        (string memory reportString, bool isTimeLock, TimeLockStatus returnTimeLockStatus) = GiveUpLib2.requestRefund(
            simpleVars,
            campaigns[_id],
            campaignOptionsVoted,
            contractFundedInfo,
            mappingCId[_id],
            // campaignDonatorTokenFunded,
            // campaignOptionTokenFunded,
            // // whitelistedTokens, // v129: depricated
            // campaignDonatorNativeTokenFunded, // v129
            // campaignOptionNativeTokenFunded, // v129
            tokenAddrToPriority
        );

        // isTimeLock == true mean there're time lock and withdrawer need to wait
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
        // isTimeLock is false here, mean refunds have successully made
        // if refund was not success, function will revert
        return reportString;
    }

    /* 21 Sep 23: requestRefund() chỉ cho backer rút sau khi campaign failed và quá deadline, nếu muốn cho rút ngay cả khi OPEN, chưa hết hạn v.v... thì phải thiết kế tránh spam hệ thống -> METHOD 1: cancelMyFunding ghi nhận việc rút trước hạn này, delay 1 thời gian mới cho rút lại để tránh spam & exploit */
    // METHOD 2: SIMPLY ALLOW WITHDRAW TO ANOTHER SC CONTROLLED BY THE PLATFORM, THIS SC THEN HANDLE THE REFUND w/ penalty or wo/ penalty

    function payOutCampaign(uint256 _id) public nonReentrant returns (bool) {
        bool result = GiveUpLib2.payOutCampaign(
            campaigns[_id],
            campaignTax,
            contractOwner,
            priorityToTokenAddr[FIRST_TOKEN],
            priorityToTokenAddr[SECOND_TOKEN],
            priorityToTokenAddr[THIRD_TOKEN],
            mappingCId[_id] // payable(mappingCId[_id].alchemist.addr)
        );
        if (result) {
            emit Action(_id, "CAMPAIGN PAIDOUT", msg.sender, block.timestamp);
        }
        return result;
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

    // function changeNativeTokenSymbol(string memory _nativeTokenSymbol) public ownerOnly {
    //     nativeTokenSymbol = _nativeTokenSymbol;
    // } // if change, how to handle previous ?

    function changeDelayBlockNumberToPreventFrontRun(uint256 _delayBlockNumber) public ownerOnly {
        require(_delayBlockNumber > 0, "Must > 0"); // v129
        delayBlockNumberToPreventFrontRun = _delayBlockNumber;
    }

    function changeRulerAddr(address _newAddr) public {
        require(msg.sender == contractOwner || msg.sender == rulerAddr, "You're not Authorized");
        require(_newAddr != address(0), "Invalid contract address");
        rulerAddr = payable(_newAddr);
    }

    /////// 240702: v129: deploying public getter function for mapping variables except (nested) mappings ///////

    // next campaign ID of a raiser's address (also the total campaign because includes all campaigns created by an address)
    function getNextCampaignCounterOfAddress(address raiser) public view returns (uint256) {
        return nextCampaignCounter[raiser];
    }

    // new in v129: store campaignId created by an address with indexing! e.g address 0xd3ef....2398 -> 0 (first index) -> 1001 (have campaign Id 1001 at 1st index)
    function getCIdFromAddressAndIndex(address raiser, uint256 index) public view returns (uint256) {
        return campaignsOfAddress[raiser][index];
    }

    function getIsTokenWhitelisted(address _tokenAddress) public view returns (bool) {
        return isTokenWhitelisted[_tokenAddress];
    }

    function getCampaignExist(uint256 campaignId) public view returns (bool) {
        return campaignExist[campaignId];
    }

    // function getAlchemist(uint256 campaignId) public view returns (address) {
    //     // return alchemist[campaignId];
    //     return mappingCId[campaignId].alchemist;
    // }

    function getTokenAddrToPriority(address _tokenAddress) public view returns (string memory) {
        return tokenAddrToPriority[_tokenAddress];
    }

    function getPriorityToTokenAddr(string memory _tokenPriority) public view returns (address) {
        return priorityToTokenAddr[_tokenPriority];
    }

    function getCampaignOptionsVoted(uint256 campaignId, address voter, uint256 voteOrder)
        public
        view
        returns (VoteData memory)
    {
        return campaignOptionsVoted[campaignId][voter][voteOrder];
    }

    function getBackerNativeTokenFunded(uint256 campaignId, address backer) public view returns (uint256) {
        return mappingCId[campaignId].BackerNativeTokenFunded[backer];
    }

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
            // returns (address, bool, address, bool, bool, string[] memory, uint256)
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

    function getBackersOfCampaign(uint256 _id) public view returns (C_Backer[] memory) {
        C_Backer[] memory backersOfCampaign = GiveUpLib1.getBackersOfCampaign(campaigns[_id]);
        return backersOfCampaign;
    }

    function getCampaigns() public view returns (CampaignNoBacker[] memory) {
        return GiveUpLib1.getNoBackersCampaigns(ruleId, presentCId, campaigns);
    }

    /**
     * getMaxMintAmount from interface BackerTokenInterface
     */
    function getMaxMintPctBaseOnNativeToken(address _backerAddr, uint256 _campaignId)
        public
        view
        returns (uint256 result)
    {
        uint256 backerNativeTokenFunded = mappingCId[_campaignId].BackerNativeTokenFunded[_backerAddr];
        uint256 totalNativeTokenFunded = campaigns[_campaignId].cFunded.amtFunded;
        if (totalNativeTokenFunded > 0) {
            result = (backerNativeTokenFunded * 100) / totalNativeTokenFunded;
        }
        return result;
    }

    // /**
    //  * getMaxMintAmountBaseOnNativeToken from interface BackerTokenInterface
    //  * @param _backerAddr backer address
    //  * @param _campaignId campaign id
    //  * @param _whiteListToken white list token address
    //  */
    // function getMaxMintPctBaseOnWLToken(address _backerAddr, uint256 _campaignId, address _whiteListToken)
    //     public
    //     view
    //     returns (uint256 result)
    // {
    //     uint256 backerTokenFunded = mappingCId[_campaignId].BackerTokenFunded[_backerAddr][_whiteListToken];
    //     // get token priority from whiteListToken
    //     string memory tokenPriority = getTokenAddrToPriority(_whiteListToken);
    //     // map it with priority in campaign such as firstTokenFunded, secondTokenFunded, thirdTokenFunded
    //     uint256 totalOfThatTokenFunded = campaigns[_campaignId].cFunded.firstTokenFunded;
    //     if (keccak256(abi.encode(tokenPriority)) == keccak256(abi.encode(FIRST_TOKEN))) {
    //         if (totalOfThatTokenFunded > 0) {
    //             result = (backerTokenFunded * 100) / totalOfThatTokenFunded;
    //         }
    //     }
    //     return result;
    // }

    function getCampaignFraudReport(uint256 campaignId, uint256 fraudIndex) public view returns (RateDetail memory) {
        return fraud[campaignId][fraudIndex];
    }

    function getCampaignRateDetail(uint256 campaignId, uint256 rateIndex) public view returns (RateDetail memory) {
        return rate[campaignId][rateIndex];
    }
}
