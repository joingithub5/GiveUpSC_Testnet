// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// v129 old comment save at 0bc09a6c694b99cd8c5daa9ef0a10f495e6adb8d - branch 129-newUI-240427

uint256 constant MAX_RULES = 1000; // rules will be special campaign/post which content are for education/ guideline/ penalty ... purposes
bytes32 constant SALT_2_CREATE_TOKEN = "Give Burden To Be Up :):):)";
// platform will have some priority token which is whitelisted by default
string constant FIRST_TOKEN = "firstToken"; // v129
string constant SECOND_TOKEN = "secondToken"; // v129
string constant THIRD_TOKEN = "thirdToken"; // v129
string constant EARLY_WITHDRAW = "EARLY_WITHDRAW"; // v129
string constant DELETED = "DELETED"; // v129
string constant REVERTING = "REVERTING"; // v129
uint256 constant BACKER_WITHDRAW_ALL_CODE = 99; // v129: used as vote options, for a backer to withdraw ALL of his funds/votes of a campaign
uint256 constant RAISER_DELETE_ALL_CODE = 100; // v129: used as vote options, for a raiser to DELETE his campaign and refund all if possible

enum campaignStatusEnum {
    OPEN, // 0
    APPROVED, // 1. 'TARGET MET!' -> stop receive fund
    REVERTED, // 2. 'TARGET NOT MET! -> 'REVERTING' -> 'REVERTED' when all backers withdrew
    DELETED, // 3. raiser or platform deleted
    PAIDOUT, // 4. campaign successfully raised and paid out
    DRAFT, // 5. (reserved) to allow editing deadline, target, etc
    APPROVED_UNLIMITED, // 6. (reserved) 'TARGET MET!' -> STILL CAN receive more fund, used in case the campaign is No Target type
    REVERTING // 7. campaign stop/failure and start reverting
        // ADD NEW FUTURE STATUS HERE, DO NOT CHANGE PREVIOUS ODER!
        // PAUSED // 8. campaign is freezed (v129)

}

// C_ prefix mean Campaign
/**
 * Rule:
 * If campaign is not a tip/donation campaign then all raised fund will be converted to strong token such as ETH, USDX to create liquidity pool with campaign's result token.
 * Backer FIRST -> be careful when setting pctForBackers, especially when set it to 100% because at that time haveFundTarget setting will be useless (no share for raiser and alchemist).
 * Raiser and Alchemist share the remain campaign's result token after deducting platform and backers' share.
 */
struct C_Id {
    uint256 id;
    address payable raiser;
    uint256[] group; // specify related (or agree with) campaign
    uint256[] deList; // specify dis-agree with campaign
    uint256 pctForBackers; // used to reward campaign's result token to backers, amount will be equal to (token's cap supply after deducting platform's share * pctForBackers).
    // OLD: v129 // new in V008 12.1: percentage of "future" token reward for backers, set in the begining when creating campaign. fund will deduct platform's tax then this pctForBackers, remain will devide for raiser and alchemist
    uint256 haveFundTarget; // NEW: = 0% = non profit/long term -> raiser get NOTHING WHATSOEVER, = 100% = tip/donation/no return ect -> raiser get ALL RAISED FUND BUT NOT CAMPAIGN'S RESULT TOKEN, = 0 < haveFundTarget < 100 is called normal campaign -> raiser BE REWARDED CAMPAIGN'S RESULT TOKEN, amount will be divided between raiser and alchemist after deducting platform and backers' share.
        // OLD: the percentage to share between raiser and alchemist, MUST 0 <= haveFundTarget < 100, e.g 10 mean raiser get 10%, alchemist get 90% (after deducting platform fee)
}

struct C_Info {
    string campaignType; // Wish, Dream, Solution etc.
    string title;
    string description;
    string image; // url
    uint256 createdAt; // timestamp
    uint256 startAt; // future date to start receive donation/vote
    uint256 deadline; // future date campaign will end
}

/**
 * "TARGET MET" Rule:
 * OFFICIAL: only when amtFunded met, other token's contribuition will be disable of considering as tip/donation.
 * (maybe in the future): Target will be met if one of the following condition is met: amtFunded, firstTokenFunded, secondTokenFunded, thirdTokenFunded, equivalentUSDFunded.
 */
struct C_Funded {
    RaisedFund raisedFund;
    uint256 voterCount; // together with campaignVoter will replace voterAddr to avoid for loop
    PaidOut paidOut; // record paidout triggering info
    AlchemistPaidOut alchemistPaidOut; // process payout to alchemist INDIRECTLY through "result token contract"
    RaiserPaidOut raiserPaidOut; // process payout to raiser INDIRECTLY through "result token contract"
}

// Refactoring C_Funded 240822
// 1. pack fund variable in C_Funded into a struct
struct RaisedFund {
    uint256 target; // campaign target of native currency like ETH, MATIC...
    uint256 amtFunded; // present amount of native currency like ETH, MATIC..., will be deducted when backer withdraw. Stop changing when campaign paid out (will not reset to 0 when campaign paid out).
    uint256 firstTokenTarget; // campaign target of first whitelisted priority token, planned for protocol's token
    uint256 firstTokenFunded; // similar to amtFunded but for first priority token
    uint256 secondTokenTarget; // (planned for platform's token)
    uint256 secondTokenFunded;
    uint256 thirdTokenTarget; // (planned for community's token) so on and so forth ...
    uint256 thirdTokenFunded;
    uint256 equivalentUSDTarget; // reserve for future use (with price oracle), LEAST SIGNIFICANT
    uint256 equivalentUSDFunded;
    uint256 totalDonating; // v129 counter of donation which > 0, any token count, even withdrawn donation (-> increasing only), used as counter for backer when donate/contribute.
    uint256 presentDonating; // v129 counter of donation which > 0, only count existing donation, use with singleRefund etc
        // address payable[] voterAddr; // used to count unique voter's address, start at 0 (deprecated)
}

// RaiserPaidOut: record the raised fund raiser get from campaign paid out following the pay out rules (such as deducting platform's tax, backers' share, etc), in general paidout to raiser indirectly through "result token contract"
struct RaiserPaidOut {
    // uint256 campaignTokenAmt; // amount of campaign's result token raiser get (if available)
    uint256 nativeTokenAmt; // amount of native token raiser get (if available)
    uint256 firstTokenAmt; // similar as above
    uint256 secondTokenAmt;
    uint256 thirdTokenAmt;
    uint256 equivalentUSDAmt; // (reserved) calculated when campaign "APPROVED" or when payout
    uint256 processedTime; // timestamp when raiser trigger paid out
    bool processed; // general flag to prevent reentrancy attack, help to make 1 time payment to raiser
}

struct AlchemistPaidOut {
    // uint256 campaignTokenAmt; // amount of campaign's result token alchemist get (if available)
    uint256 equivalentUSDAmt; // calculated when campaign "APPROVED" or when payout
    uint256 processedTime; // timestamp when alchemist trigger paid out
    bool processed; // similar to RaiserPaidOut
}

// used as guard to reentrancy attack, 1st check point to pay platform tax
struct PaidOut {
    bool nativeTokenPaidOut; // if true mean paidout for this token to platform have been proceeded successfully
    bool firstTokenPaidOut; // similar to above
    bool secondTokenPaidOut;
    bool thirdTokenPaidOut;
    bool equivalentUSDPaidOut;
}

// use for backer that fund / donate a campaign (not for voter who not really fund / donate)
struct C_Backer {
    address payable backer; // backer of Campaign
    uint256 qty; // mean quantity backer donate to campaign
    string tokenSymbol; //  "ROTTEN" mean DOWN VOTE, others mean UP VOTE
    address tokenAddr; // key for ERC20 payment, for native token it'll be set to address(0) (default value)
    FundInfo fundInfo; // v129 replace timestamp, refunded in previous version and include TimeLockStatus for later use
    uint256 voteOption; // default 0: general vote for whole campaign. 1-4: 4 official option of campaign (limit to 4)
    uint256 feedback; // point to another campaign's id as a feedback
}

// reserve (not yet deployed atm)
enum TimeLockStatus {
    No,
    Registered,
    Waiting,
    Approved
} // No = not yet refund & not yet registered for refund, Registered = registered for refund, Waiting = in waiting timeframe for refund, Approved = can refund now

struct FundInfo {
    // fund = a contribution of backer
    uint256 contributeAtTimestamp; // > 0 mean timestamp of latest contribute
    uint256 requestRefundBlockNumber; // > 0 mean block number of latest request refund (may also be used to prevent front running)
    uint256 refundTimestamp; // > 0 mean timestamp of last refund
    bool refunded; // mainly used for refund, avoid reentrancy attack
    TimeLockStatus timeLockStatus; // (planning to prevent front running)
}

// 4 fix options of a campaign. Option rule:
// 0: vote for campaign itself
// 1, 2, 3, 4: vote for specific option of a campaign (hard code max 4 options)
struct C_Options {
    string option1;
    string option2;
    string option3;
    string option4;
}

// can be expand in future (by adding new status such as aftermath, valuation ect.)
struct C_Status {
    campaignStatusEnum campaignStatus;
    string acceptance; // 1. use for proof of acceptance 2. special case - "FOL": "future" platform token symbol that campaign's attendance will withdraw (different from campaign's result token)
    string[] subAcceptance; // v129
}

struct Campaign {
    C_Id cId;
    C_Info cInfo;
    C_Funded cFunded;
    mapping(uint256 => C_Backer) cBacker;
    C_Options cOptions;
    C_Status cStatus;
}

struct CampaignNoBacker {
    C_Id cId;
    C_Info cInfo;
    C_Funded cFunded;
    C_Options cOptions;
    C_Status cStatus;
}

// save total amount of each type of currency this contract has collected
// remember to deduct when refunding to show only successfully raised amount
// NOTE: EXPERIMENTAL FEATURES BECAUSE RELATED TO PLATFORM'S TOKEN AND TOKEN PRIORITY CHANGING
struct ContractFunded {
    uint256 cTotalNativeToken; // campaign's total native token raised
    uint256 cTotalFirstToken; // 1st priority token raised (should be platform's token ??? but what if white list token change priority ???)
    uint256 cTotalSecondToken; // 2nd priority token raised (what if white list token change priority ???)
    uint256 cTotalThirdToken; // 3rd priority token raised (what if white list token change priority ???)
    uint256 cEquiTotalUSD; // (reserved) approx. USD value, intend to update when campaign payout
    uint256 totalFundedCampaign; // (exclude refunded campaign)
    uint256 totalCampaignToken; // v129 success payout campaign will create it's own campaign token -> counted here.
}

struct VoteData {
    uint256 option; // 0 is general campaign itself, 1 - 3 is for specific option of a campaign (4 options)
    string tokenSymbol;
}
// QUESTION: SHOULD SAVE FEEDBACK HERE ALSO because in C_Backer only save backer's feedback (not for voter's feedback)

// used in requestRefund, deleteCampaign (or payOutCampaign)
struct PackedVars1 {
    uint256[4] uintVars; // 0. campaignId (or campaignTax in payOutCampaign), 1. option & RAISER_DELETE_ALL_CODE ect., 2. delayBlockNumberToPreventFrontRun, 3. reserved
    address payable[4] addressVars; // 0. contractOwner, 1. penaltyContract, 2. msg.sender, 3. reserved (OR 1. firstPriorityToken, 2. secondPriorityToken, 3. thirdPriorityToken in payOutCampaign)
    string[2] stringVars; // 0. i_nativeTokenSymbol, 1. reserved
    bool earlyWithdraw;
}

struct MappingCampaignIdTo {
    mapping(address => uint256) BackerNativeTokenFunded;
    mapping(address => mapping(address => uint256)) BackerTokenFunded; // backer address => wl token address => token amt
    mapping(uint256 => uint256) OptionNativeTokenFunded;
    mapping(uint256 => mapping(address => uint256)) OptionTokenFunded;
    Alchemist alchemist;
    Community community;
    MultiPayment multiPayment;
    string[] notes; // for operator only
    FraudRateIndexes fraudRateIndexes;
    CampaignToken resultToken;
} // v129

struct Alchemist {
    address payable addr;
    bool isApproved;
    bool raiserPrivilegeInNoTargetCampaign; // in Non Profit campaign (haveFundTarget = 0), raiser priviledge to propose Alchemist < community priviledge as default to assure community can take over, however, raiser can change this before campaign start.
}

// prepresent the community of a campaign that backup for raiser
struct Community {
    address presentAddr; // set by platform base on present vote's result, no need to be payable
    address[] addrHistory;
    string[] proofs;
}

// for raiser/community to activate subAcceptance variable and always be active in initiate payment to alchemist after raiser checked and signed acceptance proof.
struct MultiPayment {
    uint256 planBatch; // payment batches which was initially planned to be sent to receiver, start with 1, 0 = not active
    address payable[] alchemistAddr; // list of alchemists received batches of payment, added when community change to new alchemist
}

struct FraudReport {
    bool isFraudNow; // present status of a FraudReport of a campaign from backer, true = backer reported as fraud, false = backer did not report as fraud.
    uint256 reportId; // present id of a FraudReport of a campaign from backer corresponding to isFraudNow
    uint256[] reportIDHistory; // collect all fraud report Ids of a campaign from a backer, added when backer both add and remove report. e.g [5, 99, 1001] may mean backer add fraud report id 5, backer remove fraud report id 99, backer add fraud report id 1001
} // v129

// v129
struct FraudRateIndexes {
    uint256 rateId; // act as next id (or total) for normal rate. I.e always increase when have new rate
    uint256 fraudReportId; // (similar to rateId) act as next id for fraud report but can also used as total fraud report regardless of add or remove action from backers. I.e. always increase when backers add or remove report
    uint256 fraudPct; // realtime fraud pct from 0 - 100 %: add & deduct when backers report fraud and remove their report. Calculated from backer' weight of native token contribution.
    uint256 fraudReportCounter; // realtime fraud counter, add & deduct when backers report fraud and remove their report
}

/**
 * RateDetail is used in 2 scenarios:
 * 1. When campaign is going on: For backers to rate the campaign, report fraud etc.
 * 2. Aftermath of a campaign (after campaign payout): For raiser, alchemist, backers to rate each others such as warranty or after sale service or project abandon etc.
 *
 */
struct RateDetail {
    address rater;
    uint256 timestamp;
    uint256 star; // 0 - 5, 0 usually used for fraud report
    uint256 campaignId;
    string ratedObject; // e.g "raiser" mean that this raiser is being rated.
    string content;
} // v129

struct CampaignToken {
    uint256 tokenIndex;
    address tokenAddr; // main field to know if a campaign is success and generate token
    string tokenSymbol;
    string tokenName;
}
