// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// 12.5 handle DOWN VOTE with rotten token, delete old comment
// 12.6 uint voterAddr => address[] voterAddr

uint256 constant MAX_RULES = 1000; // rules will be special campaign/post which content are for education/ guideline/ penalty ... purposes
// bytes32 constant SALT_2_CREATE_TOKEN = "Give Burden To Be Up";
// platform will have some priority token which is whitelisted by default
string constant FIRST_TOKEN = "firstToken"; // v129
string constant SECOND_TOKEN = "secondToken"; // v129
string constant THIRD_TOKEN = "thirdToken"; // v129
string constant EARLY_WITHDRAW = "EARLY_WITHDRAW"; // v129
string constant DELETED = "DELETED"; // v129
string constant REVERTING = "REVERTING"; // v129
uint256 constant BACKER_WITHDRAW_ALL_CODE = 99; // v129: uint256 because using with vote options, usually for a backer to withdraw ALL of his funds/votes of a campaign
uint256 constant RAISER_DELETE_ALL_CODE = 100; // v129: uint256 because using with vote options, usually for a raiser to DELETE his campaign and refund all if possible

enum campaignStatusEnum {
    OPEN, // 0
    APPROVED, // 1. 'TARGET MET!' -> stop receive fund
    REVERTED, // 2. 'TARGET NOT MET! -> 'REVERTING' -> 'REVERTED' when all backers withdrew (usually by donators)
    DELETED, // 3. raiser or platform deleted
    PAIDOUT, // 4. campaign successfully raised and paid out
    DRAFT, // 5. (reserved) to allow editing deadline, target, etc
    APPROVED_UNLIMITED, // 6. (reserved) 'TARGET MET!' -> STILL CAN receive more fund or used in case the campaign is No Target type
    REVERTING, // 7. campaign stop/failure and start reverting
        // ADD NEW FUTURE STATUS HERE, DO NOT CHANGE PREVIOUS ODER!
    PAUSED // 8. campaign is freezed (v129)

}

// C_ prefix mean Campaign
struct C_Id {
    uint256 id;
    address payable raiser;
    uint256[] group; // new in V005 9_1: can specify related / same category campaign
    uint256[] deList; // new in V005 9_1: move from ...
    uint256 haveFundTarget; // new in V006 10_1, the percentage to share between raiser and alchemist, MUST 0 <= haveFundTarget < 100, e.g 10 mean raiser get 10%, alchemist get 90% (after deducting platform fee)
    uint256 pctForBackers; // v129 // new in V008 12.1: percentage of "future" token reward for backers, set in the begining when creating campaign. fund will deduct platform's tax then this pctForBackers, remain will devide for raiser and alchemist
}

struct C_Info {
    string campaignType; // Wish, Dream, Solution ect
    string title;
    string description;
    string image; // url
    uint256 createdAt; // (~ timestamp)
    uint256 startAt; // usually use for a future date to start receive donation
    uint256 deadline; // all time in second
}

struct C_Funded {
    uint256 target; // campaign target of native currency like ETH, MATIC...
    uint256 amtFunded; // present amount of native currency like ETH, MATIC..., will be deducted when backer withdraw. Stop changing when campaign paid out.
    uint256 firstTokenTarget; // campaign target of first whitelisted priority token
    uint256 firstTokenFunded; // similar to amtFunded but for first priority token
    uint256 secondTokenTarget; // so on and so forth ...
    uint256 secondTokenFunded;
    uint256 thirdTokenTarget;
    uint256 thirdTokenFunded;
    uint256 equivalentUSDTarget;
    uint256 equivalentUSDFunded; // reserve for future use (with price oracle)
    uint256 totalDonating; // v129 counter of donation which > 0, any token count, even withdrawn donation (-> increasing only), used as counter for backer when donate/contribute.
    uint256 presentDonating; // v129 counter of donation which > 0, only count existing donation, use with singleRefund
    address payable[] voterAddr; // 12.6 uint -> address[] // new 12.3: used to count unique voter's address, start at 0
    PaidOut paidOut; // v129
}

struct PaidOut {
    bool nativeTokenPaidOut;
    bool firstTokenPaidOut;
    bool secondTokenPaidOut;
    bool thirdTokenPaidOut;
}

// use for backer that fund / donate a campaign (not for voter who not really fund / donate)
struct C_Backer {
    address payable backer; // backer of Campaign
    uint256 qty; // mean quantity backer donate to campaign
    string tokenSymbol; // v129 acceptedToken -> tokenSymbol // 12.5: "ROTTEN" mean DOWN VOTE, others mean UP VOTE
    // v129: add tokenAddr as unique key for ERC20 payment operation (not for native token), will affect: singleRefund, campaignDonatorTokenFunded, campaignOptionTokenFunded ...
    address tokenAddr; // for native token it'll be set to address(0) (default value)
    // uint256 timestamp; // when backer donate
    // bool refunded; // true when backer withdraw and vice versa
    FundInfo fundInfo; // v129 replace timestamp, refunded
    // TimeInfo timeInfo; // v129
    uint256 voteOption; // new in 11.0: default 0: general vote for whole campaign. 1-4: 4 official option of campaign (limit to 4)
    uint256 feedback; // new in 11.2: point to a campaign's id as a feedback
}

enum TimeLockStatus {
    No,
    Registered,
    Waiting,
    Approved
} // No = not yet refund & not yet registered for refund, Registered = registered for refund, Waiting = in waiting timeframe for refund, Approved = can refund now

// struct TimeInfo {
//     uint256 contributeAtTimestamp; // timestamp when backer contribute
//     uint256 requestRefundBlockNumber; // block number when backer initiate request refund
//     uint256 refundTimestamp; // timestamp when backer succesfully refunded
// }

struct FundInfo {
    uint256 contributeAtTimestamp; // > 0 mean timestamp of latest contribute
    uint256 requestRefundBlockNumber; // > 0 mean block number of latest request refund
    uint256 refundTimestamp; // > 0 mean timestamp of last refund
    bool refunded;
    TimeLockStatus timeLockStatus;
}

// 4 fix options of a campaign
struct C_Options {
    string option1;
    string option2;
    string option3;
    string option4;
}

// can be expand in future (add new status such as aftermath, valuation ect.)
struct C_Status {
    campaignStatusEnum campaignStatus;
    string acceptance; // new in V008 12.2: 1. use for proof of acceptance 2. special case - "FOL": "future" platform token symbol  that campaign's attendance will withdraw, only bigger share fund holder can assign it.
    string[] subAcceptance; // v129
        // uint256 pctForBackers; // new in V008 12.1: percentage of "future" token reward for backers, set in the begining when creating campaign. fund will deduct platform's tax then this pctForBackers, remain will devide for raiser and alchemist
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
// EXPERIMENTAL FEATURES BECAUSE RELATED TO PLATFORM'S TOKEN
struct ContractFunded {
    uint256 cTotalNativeToken; // campaign's total native token raised
    uint256 cTotalFirstToken; // 1st priority token raised (should be platform's token ??? but what if white list token change priority ???)
    uint256 cTotalSecondToken; // 2nd priority token raised (what if white list token change priority ???)
    uint256 cTotalThirdToken; // 3rd priority token raised (what if white list token change priority ???)
    uint256 cEquiTotalUSD; // (reserved) approx. USD value, intend to update when campaign payout
    uint256 totalFundedCampaign; // v129 move from outer scope // exclude refunded campaign in total campaign // numberOfCampaignsExcludeRefunded
    uint256 totalCampaignToken; // v129 success payout campaign will create it's own campaign token -> accrued here.
}

struct VoteData {
    uint256 option; // 0 is general campaign itself, 1 - 3 is for specific option of a campaign (4 options)
    string tokenSymbol;
}
// SHOULD SAVE FEEDBACK HERE ALSO because in C_Backer only save backer's feedback (not for voter's feedback)

struct SimpleRequestRefundVars {
    uint256[4] uintVars; // 0. campaignId, 1. option & RAISER_DELETE_ALL_CODE ect., 2. delayBlockNumberToPreventFrontRun, 3. reserved
    address payable[4] addressVars; // 0. contractOwner, 2. penaltyContract, 3. msg.sender, 4. reserved
    string[2] stringVars; // 0. i_nativeTokenSymbol, 1. reserved
    bool earlyWithdraw;
} // 12.5, v129

struct MappingCampaignIdTo {
    mapping(address => uint256) BackerNativeTokenFunded;
    mapping(address => mapping(address => uint256)) BackerTokenFunded;
    mapping(uint256 => uint256) OptionNativeTokenFunded;
    mapping(uint256 => mapping(address => uint256)) OptionTokenFunded;
    Alchemist alchemist;
    // address alchemist;
    // bool isAlchemistApproved;
    // bool raiserPrivilegeInNoTargetCampaign; // in Non Profit campaign (haveFundTarget = 0), raiser priviledge to propose Alchemist < community priviledge as default to assure community can take over, however, raiser can change this before campaign start.
    Community community;
    // address community;
    MultiPayment multiPayment;
    // bool multiPayment;
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
    string ratedObject;
    string content;
} // v129

struct CampaignToken {
    uint256 tokenIndex;
    address tokenAddr; // main field to know if a campaign is success and generate token
    string tokenSymbol;
    string tokenName;
}

// struct MappingAlchemist {
//     mapping(uint256 => RateDetail) rates; // index => RateDetail
//     uint256 totalRate;
//     bool platformPartner;
//     string moreInfo;
// } // v129

// struct MappingRaiser {
//     mapping(uint256 => RateDetail) rates; // index => RateDetail
//     uint256 totalRate;
//     string moreInfo;
// } // v129
