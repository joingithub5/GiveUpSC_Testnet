//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console, console2} from "forge-std/Test.sol";
import {GiveUp129} from "../../src/GiveUp_129.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DeployGiveUp129} from "../../script/DeployGiveUp129.s.sol";
import "../unit/Input_Params.sol";
import "../../src/GlobalVariables_12x.sol";
import {CommunityToken} from "../mock/CTK.sol";
import {RottenToken} from "../mock/ROTTEN.sol";
import {AnyToken} from "../mock/ANY.sol";
import {CreateOrUpdate, DonateOrVote, WithdrawOrRefund, PaidoutOrDelete, Util} from "../../script/Interactions.s.sol";
import {TokenTemplate1} from "../../src/TokenTemplate1.sol";
import {GiveUpLib1} from "../../src/lib/GLib_Base1.sol";

import {UniswapDeployer} from "../../script/UniswapDeployer.s.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * Notes in this test:
 * MAX_RULES is the campaign Id of the latest campaign
 * SEND_VALUE is the target amount of native token (e.g. ETH) of test campaign
 * SEND_TOKEN_AMT is the target amount of white list token (e.g. CTK) of test campaign
 */
contract GiveUp129InteractionsTest is Test {
    GiveUp129 giveUp;
    CommunityToken ctk;
    RottenToken rotten;
    AnyToken any;

    IUniswapV2Factory factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    WETH deployedWeth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // Convert some variables to state variables
    DonationInfo public donationInfo;
    ContractFunded public contractFundedInfoBefore;

    // Helper function to initialize donation information
    function initDonationInfo() private {
        donationInfo = DonationInfo({
            nativeTokenDonation: 0,
            ctkTokenDonation: 0,
            balanceBefore: address(giveUp).balance,
            ctkBalanceBefore: ctk.balanceOf(address(giveUp))
        });
        contractFundedInfoBefore = giveUp.getContractFundedInfo();
    }

    function initializeTestParams() private pure returns (TestParams memory) {
        uint256[] memory haveFundTargets = new uint256[](1);
        haveFundTargets[0] = 100;
        // haveFundTargets[1] = 90; // will turn on later
        // haveFundTargets[2] = 0; // will turn on later

        uint256[] memory pctForBackers = new uint256[](3);
        pctForBackers[0] = 0;
        pctForBackers[1] = 90;
        pctForBackers[2] = 100;

        bool[] memory changeAlchemists = new bool[](2);
        changeAlchemists[0] = false;
        changeAlchemists[1] = true;

        return TestParams({
            haveFundTargets: haveFundTargets,
            pctForBackers: pctForBackers,
            changeAlchemists: changeAlchemists
        });
    }

    function setUp() external {
        uint256 platformFee = 0; // if pass these params from outside will cost gas
        string memory nativeTokenSymbol = "ETH";
        DeployGiveUp129 deployGiveUp129 = new DeployGiveUp129();
        (giveUp, ctk, rotten, any,,) = deployGiveUp129.run(platformFee, nativeTokenSymbol);
        vm.deal(RAISER1, STARTING_USER_BALANCE);
        vm.deal(RAISER2, STARTING_USER_BALANCE);
        vm.deal(BACKER1, STARTING_USER_BALANCE);
        vm.deal(BACKER2, STARTING_USER_BALANCE);
        console.log("address of giveUp, address of this GiveUp129Test: ", address(giveUp), address(this));
        UniswapDeployer deployer = new UniswapDeployer();
        deployer.run();
    }

    /**
     * allow to create campaign with any haveFundTarget, pctForBackers
     * hardcoded for raiser1
     */
    modifier campaignCreated(uint256 haveFundTarget, uint256 pctForBackers) {
        CreateCampaignInput memory c_input = initializeCreateCampaignData(haveFundTarget, pctForBackers);
        vm.prank(RAISER1);
        uint256 returnCId = giveUp.createCampaign(
            c_input.haveFundTarget,
            c_input.content,
            c_input.options,
            c_input.timeline,
            c_input.group,
            c_input.deList,
            c_input.fund,
            c_input.pctForBackers,
            ALCHEMIST1
        );
        assertEq(returnCId, giveUp.nextCId() - 1);
        _;
    }

    modifier initWLToken() {
        vm.startPrank(giveUp.contractOwner());
        if (!giveUp.getIsTokenWhitelisted(address(ctk))) {
            giveUp.addWhiteListToken(address(ctk), FIRST_TOKEN);
        }
        if (!giveUp.getIsTokenWhitelisted(address(rotten))) {
            giveUp.addWhiteListToken(address(rotten), "rotten");
        }
        assert(giveUp.getIsTokenWhitelisted(address(ctk)));
        assert(giveUp.getIsTokenWhitelisted(address(rotten)));
        vm.stopPrank();
        _;
    }

    function getLatestCampaign() public view returns (CampaignNoBacker memory) {
        CampaignNoBacker[] memory campaignsNoBacker = giveUp.getCampaigns();
        CampaignNoBacker memory campaign = campaignsNoBacker[(giveUp.nextCId() - 1) - MAX_RULES]; // cause getCampaigns() compressed and reindexed
        return campaign;
    }

    /**
     * NOTE This test should be expanded to check for vulnerability of addOptionsVoted, removeOptionsVoted
     */
    function getBackerVoteData(uint256 campaignId, address backer) public view returns (VoteData[] memory) {
        VoteData[] memory voteData = new VoteData[](10);
        uint256 length;
        for (uint256 i = 0; i < 10; i++) {
            VoteData memory voteAtIndex = giveUp.getCampaignOptionsVoted(campaignId, backer, i);
            if (keccak256(abi.encodePacked(voteAtIndex.tokenSymbol)) == keccak256(abi.encodePacked(""))) {
                console.log("token symbol not found at index", i, voteAtIndex.option, "so we break");
                break;
            }
            voteData[i] = voteAtIndex;
            length += 1;
            console.log("Vote Option At Index", i, voteAtIndex.option, voteAtIndex.tokenSymbol);
        }
        VoteData[] memory returnVoteData = new VoteData[](length);
        for (uint256 i = 0; i < length; i++) {
            returnVoteData[i] = voteData[i];
        }
        return returnVoteData;
    }

    /**
     * get the amount of raised fund (in native token) that raiser is credited from campaign. i.e Thanks to this raiser, the project raised this totalAmt of capital.
     * @param totalAmt total amount of raised fund (in native token)
     * @param haveFundTarget haveFundTarget param of campaign
     * @return amtRaiserIsCredited the amount of raised fund (in native token) that raiser is credited
     */
    function getAmountRaiserIsCredited(uint256 totalAmt, uint256 haveFundTarget)
        public
        view
        returns (uint256 amtRaiserIsCredited)
    {
        uint256 feeAmt = GiveUpLib1.calculateTax(totalAmt, giveUp.campaignTax());
        amtRaiserIsCredited = (totalAmt - feeAmt) * haveFundTarget / 100;
    }

    // Helper function to perform donation
    // in serie task to refactor paidOut_1
    function performDonate(uint256 campaignId, uint256 option, uint256 feedbackId, uint256 amount, bool expectRevert)
        private
        returns (bool)
    {
        DonateOrVote donateOrVote = new DonateOrVote();
        if (expectRevert) {
            vm.expectRevert();
        }

        try donateOrVote.donate(giveUp, campaignId, option, feedbackId, amount) returns (bool success) {
            if (success) {
                donationInfo.nativeTokenDonation += amount;
            }
            return success;
        } catch Error(string memory reason) {
            if (expectRevert) {
                require(
                    keccak256(abi.encodePacked(reason))
                        == keccak256(abi.encodePacked("Campaign' status: OPEN -> Campaign can NOT be donated."))
                        || keccak256(abi.encodePacked(reason))
                            == keccak256(abi.encodePacked("Campaign' status: APPROVED -> Campaign can NOT be donated.")),
                    "Unexpected revert reason"
                );
                return false;
            } else {
                revert(reason);
            }
        }
    }

    // Helper function to check results after donation
    // in serie task to refactor paidOut_1
    function checkDonationResults() private view {
        console.log("checkDonationResults");
        assertEq(getLatestCampaign().cFunded.raisedFund.amtFunded, donationInfo.nativeTokenDonation);
        ContractFunded memory contractFundedInfo = giveUp.getContractFundedInfo();
        assertEq(
            contractFundedInfo.cTotalNativeToken - contractFundedInfoBefore.cTotalNativeToken,
            donationInfo.nativeTokenDonation
        );
        assertEq(contractFundedInfo.totalFundedCampaign - contractFundedInfoBefore.totalFundedCampaign, 0); // TotalFundedCampaign did not deducted because this campaign is successfully paidout
        console.log(
            "contractFundedInfo.cTotalNativeToken >>",
            contractFundedInfo.cTotalNativeToken,
            "contractFundedInfo.cTotalFirstToken >>",
            contractFundedInfo.cTotalFirstToken
        );
        console.log(
            "getTotalFundedCampaign did not deducted because this campaign is successfully paidout: ",
            contractFundedInfo.totalFundedCampaign
        );
    }

    // in serie task to refactor paidOut_1
    function testAlchemistChange(uint256 campaignId, bool changeAlchemist) private returns (Alchemist memory) {
        Alchemist memory alchemistBeforeCampaignStart;
        if (!changeAlchemist) {
            // vm.startPrank(RAISER1);
            giveUp.raiserChangeAlchemist(campaignId, payable(address(0)));
            (alchemistBeforeCampaignStart,,,,,) = giveUp.getRemainMappingCampaignIdTo(campaignId);
            assertEq(address(0), alchemistBeforeCampaignStart.addr);
            // vm.stopPrank();
        } else {
            (alchemistBeforeCampaignStart,,,,,) = giveUp.getRemainMappingCampaignIdTo(campaignId);
        }
        return alchemistBeforeCampaignStart;
    }

    // in serie task to refactor paidOut_1
    function testDonateBeforeCampaignStart(uint256 campaignId) private {
        console.log("testDonateBeforeCampaignStart");
        // vm.startPrank(BACKER2);
        bool donateBeforeCampaignStart = performDonate(campaignId, 0, 0, SEND_VALUE, true);
        // vm.stopPrank();
        console.log(
            "1. test donateToCampaign which will fail because of startAt time: ",
            donateBeforeCampaignStart,
            " check contract balance = ",
            address(giveUp).balance
        );
        assertEq(donateBeforeCampaignStart, false, "Donation should fail before campaign start");
    }

    // in serie task to refactor paidOut_1
    function testDonateAfterCampaignStart(uint256 campaignId) private {
        console.log("testDonateAfterCampaignStart");
        // vm.warp(block.timestamp + 86400 * 4);
        // vm.startPrank(BACKER2);
        bool donateAfterCampaignStart = performDonate(campaignId, 0, 0, SEND_VALUE / 10, false);
        // vm.stopPrank();
        assertEq(donateAfterCampaignStart, true);
        assertEq(getLatestCampaign().cFunded.raisedFund.amtFunded, SEND_VALUE / 10);
    }

    // in serie task to refactor paidOut_1
    // function testVoteAndDonateWLToken(uint256 campaignId) private {
    function testVoteAndDonateWLToken(uint256 campaignId, address caller) private {
        DonateOrVote donateOrVote = new DonateOrVote();
        console.log("testVoteAndDonateWLToken");
        vm.startPrank(caller);
        bool voteWLTokenSuccess = donateOrVote.voteWLToken(giveUp, campaignId, 0, 0, ctk);
        vm.stopPrank();
        vm.startPrank(caller); // must have this to get the correct msg.sender
        bool donateWLTokenSuccess = donateOrVote.donateWLToken(giveUp, campaignId, 0, 1111, ctk, SEND_TOKEN_AMT);
        assertEq(giveUp.getBackerTokenFunded(campaignId, caller, address(ctk)), SEND_TOKEN_AMT);
        vm.stopPrank();
        console.log(
            "voteWLTokenAfterCampaignStart, donateWLTokenAfterCampaignStart: ", voteWLTokenSuccess, donateWLTokenSuccess
        );
        if (donateWLTokenSuccess) {
            donationInfo.ctkTokenDonation += SEND_TOKEN_AMT;
        }
    }

    // in serie task to refactor paidOut_1
    function testVoteDataAndFundRelated(uint256 campaignId, address backer) private {
        console.log("testVoteDataAndFundRelated");
        VoteData[] memory voteData = getBackerVoteData(campaignId, backer);
        for (uint256 i = 0; i < voteData.length; i++) {
            console.log("vote info of BACKER1", voteData[i].option, voteData[i].tokenSymbol);
            console.log(
                "quantity of CTK token fund for this option: ",
                giveUp.getOptionTokenFunded(campaignId, voteData[i].option, address(ctk))
            );
        }

        vm.prank(backer);
        string memory withdrawWIncorrectOption = giveUp.requestRefund(campaignId, true, 1);
        assertEq(withdrawWIncorrectOption, "Remove vote option FAILED + Nothing to refund");

        vm.prank(backer);
        // Arrange this backer purposely withdraw all contributions
        giveUp.requestRefund(campaignId, true, BACKER_WITHDRAW_ALL_CODE); // pair here
        C_Backer[] memory backers = giveUp.getBackersOfCampaign(campaignId, true);
        C_Backer memory latestBacker = backers[backers.length - 1];
        assertEq(latestBacker.backer, address(backer));
        assertEq(latestBacker.fundInfo.refunded, true); // ... with here
        assertEq(giveUp.getContractFundedInfo().cTotalFirstToken, 0); // ... with here
        assertEq(giveUp.getBackerTokenFunded(campaignId, backer, address(ctk)), 0); // ... with here
    }

    // in serie task to refactor paidOut_1
    function testDonateToMeetTarget(uint256 campaignId) private {
        console.log("testDonateToMeetTarget");
        // vm.startPrank(BACKER2);
        bool donateAfterCampaignStartWithTargetAmt = performDonate(campaignId, 0, 0, SEND_VALUE, false);
        assertEq(donateAfterCampaignStartWithTargetAmt, true);
        vm.expectRevert(
            "Campaign' status: APPROVED -> Can only refund if caller is the contract platform or Campaign expired & failed or in REVERTING period!"
        );
        string memory withdrawAfterCampaignMetTarget = giveUp.requestRefund(campaignId, true, BACKER_WITHDRAW_ALL_CODE);

        // NOTE TODO HERE: cần XEM LẠI hàm requestRefund trả về string thì dùng string này cho TH thành công ntn để trừ ra phần đã đóng góp thì các test sau sẽ kế thừa đúng đắn -> nếu thêm biến bool success thì tiện hơn nhưng có ảnh hưởng gì đến các hàm hiện có?

        // vm.stopPrank();

        CampaignNoBacker memory c = getLatestCampaign();
        assert(c.cFunded.raisedFund.amtFunded >= c.cFunded.raisedFund.target);
        assert(c.cStatus.campaignStatus == campaignStatusEnum.APPROVED);
        assertEq(c.cFunded.raisedFund.amtFunded, donationInfo.nativeTokenDonation);
        if (
            keccak256(abi.encodePacked(withdrawAfterCampaignMetTarget))
                == keccak256(
                    "Campaign' status: APPROVED -> Can only refund if caller is the contract platform or Campaign expired & failed or in REVERTING period!"
                )
        ) {
            assertEq(c.cFunded.raisedFund.firstTokenFunded, donationInfo.ctkTokenDonation);
        }
    }

    // in serie task to refactor paidOut_1
    function testDonateAfterAPPROVED(uint256 campaignId) private {
        console.log("testDonateAfterAPPROVED");
        DonateOrVote donateOrVote = new DonateOrVote();
        // vm.startPrank(BACKER2);
        vm.expectRevert("Campaign' status: APPROVED -> Campaign can NOT be donated."); // used when calling donateOrVote.vote directly
        bool voteAfterCampaignStartAndApproved = donateOrVote.vote(giveUp, campaignId, 0, 0);
        // vm.expectRevert("Campaign' status: APPROVED -> Campaign can NOT be donated.");
        bool donateAfterCampaignStartAndApproved = performDonate(campaignId, 0, 0, SEND_VALUE / 5, true); // used vm.expectRevert inside performDonate
        // vm.stopPrank();
        console.log(
            "voteAfterCampaignStartAndApproved, donateAfterCampaignStartAndApproved: ",
            voteAfterCampaignStartAndApproved,
            donateAfterCampaignStartAndApproved
        );
    }

    /* test updateCampaign:
    1. contract owner CAN'T update raiser's campaign if he IS NOT the raiser ...
    2. only raiser can update ...
    3. ... with strict condition ... 
    forge test --match-test testUpdateCampaign -vvvv
    */
    // function testUpdateCampaign() public campaign_100_0_Created {
    function testUpdateCampaign() public campaignCreated(100, 0) {
        // Arrange commonly used variables
        DonateOrVote donateOrVote = new DonateOrVote();
        CreateOrUpdate createOrUpdate = new CreateOrUpdate();
        CampaignNoBacker memory campaignBeforeUpdate = getLatestCampaign();
        string memory oldCampaignType = campaignBeforeUpdate.cInfo.campaignType;
        address raiser = campaignBeforeUpdate.cId.raiser;
        uint256 cId = campaignBeforeUpdate.cId.id;
        uint256 newHaveFundTarget = 0; // change from 100 -> 0 or >0 (e.g. 1) to see the logic
        uint256 newPctForBackers = 90; // 0 -> 90
        string[] memory uintFieldToChange = new string[](2);
        uintFieldToChange[0] = "firstTokenTarget"; // update fund target, arrange FIRST_TOKEN is CTK token
        uintFieldToChange[1] = "equivalentUSDTarget"; // update fund target, arrange "equivalentUSD" is USD stable coin
        uint256[] memory uintValueToChange = new uint256[](2);
        uintValueToChange[0] = SEND_TOKEN_AMT * 10; // 1000 CTK token
        uintValueToChange[1] = SEND_TOKEN_AMT * 100; // equivalent to 10000 USD stable coin
        // UpdateCampaignInput memory data =
        //     initializeUpdateCampaignData(cId, newHaveFundTarget, newPctForBackers, uintFieldToChange, uintValueToChange);

        // Act & Assert 1. contract owner CAN'T update raiser's campaign if he IS NOT the raiser
        vm.startPrank(giveUp.contractOwner());
        vm.expectRevert("Unauthorized Campaign's Owner");
        // bool success1 = updateCampaign(data);
        bool success1 = createOrUpdate.updateCampaign(
            giveUp, cId, newHaveFundTarget, newPctForBackers, uintFieldToChange, uintValueToChange
        );
        vm.stopPrank();
        assertEq(success1, false);
        console.log("1. contract owner CAN'T update raiser's campaign if he IS NOT the raiser >> ", success1);

        // Arrange & Act 2 : raiser update campaign when it's not started
        vm.startPrank(raiser);
        // bool success2 = updateCampaign(data);
        bool success2 = createOrUpdate.updateCampaign(
            giveUp, cId, newHaveFundTarget, newPctForBackers, uintFieldToChange, uintValueToChange
        );
        vm.stopPrank();
        CampaignNoBacker memory campaignAfterUpdate = getLatestCampaign();
        string memory latestCampaignType = campaignAfterUpdate.cInfo.campaignType;
        uint256 latestHaveFundTarget = campaignAfterUpdate.cId.haveFundTarget;
        // Assert 2: update newHaveFundTarget, newPctForBackers params successfully
        assertEq(latestCampaignType, oldCampaignType); // unmentioned fields would not changed
        assertEq(latestHaveFundTarget, newHaveFundTarget);
        assertEq(campaignAfterUpdate.cId.pctForBackers, newPctForBackers);
        if (latestHaveFundTarget == 0) {
            assertEq(campaignAfterUpdate.cFunded.raisedFund.firstTokenTarget, 0);
            assertEq(campaignAfterUpdate.cFunded.raisedFund.equivalentUSDTarget, 0);
        } else {
            assertEq(campaignAfterUpdate.cFunded.raisedFund.firstTokenTarget, uintValueToChange[0]);
            assertEq(campaignAfterUpdate.cFunded.raisedFund.equivalentUSDTarget, uintValueToChange[1]);
        }
        console.log(
            "2. only raiser can update >>",
            success2,
            ", proof: campaignType not changed but haveFundTarget changed in this test"
        );

        console.log("3. can not vote/ donate before campaign start");

        // Arrange 3: BACKER1 vote before and after campaign start
        // console.log("troubeshoot1: ", block.timestamp);  // >> 1

        vm.startPrank(BACKER1);
        vm.expectRevert("Campaign' status: OPEN -> Campaign can NOT be donated.");
        donateOrVote.vote(giveUp, cId, 0, 0); // donate with 0 amount mean vote
        // then pass proper timeframe to make campaign start
        vm.warp(block.timestamp + 86400 * 4);
        // console.log("troubeshoot2: ", block.timestamp);  // >> 345601
        bool voteSuccess = donateOrVote.vote(giveUp, cId, 0, 0);
        vm.stopPrank();
        // Assert 3: anyone can vote after campaign start
        assertEq(voteSuccess, true);
        assertEq(getLatestCampaign().cFunded.voterCount, 1);

        // AAA 4: then the raiser want to update campaign (for example: change haveFundTarget) but fail because campaign can not be updated after started
        vm.startPrank(raiser);
        vm.expectRevert("start time must be now or in future");
        createOrUpdate.updateCampaign(
            giveUp, cId, newHaveFundTarget, newPctForBackers, uintFieldToChange, uintValueToChange
        );
        vm.stopPrank();
    }

    /* test donateToCampaign, requestRefund: _100_0 is campaign type that has 100% fund for raiser, 0% for backers
    
    !!! WARNING !!!
    NOTE: BACKER CAN NOT DONATE MORE THAN THE EXPECTED TARGET if a DONATION campaign (distinguished by haveFundTarget > 0) is 'APPROVED' 
    NOTE: Donate mean backer will give the money to raiser and money can not be refund if campaign success !!!
    !!! WARNING !!!

    1. donate/vote will fail before startAt time 
    2. ... set proper timeframe (after campaign start) -> donate, withdraw
    3. ... enough donation amount will trigger campaign 'APPROVED' status
    4. donate fail after campaign is 'APPROVED' (different from testDonateToCampaign_0_90())
    => notice emit Action
    forge test --mt testDonateVoteWithdraw_100_0 -vvvv
    */
    // function testDonateVoteWithdraw_100_0() public campaign_100_0_Created initWLToken {
    function testDonateVoteWithdraw_100_0() public campaignCreated(100, 0) initWLToken {
        // Arrange & Act 1 : test donateToCampaign before campaign start -> will fail
        DonateOrVote donateOrVote = new DonateOrVote();
        vm.startPrank(BACKER2);
        vm.expectRevert("Campaign' status: OPEN -> Campaign can NOT be donated."); // Assert 1: campaign can not be donate before started
        bool donateBeforeCampaignStart = donateOrVote.donate(giveUp, MAX_RULES, 0, 0, SEND_VALUE);
        vm.stopPrank();
        console.log(
            "1. test donateToCampaign which will fail because of startAt time: ",
            donateBeforeCampaignStart,
            " check contract balance = ",
            address(giveUp).balance
        );

        // Arrange & Act 2 : test donateToCampaign after campaign start but not make campaign meet fund target
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)
        vm.startPrank(BACKER2); // if obmit will take address of this GiveUp129InteractionsTest contract
        bool donateAfterCampaignStart = donateOrVote.donate(giveUp, MAX_RULES, 0, 0, SEND_VALUE / 10);
        vm.stopPrank();
        // Assert 2a: campaign can be donate after started
        assertEq(donateAfterCampaignStart, true);
        assertEq(getLatestCampaign().cFunded.raisedFund.amtFunded, SEND_VALUE / 10);

        // Arrange 2b: test donateWhiteListTokenToCampaign (vote & donate) and check other function ralated to voting: getCampaignOptionsVoted
        // BACKER1 want to vote for option 0 and donate to option 2
        uint256[] memory backer1VoteOption = new uint256[](2);
        backer1VoteOption[0] = 0;
        backer1VoteOption[1] = 2;
        // uint256[] memory backer1TokenVoteQty = new uint256[](2); //stack too deep
        // backer1TokenVoteQty[0] = 0;
        // backer1TokenVoteQty[1] = SEND_TOKEN_AMT;
        vm.startPrank(BACKER1);
        bool voteWLTokenSuccess = donateOrVote.voteWLToken(giveUp, MAX_RULES, backer1VoteOption[0], 0, ctk);
        vm.startPrank(BACKER1);
        bool donateWLTokenSuccess =
            donateOrVote.donateWLToken(giveUp, MAX_RULES, backer1VoteOption[1], 1111, ctk, SEND_TOKEN_AMT);
        vm.stopPrank();
        assertEq(giveUp.getBackerTokenFunded(MAX_RULES, BACKER1, address(ctk)), SEND_TOKEN_AMT); // campaign accrued above donate amount: OK

        console.log(
            "2. test donateToCampaign which will pass: ",
            donateAfterCampaignStart,
            " check contract balance = ",
            address(giveUp).balance
        );
        console.log(
            "voteWLTokenAfterCampaignStart, donateWLTokenAfterCampaignStart: ", voteWLTokenSuccess, donateWLTokenSuccess
        );

        // Assert 2b: confirm donateWhiteListTokenToCampaign (vote & donate) and options voted is correct
        VoteData[] memory voteData = getBackerVoteData(MAX_RULES, BACKER1);
        console.log("voteData.length", voteData.length);
        for (uint256 i = 0; i < voteData.length; i++) {
            assertEq(voteData[i].option, backer1VoteOption[i]);
            console.log("vote info of BACKER1", voteData[i].option, voteData[i].tokenSymbol);
            // cant assert the quantity because of stack too deep
            console.log("quantity: ", giveUp.getOptionTokenFunded(MAX_RULES, voteData[i].option, address(ctk)));
        }

        // Arrange & Act 2c: test requestRefund with an incorrect option
        vm.prank(BACKER1);
        string memory withdrawWIncorrectOption = giveUp.requestRefund(MAX_RULES, true, 1);
        // Assert 2c: Can not refund/ withdraw because provided option is not correct
        assertEq(withdrawWIncorrectOption, "Remove vote option FAILED + Nothing to refund");
        console.log("|-> requestRefund - withdrawWOption: ", withdrawWIncorrectOption);

        // Assert 2d: test requestRefund all options (mean not donate or vote for any option anymore) (-> todo will be checked for timelock)
        vm.prank(BACKER1);
        string memory withdrawAllOptions = giveUp.requestRefund(MAX_RULES, true, BACKER_WITHDRAW_ALL_CODE);
        C_Backer[] memory backers = giveUp.getBackersOfCampaign(MAX_RULES, true);
        C_Backer memory latestBacker = backers[backers.length - 1];
        assertEq(latestBacker.backer, address(BACKER1));
        assertEq(latestBacker.fundInfo.refunded, true); // e.g. succeed
        assertEq(giveUp.getContractFundedInfo().cTotalFirstToken, 0); // contract deducted above refund amount: OK
        assertEq(giveUp.getBackerTokenFunded(MAX_RULES, BACKER1, address(ctk)), 0); // campaign deducted above refund amount and show that that backer no longer has refunded token: OK
        console.log("latest backer other Info: ", latestBacker.backer, latestBacker.qty, latestBacker.tokenSymbol);
        console.log("|-> requestRefund - withdrawAllOptions: ", withdrawAllOptions);

        // Arrange & Act 3 : donateToCampaign after campaign start and make campaign meet fund target
        // enough donation amount to trigger campaign 'APPROVED' status
        // 3a: donateToCampaign after campaign start and make campaign meet fund target
        vm.startPrank(BACKER2);
        bool donateAfterCampaignStartWithTargetAmt = donateOrVote.donate(giveUp, MAX_RULES, 0, 0, SEND_VALUE);
        assertEq(donateAfterCampaignStartWithTargetAmt, true);
        // 3b: then try to withdraw but fail because campaign is 'APPROVED' and haveFundTarget > 0
        vm.startPrank(BACKER2);
        vm.expectRevert(
            "Campaign' status: APPROVED -> Can only refund if caller is the contract platform or Campaign expired & failed or in REVERTING period!"
        ); // NOTE: BACKER CAN NOT withdraw if a DONATION campaign (distinguished by haveFundTarget > 0) is 'APPROVED' !!! BE CAUTION !!!
        string memory withdrawAfterCampaignMetTarget = giveUp.requestRefund(MAX_RULES, true, BACKER_WITHDRAW_ALL_CODE);
        console.log(
            "|-> requestRefund - withdrawAfterCampaignMetTarget: try to withdraw but fail because campaign is 'APPROVED' and haveFundTarget > 0",
            withdrawAfterCampaignMetTarget
        );
        CampaignNoBacker memory c = getLatestCampaign();
        assert(c.cFunded.raisedFund.amtFunded >= c.cFunded.raisedFund.target);
        console.log(
            "3. = 2nd test + enough donation amount to trigger campaign 'APPROVED' status: ",
            donateAfterCampaignStartWithTargetAmt,
            " check contract balance = ",
            address(giveUp).balance
        );
        // Arrange & Act 4: donate more will fail because campaign is 'APPROVED' and has set haveFundTarget > 0
        vm.expectRevert("Campaign' status: APPROVED -> Campaign can NOT be donated."); // BACKER CAN NOT VOTE if a DONATION campaign (distinguished by haveFundTarget > 0) is 'APPROVED'
        bool voteAfterCampaignStartAndApproved = donateOrVote.vote(giveUp, MAX_RULES, 0, 0);
        console.log("4. vote fail because campaign is 'APPROVED': >> ", voteAfterCampaignStartAndApproved);
        vm.expectRevert("Campaign' status: APPROVED -> Campaign can NOT be donated."); // NOTE: Moreover BACKER CAN NOT DONATE MORE THAN THE EXPECTED TARGET if a DONATION campaign (distinguished by haveFundTarget > 0) is 'APPROVED' !!! NOTICE !!!
        bool donateAfterCampaignStartAndApproved = donateOrVote.donate(giveUp, MAX_RULES, 0, 0, SEND_VALUE / 5);
        console.log(
            "4. donate also fail because campaign is 'APPROVED': >> ",
            donateAfterCampaignStartAndApproved,
            " check contract balance = ",
            address(giveUp).balance
        );
    }

    /**
     * include 2 parts:
     * testDonateVoteWithdraw_0_90_p1:
     * testDonateVoteWithdraw_0_90_p2:
     *
     *     NOTE:
     *     Because haveFundTarget = 0 -> this is a non profit campaign -> when have any donation, campaign status
     *     will be "APPROVED_UNLIMITED" (not "APPROVED")
     */
    function testDonateVoteWithdraw_0_90_p1() public initWLToken {
        // Arrange: create campaign with haveFundTarget = 0
        CreateOrUpdate campaign_0_90 = new CreateOrUpdate();
        uint256 cId = campaign_0_90.createCampaign(giveUp, 0, 90);

        /* 
        do the same test as testDonateVoteWithdraw_100_0, pay attention to actions after campaign meet target, in and out of raising timeframe
        */

        // Arrange & Act 1 : test donateToCampaign before campaign start -> will fail
        DonateOrVote donateOrVote = new DonateOrVote();
        vm.startPrank(BACKER2);
        vm.expectRevert("Campaign' status: OPEN -> Campaign can NOT be donated."); // Assert 1: campaign can not be donate before started
        bool donateBeforeCampaignStart = donateOrVote.donate(giveUp, cId, 0, 0, SEND_VALUE);
        vm.stopPrank();
        console.log(
            "1. test donateToCampaign which will fail because of startAt time: ",
            donateBeforeCampaignStart,
            " check contract balance = ",
            address(giveUp).balance
        );

        // Arrange & Act 2 : test donateToCampaign after campaign start but not make campaign meet fund target
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)
        vm.startPrank(BACKER2); // if obmit will take address of this GiveUp129InteractionsTest contract
        bool donateAfterCampaignStart = donateOrVote.donate(giveUp, cId, 0, 0, SEND_VALUE / 10);
        vm.stopPrank();
        // Assert 2a: campaign can be donate after started
        assertEq(donateAfterCampaignStart, true);
        assertEq(getLatestCampaign().cFunded.raisedFund.amtFunded, SEND_VALUE / 10);

        // Assert 2b: test donateWhiteListTokenToCampaign (vote & donate)
        vm.startPrank(BACKER1);
        bool voteWLTokenSuccess = donateOrVote.voteWLToken(giveUp, cId, 0, 0, ctk); // vote for general option, no feedback, use ctk token (backer no need to have any token amount) -> expect success
        vm.startPrank(BACKER1);
        bool donateWLTokenSuccess = donateOrVote.donateWLToken(giveUp, cId, 0, 1111, ctk, SEND_TOKEN_AMT); // donate for general option, have feedback id 1111, donate SEND_TOKEN_AMT amount of ctk -> expect success
        vm.stopPrank();

        console.log(
            "2. test donateToCampaign which will pass: ",
            donateAfterCampaignStart,
            " check contract balance = ",
            address(giveUp).balance
        );
        console.log(
            "voteWLTokenAfterCampaignStart, donateWLTokenAfterCampaignStart: ", voteWLTokenSuccess, donateWLTokenSuccess
        );

        // Arrange & Act 2c: test requestRefund with an incorrect option
        vm.prank(BACKER1);
        string memory withdrawWOption = giveUp.requestRefund(cId, true, 1);
        // Assert 2c: Can not refund/ withdraw because provided option is not correct (correct option is 0)
        assertEq(withdrawWOption, "Remove vote option FAILED + Nothing to refund");
        console.log("|-> requestRefund - withdrawWOption: ", withdrawWOption);

        // NOTE: Below comment is trial for using timelock but failed atm
        // ////// testing with timelock - start //////
        // // Assert 2d: test requestRefund all options (mean not donate or vote for any option anymore) -> will need 2 step, 1st: register, 2nd: wait for timelock to over then withdraw
        // vm.prank(BACKER1);
        // string memory withdrawAllOptions_register = giveUp.requestRefund(cId, true, BACKER_WITHDRAW_ALL_CODE);
        // assertEq(
        //     withdrawAllOptions_register,
        //     "Successfully registered early withdrawal at timelock index 1. Please wait and make withdraw again AFTER 3 block numbers!"
        // ); // hard code the return message to test
        // // Arrange 2e: assuming 1 block.number == 60 seconds, we increase 1 block.number and increase timestamp 60 seconds
        // vm.roll(block.number + 1);
        // vm.warp(block.timestamp + 60);
        // // Act 2e: test requestRefund 2nd times after successfully registered but still in delay time frame (3 blocks) -> expect falure notice
        // vm.prank(BACKER1);
        // string memory withdrawAllOptions_WithinDelayTimeFrame = giveUp.requestRefund(cId, true, BACKER_WITHDRAW_ALL_CODE);
        // assertEq(
        //     withdrawAllOptions_WithinDelayTimeFrame,
        //     "You are in waiting period of 3 block numbers, please wait until it's over!. Index: 1"
        // ); // hard code the return message to test
        // // Arrange 2f: continue to increase 3 block.number and timestamp correspondingly
        // vm.roll(block.number + 3);
        // vm.warp(block.timestamp + 180);
        // // Act 2f: test requestRefund 3rd times after successfully registered and after waiting period
        // ////// testing with timelock - end //////

        vm.prank(BACKER1);
        string memory withdrawAllOptions_3rdTime = giveUp.requestRefund(cId, true, BACKER_WITHDRAW_ALL_CODE);
        // Assert 2f: to withdraw previous vote or donate the simplest way, BACKER1 just simply call requestRefund -> expect success
        C_Backer[] memory backers = giveUp.getBackersOfCampaign(cId, true);
        C_Backer memory latestBacker = backers[backers.length - 1];
        assertEq(latestBacker.backer, address(BACKER1));
        assertEq(latestBacker.fundInfo.refunded, true); // e.g. succeed
        console.log("latest backer other Info: ", latestBacker.backer, latestBacker.qty, latestBacker.tokenSymbol);
        console.log("|-> requestRefund - withdrawAllOptions_3rdTime: ", withdrawAllOptions_3rdTime);

        // to be continue with part 2 ...
    }

    function testDonateVoteWithdraw_0_90_p2() public {
        // Arranges to continue with part 2 ...
        testDonateVoteWithdraw_0_90_p1();
        DonateOrVote donateOrVote = new DonateOrVote();
        uint256 cId = MAX_RULES; // continue previous campaign

        // 3a: donateToCampaign after campaign start will ALWAYS make campaign "APPROVED_UNLIMITED"
        vm.startPrank(BACKER2);
        bool donateAfterCampaignStartWithAnyAmt = donateOrVote.donate(giveUp, cId, 0, 0, SEND_VALUE);
        assertEq(donateAfterCampaignStartWithAnyAmt, true);

        // NOTE: Below comment is trial for using timelock but failed atm
        /**
         * SOME SCENARIOS (more complex) in part 2:
         * 	- S1: backer request refund all
         *       + while wait donate for an option -> this donate will lead to new timelock that make him can not withdraw all within this new timelock period.
         *       + after waiting all timelock he proceed withdraw all -> check all are withdrawn include new contribute ?
         *  - S2: backer request refund 2/4 option: e.g 1, 2 in [1,2,3,4]
         *       + while wait he donate to option 2 again
         *       + after waiting time he proceed to withdraw 1 -> check
         *       + after waiting time he proceed to withdraw 2-> check
         *       + interact when APPROVED, can not withdraw is right
         */
        // ////// testing with timelock - start //////
        // // Arrange S1: BACKER2 trigger withdraw all
        // vm.startPrank(BACKER2);
        // string memory withdrawAfterCampaignApprovedUnlimitted = giveUp.requestRefund(cId, true, BACKER_WITHDRAW_ALL_CODE);
        // assertEq(
        //     withdrawAfterCampaignApprovedUnlimitted,
        //     "Successfully registered early withdrawal at timelock index 0. Please wait and make withdraw again AFTER 3 block numbers!"
        // ); // hard code the return message to test

        // // Arrange S1: assuming 1 block time pass
        // vm.warp(block.timestamp + 60); // 345901
        // vm.roll(block.number + 1); // 6
        // // Assert S1: backer trigger withdraw all again while in waiting period -> expect falure notice
        // // vm.prank(BACKER2);
        // string memory withdrawAllOptions_WithinDelayTimeFrame = giveUp.requestRefund(cId, true, BACKER_WITHDRAW_ALL_CODE);
        // assertEq(
        //     withdrawAllOptions_WithinDelayTimeFrame,
        //     "You are in waiting period of 3 block numbers, please wait until it's over!. Index: 0"
        // ); // hard code the return message to test
        // // C_Backer[] memory backers_temp_to_check = giveUp.getBackersOfCampaign(cId);
        // // console.log(backers_temp_to_check[0].fundInfo.requestRefundBlockNumber);
        // ////// testing with timelock - end //////

        // Arrange S1: (while wait for timelock) backer donate for another option
        vm.startPrank(BACKER2);
        bool donateToAnotherOptionS1 = donateOrVote.donate(giveUp, cId, 1, 1999, SEND_VALUE);
        assertEq(donateToAnotherOptionS1, true);
        // Arrange S1: (after timelock waiting time is over) he proceed withdraw all
        vm.warp(block.timestamp + 240); // 346141
        vm.roll(block.number + 4); // 10
        // vm.warp(block.timestamp + 240);
        // vm.roll(block.number + 4);
        // console.log("block.number", block.number, "timestamp", block.timestamp);

        // Assert S1: try withdraw all -> expect success
        vm.startPrank(BACKER2);
        string memory withdrawAll_S1_Final = giveUp.requestRefund(cId, true, BACKER_WITHDRAW_ALL_CODE);
        console.log("withdrawAll_S1_Final", withdrawAll_S1_Final);
        C_Backer[] memory backers = giveUp.getBackersOfCampaign(cId, true);
        C_Backer memory latestBacker = backers[backers.length - 1];
        // assertEq(
        //     withdrawAll_S1_Final,
        //     "Successfully registered early withdrawal at timelock index 2. Please wait and make withdraw again AFTER 3 block numbers!"
        // ); // hard code the return message to test with timelock
        (uint256 numberOfContributionsOfBACKER2, uint256[] memory indexList) =
            giveUp.getCampaignContributionsFromBacker(cId, BACKER2, true); // find contributions that are refunded
        console.log("indexList", indexList[0], indexList[1], indexList[2]);
        string memory withdrawAll_S1_Final_compare =
            string(abi.encodePacked("Processed ", Strings.toString(numberOfContributionsOfBACKER2), " donation(s)"));
        assertEq(withdrawAll_S1_Final, withdrawAll_S1_Final_compare); // hard code the return message to test with no timelock
        assertEq(latestBacker.backer, address(BACKER2));
        assertEq(backers[0].backer, address(BACKER2)); // make sure we're working with the same backer
        assertEq(backers[0].fundInfo.refunded, true); // and this backer, at previous return index 0, is refunded
    }

    /**
     * paidOut_1 is sub function of testPaidOutDelete_xxx_yyy(), paidOutDelete_xxx_yyy etc
     * test vote, donate, withdraw, payout / contractFundedInfo ...
     */
    function paidOut_1(bool changeAlchemist, uint256 campaignId) public {
        // uint256 nativeTokenDonation = 0;
        // uint256 ctkTokenDonation = 0;
        // uint256 balanceBefore = address(giveUp).balance;
        // uint256 ctkBalanceBefore = ctk.balanceOf(address(giveUp));
        // ContractFunded memory contractFundedInfoBefore = giveUp.getContractFundedInfo();
        initDonationInfo();

        PaidoutOrDelete paidoutOrDelete = new PaidoutOrDelete();

        // Alchemist memory alchemistBeforeCampaignStart;
        // // by default this test will change alchemist to 0
        // if (!changeAlchemist) {
        //     // Assert: Alchemist not effect payout when haveFundTarget = 100 (raiser have all the power to payout)
        //     vm.startPrank(RAISER1);
        //     giveUp.raiserChangeAlchemist(campaignId, payable(address(0)));
        //     (alchemistBeforeCampaignStart,,,,,) = giveUp.getRemainMappingCampaignIdTo(campaignId);
        //     assertEq(address(0), alchemistBeforeCampaignStart.addr); // raiser change alchemist address to 0
        //     vm.stopPrank();
        // } else {
        //     (alchemistBeforeCampaignStart,,,,,) = giveUp.getRemainMappingCampaignIdTo(campaignId); // just update alchemist info for later assertion
        // }
        vm.startPrank(RAISER1);
        Alchemist memory alchemistBeforeCampaignStart = testAlchemistChange(campaignId, changeAlchemist);
        vm.stopPrank();

        vm.startPrank(BACKER2);
        testDonateBeforeCampaignStart(campaignId);
        vm.stopPrank();

        // // Arrange & Act 1 : donateToCampaign after campaign start but not make campaign meet fund target
        // vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)
        // vm.startPrank(BACKER2); // if obmit will take address of this GiveUp129InteractionsTest contract
        // bool donateAfterCampaignStart = donateOrVote.donate(giveUp, campaignId, 0, 0, SEND_VALUE / 10);
        // nativeTokenDonation = nativeTokenDonation + (SEND_VALUE / 10);
        // vm.stopPrank();

        vm.warp(block.timestamp + 86400 * 4);
        vm.startPrank(BACKER2);
        testDonateAfterCampaignStart(campaignId);
        vm.stopPrank();

        // Assert: Raiser can not propose to change alchemist after campaign start
        vm.startPrank(RAISER1);
        vm.expectRevert("Can not propose Alchemist after campaign start"); // "Raiser can not propose to change alchemist after campaign start, if he want to in this case he has to have his community to help him"
        giveUp.raiserChangeAlchemist(campaignId, ALCHEMIST1);
        (Alchemist memory alchemistAfterCampaignStart,,,,,) = giveUp.getRemainMappingCampaignIdTo(campaignId);
        assertEq(alchemistBeforeCampaignStart.addr, alchemistAfterCampaignStart.addr);
        vm.stopPrank();

        // // Assert 1a: campaign can be donated after started -> moved inside testDonateAfterCampaignStart
        // assertEq(donateAfterCampaignStart, true);
        // assertEq(getLatestCampaign().cFunded.raisedFund.amtFunded, nativeTokenDonation);

        // // note: temporarily comment -> moved inside checkDonationResults and place at the end of this function
        // assertEq(giveUp.getContractFundedInfo().cTotalNativeToken - contractFundedInfoBefore.cTotalNativeToken, nativeTokenDonation); // contract accrued above native token donation

        // // Assert 1b: vote & donate more with whiteListToken
        // vm.startPrank(BACKER1);
        // bool voteWLTokenSuccess = donateOrVote.voteWLToken(giveUp, campaignId, 0, 0, ctk);
        // vm.startPrank(BACKER1);
        // bool donateWLTokenSuccess = donateOrVote.donateWLToken(giveUp, campaignId, 0, 1111, ctk, SEND_TOKEN_AMT);
        // ctkTokenDonation = ctkTokenDonation + SEND_TOKEN_AMT;
        // vm.stopPrank();

        // console.log(
        //     "1. We have made some vote, donate native token, whiteListToken, check contract balance = ",
        //     address(giveUp).balance
        // );
        // console.log("voteWLTokenSuccess, donateWLTokenSuccess: ", voteWLTokenSuccess, donateWLTokenSuccess);

        testVoteAndDonateWLToken(campaignId, BACKER1);
        testVoteDataAndFundRelated(campaignId, BACKER1);

        // Arrange & Act 2 : donateToCampaign after campaign start and make campaign meet fund target
        // vm.startPrank(RAISER2);
        // bool donateAfterCampaignStartWithTargetAmt = donateOrVote.donate(giveUp, campaignId, 0, 0, SEND_VALUE);
        // nativeTokenDonation = nativeTokenDonation + SEND_VALUE;
        // assertEq(donateAfterCampaignStartWithTargetAmt, true);
        // vm.stopPrank();
        // CampaignNoBacker memory c = getLatestCampaign();
        // assert(c.cFunded.raisedFund.amtFunded >= c.cFunded.raisedFund.target);
        // assert(c.cStatus.campaignStatus == campaignStatusEnum.APPROVED);
        // assertEq(c.cFunded.raisedFund.amtFunded, nativeTokenDonation);
        // assertEq(c.cFunded.raisedFund.firstTokenFunded, ctkTokenDonation);

        vm.startPrank(BACKER2);
        testDonateToMeetTarget(campaignId);
        testDonateAfterAPPROVED(campaignId);
        vm.stopPrank();

        /**
         * obmit these assertEq because not necessary
         *     assertEq(ctk.balanceOf(address(giveUp)) - ctkBalanceBefore, ctkTokenDonation); // contract accrued above ctk token donation (ctk is first priority token) in itself.
         *     assertEq(contractFundedInfo.cTotalFirstToken - contractFundedInfoBefore.cTotalFirstToken, ctkTokenDonation); // contract accrued above ctk token donation (ctk is first priority token) in contractFundedInfo var
         */

        // moved to checkDonationResults
        // ContractFunded memory contractFundedInfo = giveUp.getContractFundedInfo();
        // assertEq(contractFundedInfo.cTotalNativeToken - contractFundedInfoBefore.cTotalNativeToken, nativeTokenDonation); // contract accrued above native token donation
        // assertEq(contractFundedInfo.totalFundedCampaign - contractFundedInfoBefore.totalFundedCampaign, 0); // TotalFundedCampaign did not deducted because this campaign is successfully paidout
        // console.log(
        //     "contractFundedInfo.cTotalNativeToken >>",
        //     contractFundedInfo.cTotalNativeToken,
        //     "contractFundedInfo.cTotalFirstToken >>",
        //     contractFundedInfo.cTotalFirstToken
        // );
        // console.log(
        //     "getTotalFundedCampaign did not deducted because this campaign is successfully paidout: ",
        //     contractFundedInfo.totalFundedCampaign
        // );
        checkDonationResults();

        // Arrange 3: test non raiser, raiser Paidout
        vm.startPrank(RAISER2);
        vm.expectRevert("Invalid Pay Out Right"); // -> expect non raiser fail
        paidoutOrDelete.payOutCampaign(giveUp, campaignId);
        vm.stopPrank();
        // Assert 3a: check contract balance before raiser Paidout

        // // note: temporarily comment because testing aggregated giveUp fund, it can not equal to nativeTokenDonation todo: recheck?
        // assertEq(address(giveUp).balance - balanceBefore, nativeTokenDonation);
        // assertEq(ctk.balanceOf(address(giveUp)), ctkTokenDonation);

        // Act 3: raiser Paidout -> expect success
        CampaignNoBacker memory c = getLatestCampaign();
        vm.startPrank(c.cId.raiser);
        vm.expectRevert("please set token symbol first");
        paidoutOrDelete.payOutCampaign(giveUp, campaignId);
        vm.expectRevert("setter is not raiser or community in RIGHT timeframe");
        giveUp.setCampaignFinalTokenNameAndSymbol("resultToken", "RST", campaignId);
        vm.stopPrank();
        vm.startPrank(giveUp.contractOwner());
        giveUp.setCommunityAddress(campaignId, COMMUNITY1, "testPaidOutDelete_100_0");
        vm.expectRevert("setter is not raiser or community in RIGHT timeframe");
        giveUp.setCampaignFinalTokenNameAndSymbol("resultToken", "RST", campaignId);
        vm.stopPrank();
        vm.startPrank(COMMUNITY1);
        giveUp.setCampaignFinalTokenNameAndSymbol("resultToken", "RST", campaignId); // set result token name and symbol success
        vm.stopPrank();

        // arrange: change platform tax from 0 to 10% before raiser paidout
        vm.startPrank(giveUp.contractOwner());
        giveUp.changeTax(FEE_PCT_10);
        vm.stopPrank();
        vm.startPrank(c.cId.raiser);
        (TokenTemplate1 resultToken, uint256 liquidity) = paidoutOrDelete.payOutCampaign(giveUp, campaignId);
        vm.stopPrank();

        // Assert 3b: check amount raiser, platform receive when campaign tax = 10%, haveFundTarget = 100
        // expectation: if the donation campaign is success, platform will make a result token contract as a reward rememberance for backers. In this case, because raiser get all fund so the liquidity (pool token between raised fund and result token) should be 0.
        assertEq(payable(address(resultToken)) != payable(address(0)), true); // result token is not zero address
        console.log("print resultToken address", address(resultToken));
        if (c.cId.haveFundTarget == 100) {
            assert(liquidity == 0); // if haveFundTarget = 100,  so no liquidity
        } else if (c.cId.haveFundTarget < 100) {
            assert(liquidity > 0); // if haveFundTarget < 100, so have liquidity
        }

        // // note: here
        // // note: temporarily comment below because formular to calculate aggregated platform fee is not correct
        // // assert main contract have sent native token to result token and its balance now = tax amount (is the fee it'll get)
        // // assertEq(address(giveUp).balance, nativeTokenDonation * FEE_PCT_10 / 100);

        // // assert result token contract have received native token fund (which have been deducted fee) from main contract
        // assertEq(address(resultToken).balance, nativeTokenDonation * (100 - FEE_PCT_10) / 100);
        // assertEq(ctk.balanceOf(address(giveUp)), 0); // ctk balance of main contract should be 0

        // // assert result token contract have received whitelisted token (ctk) in full
        // assertEq(ctk.balanceOf(address(resultToken)), SEND_TOKEN_AMT); // ctk balance of result token should be SEND_TOKEN_AMT ...
        // assertEq(ctk.balanceOf(address(resultToken)), ctkTokenDonation); // ... and also equal ctkTokenDonation (so far)

        // console.log("address(resultToken)", address(resultToken));
        // (,, C_Funded memory cFundedOfResultToken,,) = resultToken.thisCampaign();
        // uint256 nativeTokenRaiserIsCredited = getAmountRaiserIsCredited(nativeTokenDonation, c.cId.haveFundTarget);
        // assertEq(cFundedOfResultToken.raisedFund.amtFunded, nativeTokenDonation);
        // assertEq(cFundedOfResultToken.raiserPaidOut.nativeTokenAmt, nativeTokenRaiserIsCredited); // value raiser will receive after tax and in this haveFundTarget setting. If get stack too deep error -> use:  forge test --mt testPaidOutDelete_100_0 -vvvv --via-ir
        // assertEq(cFundedOfResultToken.raiserPaidOut.firstTokenAmt, ctkTokenDonation); // firstTokenAmt == ctkTokenDonation when haveFundTarget = 100
    }

    /**
     * paidOut_2 is sub function of testPaidOutDelete_xxx_yyy(), paidOutDelete_xxx_yyy etc
     * it usually ran after paidOut_1 for more test
     */
    function paidOut_2(uint256 campaignId) public {
        //////////////////////////////// initialized value to continue previous test
        uint256 nativeTokenDonation = (SEND_VALUE / 10) + SEND_VALUE;
        uint256 nativeTokenRaiserIsCredited = getAmountRaiserIsCredited(nativeTokenDonation, 100); // 100 is haveFundTarget
        // Note 1: manually adjust ctkTokenDonation depend on scenario:
        uint256 ctkTokenDonation = 0; // because in paidOut_1, backer already withdrew in testVoteDataAndFundRelated
        uint256 raiserBalanceBeforePaidout = RAISER1.balance; // STARTING_USER_BALANCE; // 100 ether
        uint256 raiserCTK_BalanceBeforePaidout = ctk.balanceOf(RAISER1); // old test is 0;
        (,,,,, CampaignToken memory campaignToken) = giveUp.getRemainMappingCampaignIdTo(campaignId);
        address payable resultTokenAddress = payable(campaignToken.tokenAddr);
        TokenTemplate1 resultToken = TokenTemplate1(resultTokenAddress);

        // note: temporarily comment below because duplicate in paidOut_1.
        // ContractFunded memory contractFundedInfoAfterPaidout = giveUp.getContractFundedInfo();
        // assertEq(contractFundedInfoAfterPaidout.cTotalNativeToken, nativeTokenDonation); // contract successfully recorded paidout campaign
        // assertEq(contractFundedInfoAfterPaidout.cTotalFirstToken, ctkTokenDonation); // contract successfully recorded paidout campaign

        console.log("START coding WITHDRAW FUNCTION THEN assert below");
        vm.startPrank(RAISER1);
        resultToken.raiserWithdrawDonationCampaignFunds();
        vm.stopPrank();
        assertEq(RAISER1.balance, raiserBalanceBeforePaidout + nativeTokenRaiserIsCredited);
        assertEq(ctk.balanceOf(RAISER1), raiserCTK_BalanceBeforePaidout + ctkTokenDonation); // see note 1

        // Test claimTokenToBacker function
        // Sử dụng resultToken đã được tạo sẵn

        // Test raiser không thể mint vì quy định kiểu dự án donation / tip thì raiser chỉ được lấy raised fund, token để dành cho backers làm quà lưu niệm
        vm.prank(RAISER1);
        vm.expectRevert("Invalid backer or there is no alchemist");
        resultToken.claimTokenToBacker(RAISER1);

        (address alchemistAddr,, uint256 alchemistClaimAmount,,) = resultToken.alchemistShare();
        if (alchemistAddr == address(0)) {
            // Test alchemist không thể mint (trong TH này là do raiser không set alchemist)
            vm.prank(ALCHEMIST1);
            vm.expectRevert("Invalid backer or there is no alchemist");
            resultToken.claimTokenToBacker(ALCHEMIST1);
        } else {
            // raiser set alchemist but we have to check for pctForBacker = 0 or not
            if (alchemistClaimAmount > 0) {
                vm.prank(ALCHEMIST1);
                resultToken.claimTokenToBacker(ALCHEMIST1);
            } else {
                vm.prank(ALCHEMIST1);
                vm.expectRevert("Amount token for alchemist is 0");
                resultToken.claimTokenToBacker(ALCHEMIST1);
            }
        }
        assertEq(
            resultToken.balanceOf(ALCHEMIST1), alchemistClaimAmount, "Alchemist should receive correct mint amount"
        );

        // Test backer có thể mint token theo phần đóng góp
        uint256 backerIndex = resultToken.getBackerIndex(BACKER2);
        (,, uint256 backerMintAmount,,) = resultToken.backerShare(backerIndex);
        (C_Id memory temp,,,,) = resultToken.thisCampaign();
        console2.log("token amt of BACKER2, if pctForBacker = 0, it'll be 0 >> ", backerMintAmount);
        console2.log("temp.haveFundTarget", temp.haveFundTarget);
        console2.log("address of resultToken", address(resultToken));
        if (backerMintAmount == 0) {
            vm.prank(BACKER2);
            vm.expectRevert("Amount token for backer is 0"); // because raiser set pctForBacker = 0 !!!
            resultToken.claimTokenToBacker(BACKER2); // test ok
            vm.prank(BACKER2);
            vm.expectRevert("Amount token for backer is 0"); // because raiser set pctForBacker = 0 !!!
            giveUp.claimTokenToBacker(campaignId); // similar to above but calling via giveUp contract
        } else {
            // vm.prank(BACKER2);
            // resultToken.claimTokenToBacker(BACKER2); // test ok but comment to test similar call below
            vm.prank(BACKER2);
            giveUp.claimTokenToBacker(campaignId); // similar to above but calling via giveUp contract
        }

        assertEq(resultToken.balanceOf(BACKER2), backerMintAmount, "Backer should receive correct mint amount");

        // Test backer không thể mint do: quá phần được phép / không phải backer / đã mint đủ => dùng vm.expectRevert() là đủ
        vm.prank(BACKER1);
        vm.expectRevert();
        resultToken.claimTokenToBacker(BACKER1);

        // Test tổng cung sau khi mint
        assertEq(
            resultToken.totalSupply(),
            backerMintAmount + alchemistClaimAmount,
            "Total supply should be equal to backers, alchemist claim amount"
        );
    }

    // refactoring code to testAllPaidOutDeleteCombinations

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 0 - part 1
    //  * (Before was modifier successCampaign_100_0() that)
    //  * Run some test before entering main testPaidOutDelete_100_0 test
    //  * include: test vote, donate, withdraw, payout / contractFundedInfo ... of campaign _100_0
    //  * now we change it to a function
    //  *
    //  */
    // function paidOutDelete_100_0() public campaignCreated(100, 0) initWLToken {
    //     paidOut_1(false);
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 0 - part 2
    //  * further test of paidOutDelete_100_0 above
    //  */
    // function testPaidOutDelete_100_0() public {
    //     paidOutDelete_100_0(); // here we run modifier to create campaign with haveFundTarget = 100, pctForBacker = 0
    //     paidOut_2(); // here we run sub function of testPaidOutDelete_xxx_yyy() etc
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 90 - part 1
    //  * Run some test before entering main testPaidOutDelete_100_90 test
    //  * include: test vote, donate, withdraw, payout / contractFundedInfo ... of campaign _100_90
    //  * (similar to paidOutDelete_100_0 above)
    //  *
    //  */
    // function paidOutDelete_100_90() public campaignCreated(100, 90) initWLToken {
    //     paidOut_1(false);
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 90 - part 2
    //  * further test of paidOutDelete_100_90 above
    //  */
    // function testPaidOutDelete_100_90() public {
    //     paidOutDelete_100_90();
    //     paidOut_2();
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 100 - part 1
    //  * Run some test before entering main testPaidOutDelete_100_100 test
    //  * include: test vote, donate, withdraw, payout / contractFundedInfo ... of campaign _100_100
    //  * (similar to paidOutDelete_100_90 above)
    //  */
    // function paidOutDelete_100_100() public campaignCreated(100, 100) initWLToken {
    //     paidOut_1(false);
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 100 - part 2
    //  * further test of paidOutDelete_100_100 above
    //  */
    // function testPaidOutDelete_100_100() public {
    //     paidOutDelete_100_100();
    //     paidOut_2();
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 100 AND HAVE ALCHEMIST - part 1
    //  * Run some test before entering main testPaidOutDelete_100_100 test
    //  * include: test vote, donate, withdraw, payout / contractFundedInfo ... of campaign _100_100
    //  * (similar to paidOutDelete_100_90 above)
    //  */
    // function paidOutDelete_100_100_WithAlchemist() public campaignCreated(100, 100) initWLToken {
    //     paidOut_1(true);
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 100 AND HAVE ALCHEMIST - part 2
    //  * further test of paidOutDelete_100_100_WithAlchemist above
    //  */
    // function testPaidOutDelete_100_100_WithAlchemist() public {
    //     paidOutDelete_100_100_WithAlchemist();
    //     paidOut_2();
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 90 AND HAVE ALCHEMIST - part 1
    //  * Run some test before entering main testPaidOutDelete_100_90 test
    //  * include: test vote, donate, withdraw, payout / contractFundedInfo ... of campaign _100_90
    //  * (similar to paidOutDelete_100_90 above)
    //  */
    // function paidOutDelete_100_90_WithAlchemist() public campaignCreated(100, 90) initWLToken {
    //     paidOut_1(true);
    // }

    // /**
    //  * TESTING DONATION/ TIP CAMPAIGN - with pctForBacker = 90 AND HAVE ALCHEMIST - part 2
    //  * further test of paidOutDelete_100_90_WithAlchemist above
    //  */
    // function testPaidOutDelete_100_90_WithAlchemist() public {
    //     paidOutDelete_100_90_WithAlchemist();
    //     paidOut_2();
    // }

    function paidOutDelete_xxx_yyy(uint256 haveFundTarget, uint256 pctForBackers, bool changeAlchemist) public {
        // Tạo chiến dịch
        vm.startPrank(RAISER1);
        CreateCampaignInput memory c_input = initializeCreateCampaignData(haveFundTarget, pctForBackers);
        uint256 newCampaignId = giveUp.createCampaign(
            c_input.haveFundTarget,
            c_input.content,
            c_input.options,
            c_input.timeline,
            c_input.group,
            c_input.deList,
            c_input.fund,
            c_input.pctForBackers,
            ALCHEMIST1
        );
        vm.stopPrank();

        // Khởi tạo token whitelist
        vm.startPrank(giveUp.contractOwner());
        if (!giveUp.getIsTokenWhitelisted(address(ctk))) {
            giveUp.addWhiteListToken(address(ctk), FIRST_TOKEN);
        }
        if (!giveUp.getIsTokenWhitelisted(address(rotten))) {
            giveUp.addWhiteListToken(address(rotten), "rotten");
        }
        assert(giveUp.getIsTokenWhitelisted(address(ctk)));
        assert(giveUp.getIsTokenWhitelisted(address(rotten)));
        vm.stopPrank();

        // Thực hiện kiểm thử
        paidOut_1(changeAlchemist, newCampaignId);
        paidOut_2(newCampaignId);
    }

    function runPaidOutDeleteTests(TestParams memory params) private {
        for (uint256 i = 0; i < params.haveFundTargets.length; i++) {
            for (uint256 j = 0; j < params.pctForBackers.length; j++) {
                for (uint256 k = 0; k < params.changeAlchemists.length; k++) {
                    paidOutDelete_xxx_yyy(
                        params.haveFundTargets[i], params.pctForBackers[j], params.changeAlchemists[k]
                    );
                }
            }
        }
    }

    function testAllPaidOutDeleteCombinations() public {
        TestParams memory params = initializeTestParams();
        runPaidOutDeleteTests(params);

        // Note: need to add tests, e.g:
        // show how much fee platform get after some successful campaign
        // ...
    }

    /**
     * create a NORMAL campaign type when 0 < haveFundTarget < 100
     * this campaign type is used for TOKENIZATION which the result is LP SHARE TOKEN
     * TODO: ... should make it a modifer for other successor test similar to modifier successCampaign_100_0 case above
     */
    function testPaidOutDelete_90_10() public initWLToken {
        // Arrange: create campaign with haveFundTarget = 90
        CreateOrUpdate campaign_90_10 = new CreateOrUpdate();
        vm.startPrank(RAISER1);
        uint256 cId = campaign_90_10.createCampaign(giveUp, 90, 10);
        CampaignNoBacker memory c = getLatestCampaign();
        address raiser = c.cId.raiser;
        PaidoutOrDelete paidoutOrDelete = new PaidoutOrDelete();
        vm.startPrank(giveUp.contractOwner());
        uint256 newCTax = giveUp.changeTax(FEE_PCT_10); // giveUp.changeTax(10);
        vm.stopPrank();
        assertEq(newCTax, FEE_PCT_10);
        // arrange setting token name and symbol before calling payOutCampaign
        vm.startPrank(raiser);
        giveUp.setCampaignFinalTokenNameAndSymbol("resultToken", "RST", cId);
        vm.stopPrank();

        // Arrange donating:
        DonateOrVote donateOrVote = new DonateOrVote();
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)
        vm.startPrank(BACKER1); // donate ctk: SEND_TOKEN_AMT for option 0, feedback 1110
        bool donateWLTokenSuccess = donateOrVote.donateWLToken(giveUp, cId, 0, 1110, ctk, SEND_TOKEN_AMT);
        vm.stopPrank();
        assertEq(donateWLTokenSuccess, true);
        vm.startPrank(BACKER2); // donate native token: SEND_VALUE / 10 for option 1, feedback 1111
        bool donateAfterCampaignStart = donateOrVote.donate(giveUp, cId, 1, 1111, SEND_VALUE / 10);
        vm.stopPrank();
        assertEq(donateAfterCampaignStart, true);
        vm.startPrank(RAISER2); // donate native token: SEND_VALUE for option 1, feedback 1112
        bool donateAfterCampaignStartWithTargetAmt = donateOrVote.donate(giveUp, cId, 1, 1112, SEND_VALUE);
        vm.stopPrank();
        assertEq(donateAfterCampaignStartWithTargetAmt, true);

        // Assert: about backers and options voted/donated
        assertEq(giveUp.getBackerTokenFunded(cId, BACKER1, address(ctk)), SEND_TOKEN_AMT);
        assertEq(giveUp.getBackerNativeTokenFunded(cId, BACKER2), SEND_VALUE / 10);
        assertEq(giveUp.getBackerNativeTokenFunded(cId, RAISER2), SEND_VALUE);

        assertEq(giveUp.getOptionTokenFunded(cId, 0, address(ctk)), SEND_TOKEN_AMT);
        assertEq(giveUp.getOptionTokenFunded(cId, 1, address(ctk)), 0);
        assertEq(giveUp.getOptionNativeTokenFunded(cId, 1), (SEND_VALUE / 10) + (SEND_VALUE));

        // Assert: about payOut logic when 0 < haveFundTarge < 100
        vm.startPrank(raiser);
        vm.expectRevert("Invalid Pay Out Right");
        (TokenTemplate1 resultTokenFail,) = paidoutOrDelete.payOutCampaign(giveUp, cId);
        vm.stopPrank();
        console.log(
            "0 < haveFundTarge: raiser can't self payout unless set alchemist's address different to raiser and alchemist address must be approved by operator/community >> ",
            address(resultTokenFail)
        ); // └─ ← [Revert] ERC20InvalidSpender(0x0000000000000000000000000000000000000000)
            // giveUp.signAcceptance ?
            // giveUp.transferERC20
            // giveUp.updateAlchemist
        vm.startPrank(giveUp.contractOwner());
        giveUp.approveAlchemist(cId, false, "Approve origin alchemist suggested by raiser");
        vm.stopPrank();

        // Assert: raiser payout succesfully after Alchemist approved
        vm.startPrank(raiser);
        (TokenTemplate1 resultTokenSuccess, uint256 liquiditySuccess) = paidoutOrDelete.payOutCampaign(giveUp, cId);
        vm.stopPrank();
        assertEq(address(resultTokenSuccess) != address(0), true);
        assert(liquiditySuccess > 0);
    }

    /* ...testing add, remove white list token */
    function testWhiteListTokenInteractions() public {
        // uint256 snapshot = vm.snapshot(); // saves the state https://book.getfoundry.sh/cheatcodes/snapshots

        vm.startPrank(giveUp.contractOwner());
        giveUp.addWhiteListToken(address(rotten), FIRST_TOKEN);
        assertEq(giveUp.getIsTokenWhitelisted(address(rotten)), true);
        assertEq(giveUp.getTokenAddrToPriority(address(rotten)), FIRST_TOKEN);
        assertEq(giveUp.getPriorityToTokenAddr(FIRST_TOKEN), address(rotten));
        assertEq(giveUp.WLAddresses(0), address(rotten));

        vm.expectRevert("Priority is already used"); // because Priority FIRST_TOKEN is already used for rotten token above
        giveUp.addWhiteListToken(address(ctk), FIRST_TOKEN);

        // Arrange & Act: remove address(rotten)
        giveUp.removeWhiteListToken(address(rotten));
        // Assert
        assertEq(giveUp.getIsTokenWhitelisted(address(rotten)), false);
        assertEq(giveUp.getTokenAddrToPriority(address(rotten)), "");
        assertEq(giveUp.getPriorityToTokenAddr(FIRST_TOKEN), address(0));
        vm.expectRevert(); // "array is empty -> no item at index 0"
        giveUp.WLAddresses(0);

        // Arrange & Act: add address(ctk) again with previous failed priority
        giveUp.addWhiteListToken(address(ctk), FIRST_TOKEN);
        // Assert
        assertEq(giveUp.getIsTokenWhitelisted(address(ctk)), true);
        assertEq(giveUp.getTokenAddrToPriority(address(ctk)), FIRST_TOKEN);
        assertEq(giveUp.getPriorityToTokenAddr(FIRST_TOKEN), address(ctk));
        assertEq(giveUp.WLAddresses(0), address(ctk));
        vm.stopPrank();
        // vm.revertTo(snapshot); // restores the state
    }

    // function testDeleteCampaign() public campaign_100_0_Created initWLToken {
    function testDeleteCampaign() public campaignCreated(100, 0) initWLToken {
        // Arrange & Act 1: fund campaign successfully but not enough to meet target
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)

        // voteWLTokenAfterCampaignStart(BACKER1, MAX_RULES, 0, 0, address(ctk));
        // donateWLTokenAfterCampaignStart(BACKER1, MAX_RULES, 0, 1111, address(ctk), SEND_TOKEN_AMT); // ok but comment to test donate wl token using below script:
        vm.startPrank(BACKER1);
        DonateOrVote donateOrVote = new DonateOrVote();
        donateOrVote.voteWLToken(giveUp, MAX_RULES, 0, 0, ctk);
        donateOrVote.donateWLToken(giveUp, MAX_RULES, 0, 1111, ctk, SEND_TOKEN_AMT);

        // Assert 1a: contract accrued donation
        assertEq(giveUp.getContractFundedInfo().cTotalFirstToken, SEND_TOKEN_AMT);

        // Assert 1b: can not delete campaign if not the contract owner
        vm.expectRevert();
        giveUp.deleteCampaign(MAX_RULES);
        vm.stopPrank();
        // Assert 1c: even raiser CAN NOT delete campaign. (Can only refund if Campaign expired & failed or in REVERTING period!)
        vm.startPrank(RAISER1);
        vm.expectRevert();
        giveUp.deleteCampaign(MAX_RULES);
        vm.stopPrank();

        // Assert 1c: platform/contract owner can delete campaign and refund backer
        console.log("getTotalFundedCampaign before", giveUp.getContractFundedInfo().totalFundedCampaign);
        assertEq(giveUp.getContractFundedInfo().totalFundedCampaign, 1);
        CampaignNoBacker memory campaignBeforeDelete = getLatestCampaign();
        console.log(
            "campaignBeforeDelete.cFunded.raisedFund.firstTokenFunded",
            campaignBeforeDelete.cFunded.raisedFund.firstTokenFunded
        );
        vm.prank(giveUp.contractOwner());
        bool deleteSuccess = giveUp.deleteCampaign(MAX_RULES);
        CampaignNoBacker memory c = getLatestCampaign();
        assertEq(c.cFunded.paidOut.nativeTokenPaidOut, false); // nativeTokenPaidOut not change to true because this is a failed campaign
        assertEq(c.cFunded.raisedFund.firstTokenFunded, 0); // firstTokenFunded reset to 0 because this is a failed campaign and have to refund backers
        assertEq(c.cFunded.paidOut.firstTokenPaidOut, false); // similar to nativeTokenPaidOut, firstTokenPaidOut false = not paid out yet because this is a failed campaign
        assert(deleteSuccess);
        assertEq(c.cStatus.campaignStatus == campaignStatusEnum.DELETED, true); // campaign status changed to DELETED
        console.log("getTotalFundedCampaign after", giveUp.getContractFundedInfo().totalFundedCampaign);
        assertEq(giveUp.getContractFundedInfo().totalFundedCampaign, 0);

        // Assert 1d: contract deducted above refund amount.
        assertEq(giveUp.getContractFundedInfo().cTotalFirstToken, 0);
    }

/** temp: test if raiser can delete his non profit campaign? */
    function testDeleteCampaign_0_xxx() public campaignCreated(0, 99) initWLToken {
        // Arrange & Act 1: fund campaign successfully but not enough to meet target
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)

        // voteWLTokenAfterCampaignStart(BACKER1, MAX_RULES, 0, 0, address(ctk));
        // donateWLTokenAfterCampaignStart(BACKER1, MAX_RULES, 0, 1111, address(ctk), SEND_TOKEN_AMT); // ok but comment to test donate wl token using below script:
        vm.startPrank(BACKER1);
        DonateOrVote donateOrVote = new DonateOrVote();
        donateOrVote.voteWLToken(giveUp, MAX_RULES, 0, 0, ctk);
        donateOrVote.donateWLToken(giveUp, MAX_RULES, 0, 1111, ctk, SEND_TOKEN_AMT);

        // Assert 1a: contract accrued donation
        assertEq(giveUp.getContractFundedInfo().cTotalFirstToken, SEND_TOKEN_AMT);

        // Assert 1b: can not delete campaign if not the contract owner
        vm.expectRevert();
        giveUp.deleteCampaign(MAX_RULES);
        vm.stopPrank();

        console.log("getTotalFundedCampaign before delete success", giveUp.getContractFundedInfo().totalFundedCampaign);
        assertEq(giveUp.getContractFundedInfo().totalFundedCampaign, 1);
        CampaignNoBacker memory campaignBeforeDelete = getLatestCampaign();
        console.log(
            "campaignBeforeDelete.cFunded.raisedFund.firstTokenFunded",
            campaignBeforeDelete.cFunded.raisedFund.firstTokenFunded
        );
        console2.log("check that campaign is not expired - expect false, false", campaignBeforeDelete.cInfo.startAt > block.timestamp, campaignBeforeDelete.cInfo.deadline < block.timestamp);

        // Assert 1c: even raiser CAN NOT delete campaign if it's not expired. (Can only refund if Campaign expired & failed or in REVERTING period!)
        vm.startPrank(RAISER1);
        console.log("test raiser delete non profit campaign");
        vm.expectRevert();
        giveUp.deleteCampaign(MAX_RULES);
        // test if raiser can delete campaign if it's expired?
        vm.warp(block.timestamp + 86400 * 10); // set proper timeframe (for campaign to be expired)
        console2.log("print startAt, deadline, block.timestamp", campaignBeforeDelete.cInfo.startAt, campaignBeforeDelete.cInfo.deadline, block.timestamp);
        console2.log("check that campaign is not expired - expect false, false", campaignBeforeDelete.cInfo.startAt > block.timestamp, campaignBeforeDelete.cInfo.deadline < block.timestamp);
        // vm.startPrank(RAISER1);
        // can not delete because campaign already received fund and be prevented by checkDeletableCampaign(). Note: if want to delete and refund backer, we have to adjust checkDeletableCampaign().
        vm.expectRevert("Campaign' status: APPROVED_UNLIMITED -> Campaign can not be DELETED from now on except platform's operator!!!");
        bool raiserDeleteSuccess = giveUp.deleteCampaign(MAX_RULES);
        assertEq(raiserDeleteSuccess, false);
        vm.stopPrank();

        // Assert 1c: platform/contract owner can delete campaign and refund backer
        vm.prank(giveUp.contractOwner());
        bool deleteSuccess = giveUp.deleteCampaign(MAX_RULES);
        CampaignNoBacker memory c = getLatestCampaign();
        assertEq(c.cFunded.paidOut.nativeTokenPaidOut, false); // nativeTokenPaidOut not change to true because this is a failed campaign
        assertEq(c.cFunded.raisedFund.firstTokenFunded, 0); // firstTokenFunded reset to 0 because this is a failed campaign and have to refund backers
        assertEq(c.cFunded.paidOut.firstTokenPaidOut, false); // similar to nativeTokenPaidOut, firstTokenPaidOut false = not paid out yet because this is a failed campaign
        assert(deleteSuccess);
        assertEq(c.cStatus.campaignStatus == campaignStatusEnum.DELETED, true); // campaign status changed to DELETED
        console.log("getTotalFundedCampaign after", giveUp.getContractFundedInfo().totalFundedCampaign);
        assertEq(giveUp.getContractFundedInfo().totalFundedCampaign, 0);

        // Assert 1d: contract deducted above refund amount.
        assertEq(giveUp.getContractFundedInfo().cTotalFirstToken, 0);
    }

    /**
     * test vote, donate interaction with other information, mainly to check whether vote, donate result are correct
     * e.g: a backers vote, donate for many options, have feedback then withdraw votes, donation etc.
     * @dev Remember that donate with option also vote for that option. In general:
     *     - a donation by default is a vote plus a donate => will be recorded in cBacker mapping and have getter function getBackersOfCampaign
     *     - voter address will be record at cFunded.voterAddr
     * Todo: should make similar test for campaign type: normal (haveFundTarget < 100), non profit (haveFundTarget = 0)
     */
    // function testVoteDonateInteraction() public campaign_100_0_Created initWLToken {
    function testVoteDonateInteraction() public campaignCreated(100, 0) initWLToken {
        // Arrange 1: vote & donate.
        DonateOrVote donateOrVote = new DonateOrVote();
        Util util = new Util();
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)
        vm.startPrank(BACKER1);
        bool voteOption_1 = donateOrVote.vote(giveUp, MAX_RULES, 1, 0); // 1st vote
        vm.startPrank(BACKER1);
        bool donateOption_2_Feedback_2222 = donateOrVote.donate(giveUp, MAX_RULES, 2, 2222, SEND_VALUE / 10); // 1st donate
        vm.startPrank(BACKER1);
        bool voteWLTokenOption_0 = donateOrVote.voteWLToken(giveUp, MAX_RULES, 0, 0, ctk); // 2nd vote => total 3 votes, 1 donation until now
        vm.startPrank(BACKER1);
        bool donateWLTokenOption_4_Feedback_4444 =
            donateOrVote.donateWLToken(giveUp, MAX_RULES, 4, 4444, ctk, SEND_TOKEN_AMT); // 2nd donate => total 4 votes, 2 donations until now

        // Assert 1: check vote and donate result
        assertEq(voteOption_1, true);
        assertEq(donateOption_2_Feedback_2222, true);
        assertEq(voteWLTokenOption_0, true);
        assertEq(donateWLTokenOption_4_Feedback_4444, true);
        CampaignNoBacker memory c1 = getLatestCampaign();
        assertEq(c1.cFunded.voterCount, 1); // assert total backers address (both voter and donator) is 1 (only BACKER1 above)

        C_Backer[] memory backersBeforeWithdraw = giveUp.getBackersOfCampaign(MAX_RULES, true);
        vm.startPrank(BACKER1);
        assertEq(backersBeforeWithdraw.length, c1.cFunded.raisedFund.totalDonating); // assert total donations is ALWAYS equal totalDonating
        console.log(
            "NOTE: cFunded.raisedFund.totalDonating will save total donating, cFunded.raisedFund.presentDonating only save active donating"
        );
        console.log(
            "cFunded.raisedFund.totalDonating ALWAYS equal backers' length, now it = ", backersBeforeWithdraw.length
        );

        VoteData[] memory backer1_votes_before_withdraw = util.getVoterOptions(giveUp, MAX_RULES);
        assertEq(backer1_votes_before_withdraw.length, 4); // assert total votes until now is 4
        console.log("backer1_votes_before_withdraw: (will be 4) >> ", backer1_votes_before_withdraw.length);

        // Arrange & Act 2: in testDonateVoteWithdraw_100_0 already test unvote/ undonate with incorrect option, now we'll test unvote/ undonate with correct option
        vm.startPrank(BACKER1);
        string memory withdrawVoteOption_1 = giveUp.requestRefund(MAX_RULES, true, 1); // withdraw vote for option 1
        assertEq(getLatestCampaign().cFunded.voterCount, 1); // "check cFunded.voterAddr.length after 1 withdraw: (1 will be correct)
        console.log("|-> requestRefund - withdrawVoteOption_1: ", withdrawVoteOption_1);
        vm.startPrank(BACKER1);
        string memory withdrawDonateWLTokenOption_4_Feedback_4444 = giveUp.requestRefund(MAX_RULES, true, 4); // withdraw donate for option 4
        assertEq(getLatestCampaign().cFunded.voterCount, 1); // "check cFunded.voterAddr.length after 2 withdraw: (1 will be correct)
        console.log(
            "|-> requestRefund - withdrawDonateWLTokenOption_4_Feedback_4444: ",
            withdrawDonateWLTokenOption_4_Feedback_4444
        );
        vm.stopPrank();
        // Assert 2a: withdraws success
        assertEq(withdrawVoteOption_1, "Remove vote option SUCCESS + Nothing to refund");
        assertEq(withdrawDonateWLTokenOption_4_Feedback_4444, "Processed 1 donation(s)");
        // Assert 2b: update campaign info again and make assertion
        C_Backer[] memory backersAfterWithdraws = giveUp.getBackersOfCampaign(MAX_RULES, true);
        CampaignNoBacker memory c2 = getLatestCampaign();
        uint256 totalVoter = c2.cFunded.voterCount;
        for (uint256 i = 0; i < totalVoter; i++) {
            console.log("voter addr at index ", i, " >> ", giveUp.getCampaignVoter(MAX_RULES, i));
        }
        assertEq(backersAfterWithdraws.length, c2.cFunded.raisedFund.totalDonating); // assert total donations is ALWAYS equal totalDonating
        assertEq(c2.cFunded.raisedFund.presentDonating, c2.cFunded.raisedFund.totalDonating - 1); // because withdrew 1 donation for option 4 above
        vm.startPrank(BACKER1);
        VoteData[] memory backer1_votes_after_withdraws = util.getVoterOptions(giveUp, MAX_RULES);
        if (backer1_votes_after_withdraws.length > 0) {
            assertEq(backer1_votes_after_withdraws.length, 2);
            console.log("backer1_votes_after_withdraws: (2 will be correct)", backer1_votes_after_withdraws.length); // because withdraw 1 vote, 1 donation in total 4
            assertEq(c2.cFunded.voterCount, 1);
            console.log(
                "if there's vote from backer1 then voterAddr.length = (1 will be correct) ", c2.cFunded.voterCount
            );
        }
        // AAA 3: backer1 continue withdraw all options -> check voterAddr.length, refunded
        vm.startPrank(BACKER1);
        string memory backer1WithdrawAllOptions = giveUp.requestRefund(MAX_RULES, true, BACKER_WITHDRAW_ALL_CODE);
        // instead of withdraw all using code BACKER_WITHDRAW_ALL_CODE above, can replace by 2 separate withdraws as below code
        // string memory backer1WithdrawAllOptions = giveUp.requestRefund(MAX_RULES, true, 2);
        // vm.startPrank(BACKER1);
        // string memory withdrawOption0 = giveUp.requestRefund(MAX_RULES, true, 0);

        assertEq(backer1WithdrawAllOptions, "Processed 1 donation(s)"); // because knowing that only 1 donation left
        CampaignNoBacker memory c3 = getLatestCampaign();
        assertEq(c3.cFunded.voterCount, 0); // no voter/ backer left
        assertEq(c3.cFunded.raisedFund.presentDonating, 0); // no backer left
        C_Backer[] memory backersAfterWithdrawAll = giveUp.getBackersOfCampaign(MAX_RULES, true);
        assertEq(backersAfterWithdrawAll.length, c2.cFunded.raisedFund.totalDonating); // assert total donations is ALWAYS equal totalDonating
        assertEq(backersAfterWithdrawAll[0].backer, address(BACKER1));
        for (uint256 i = 0; i < backersAfterWithdrawAll.length; i++) {
            // assertEq(backersAfterWithdrawAll[i].refunded, true); // e.g. succeed
            assertEq(backersAfterWithdrawAll[i].fundInfo.refunded, true); // e.g. succeed
        }
        vm.stopPrank();
    }

    /**
     * Test scenario: Non Profit Campaign Interactions Between Raiser, Alchemist, Community and Platform Operator. Focusing on who can finally payout.
     * - Supposedly Raiser don't want community to propose Alchemist except Raiser himself, he want to propose a fraud Alchemist to benefit raiser, in this case he deliberately turn off the option that allow community to change Alchemist (turnOffCommunityProposeAlchemist) -> assert community can not change it after campaign started.
     * - Operator approve the Alchemist proposal.
     * - Community reported some fraud
     * ***** end part 1 test => testNonProfitCampaignPayoutRight_P1() *****
     * ***** start part 2 test => testNonProfitCampaignPayoutRight_P2() *****
     * - Community want to change Alchemist proposal and submit with proofs
     * - Base on rules: (BACKERS COMMUNITY FIRST - BECAUSE THEY'RE THE PAYER) Operator approve community proposal and set campaign to the situation that neither raiser or alchemist can payout until community set new Alchemist.
     * - Then the community set their prefered Alchemist -> campaign can be paidout and new Alchemist can receive payout.
     * - NOTE: JUST IDEA: Besides, operator could set campaign status to SUSPENDING to prevent raiser or alchemist from payout when community report fraud (highest level of report), it'll also help not to receive further donation/contribution.
     * - Assert the payout (try with raiser and alchemist)
     */
    // function testNonProfitCampaignPayoutRight_P1() public campaign_0_90_Created {
    function testNonProfitCampaignPayoutRight_P1() public campaignCreated(0, 90) {
        // Assert 1: raiser turn off the option that allow community to change Alchemist
        (Alchemist memory alchemistBefore,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(alchemistBefore.raiserPrivilegeInNoTargetCampaign, false);
        vm.startPrank(RAISER1);
        giveUp.turnOffCommunityProposeAlchemist(MAX_RULES);
        vm.stopPrank();
        (Alchemist memory alchemistAfter,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(alchemistAfter.raiserPrivilegeInNoTargetCampaign, true); // turn off the option successfully
        // Sub assert: before campaign start, raiser can set name and symbol for the token that will be created to reward backers in case campaign success
        vm.startPrank(RAISER1);
        bool setTokenNameAndSymbol = giveUp.setCampaignFinalTokenNameAndSymbol("RaisersToken", "RTK", MAX_RULES);
        assertEq(setTokenNameAndSymbol, true);
        vm.stopPrank();

        // Arrange for campaign start then make 2 donations
        vm.warp(block.timestamp + 86400 * 4);
        DonateOrVote donateOrVote = new DonateOrVote();
        vm.startPrank(BACKER1);
        donateOrVote.donate(giveUp, MAX_RULES, 0, 0, SEND_VALUE);
        vm.stopPrank();
        vm.startPrank(BACKER2);
        donateOrVote.donate(giveUp, MAX_RULES, 0, 0, SEND_VALUE);
        vm.stopPrank();
        assertEq(getLatestCampaign().cFunded.raisedFund.amtFunded, SEND_VALUE * 2);
        // Sub assert: raiser change name and symbol for campaign final token but fail because campaign has started
        vm.startPrank(RAISER1);
        vm.expectRevert();
        giveUp.setCampaignFinalTokenNameAndSymbol("RaisersToken2", "RTK2", MAX_RULES);
        vm.stopPrank();

        // Arrange backer1 report fraud (1st report)
        string memory fraudContent = "this is fake Blast Layer 2 account, real one is https://blast.io/";
        vm.startPrank(BACKER1);
        (bool success, uint256 fraudIndex, uint256 fraudRealtimePct) =
            giveUp.backerAddFraudReport(MAX_RULES, fraudContent);
        // Assert backer1 report fraud
        vm.stopPrank();
        assertEq(success, true);
        assertEq(fraudIndex, 0);
        assertEq(fraudRealtimePct, 50); // expect 50%
        // Assert getter function getBackerFraudReport, getRateDetailOfFraudReport work correctly after above report
        FraudReport memory fraudReport = giveUp.getBackerFraudReport(MAX_RULES, BACKER1);
        assertEq(fraudReport.isFraudNow, true);
        assertEq(fraudReport.reportId, 0);
        assertEq(fraudReport.reportIDHistory.length, 1);
        RateDetail memory rateDetail = giveUp.getRateDetailOfFraudReport(MAX_RULES, 0);
        assertEq(rateDetail.rater, BACKER1);
        assertEq(rateDetail.timestamp > 0, true);
        console.log("rateDetail.timestamp", rateDetail.timestamp);
        assertEq(rateDetail.star, 0);
        assertEq(rateDetail.campaignId, MAX_RULES);
        assertEq(rateDetail.ratedObject, "raiser");
        assertEq(rateDetail.content, fraudContent);
        // Assert fraudRateIndexes in mappingCId updated correctly
        (,,,, FraudRateIndexes memory fraudRateIndexes,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(fraudRateIndexes.rateId, 0); // no normal rate so far, so next id is 0
        assertEq(fraudRateIndexes.fraudReportId, 1); // there's 1 fraud report from BACKER1 above, so next id (or total fraud report so far) is 1
        assertEq(fraudRateIndexes.fraudPct, fraudRealtimePct); // expect 100%
        assertEq(fraudRateIndexes.fraudReportCounter, 1); // expect 1 fraud report in this campaign as a result of add fraud report by BACKER1 above

        // Arrange BACKER2 add another (2nd) fraud report to test reportId, fraudReportId
        string memory fraudContent1 = "this is 2nd fraud report - frome different backer";
        vm.startPrank(BACKER2);
        (bool success1, uint256 fraudIndex1, uint256 fraudRealtimePct1) =
            giveUp.backerAddFraudReport(MAX_RULES, fraudContent1);
        // Assert backer2 report fraud
        vm.stopPrank();
        assertEq(success1, true);
        assertEq(fraudIndex1, 1); // expect 1
        assertEq(fraudRealtimePct1, 100); // expect 100%
        // assert fraudIndex1 above is reportId in FraudReport of BACKER2 which equal 1 (2nd report)
        FraudReport memory backer2FraudReport = giveUp.getBackerFraudReport(MAX_RULES, BACKER2);
        assertEq(backer2FraudReport.reportId, 1);
        assertEq(backer2FraudReport.reportIDHistory.length, 1); // expect [1] so length = 1
        // assert fraudReportId in fraudRateIndexes of mappingCId now show total 2 report and also jump to 2 which will be the next index of future Fraud report
        (,,,, FraudRateIndexes memory fraudRateIndexes1,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(fraudRateIndexes1.fraudReportId, 2);
        assertEq(fraudRateIndexes1.fraudReportCounter, 2); // e.g 2 backer reported fraud so far!

        // Arrange backer1 remove his previous fraud report
        vm.startPrank(BACKER1);
        giveUp.backerRemoveFraudReport(MAX_RULES, "backer1 remove his previous fraud report because it's testing");
        vm.stopPrank();
        // Assert getter function getBackerFraudReport, getRateDetailOfFraudReport work correctly after above remove report
        FraudReport memory fraudReportAfterRemove = giveUp.getBackerFraudReport(MAX_RULES, BACKER1);
        assertEq(fraudReportAfterRemove.isFraudNow, false);
        assertEq(fraudReportAfterRemove.reportId, 2); // because 2 add action + 1 remove action so the index accrued is 2 (0, 1, 2)
        assertEq(fraudReportAfterRemove.reportIDHistory.length, 2); // expect [0, 2] so length = 2 (can see in terminal)
        RateDetail memory rateDetailAfterRemove = giveUp.getRateDetailOfFraudReport(MAX_RULES, 2); // 2 is fraudReportAfterRemove.reportId aboves
        assertEq(rateDetailAfterRemove.rater, BACKER1);
        assertEq(rateDetailAfterRemove.timestamp, block.timestamp);
        assertEq(rateDetailAfterRemove.star, 0);
        assertEq(rateDetailAfterRemove.campaignId, MAX_RULES);
        assertEq(rateDetailAfterRemove.ratedObject, "raiser");
        assertEq(rateDetailAfterRemove.content, "backer1 remove his previous fraud report because it's testing");
        // Assert fraudRateIndexes in mappingCId updated correctly
        (,,,, FraudRateIndexes memory fraudRateIndexesAfter,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(fraudRateIndexesAfter.rateId, 0); // no normal rate so far, so next id is 0
        assertEq(fraudRateIndexesAfter.fraudReportId, 3); // there's 3 fraud report from BACKER1 above so far (2 add, 1 remove), so next id (or total fraud report so far) is 3
        assertEq(fraudRateIndexesAfter.fraudPct, 50); // expect 50%
        assertEq(fraudRateIndexesAfter.fraudReportCounter, 1); // expect deducting 1 fraud report in this campaign as a result of remove fraud report by BACKER1 above => 2 -1 = 1
    }

    /**
     * continue from testNonProfitCampaignPayoutRight_P1()
     */
    function testNonProfitCampaignPayoutRight_P2() public {
        testNonProfitCampaignPayoutRight_P1();
        // operator veto raiser' Alchemist proposal
        string memory fraudProof = "link to show the proof of fraud";
        bool vetoAlchemistProposalFromRaiser = true;
        vm.startPrank(giveUp.contractOwner());
        giveUp.approveAlchemist(MAX_RULES, vetoAlchemistProposalFromRaiser, fraudProof);
        vm.stopPrank();
        // assert Alchemist veto
        (Alchemist memory alchemist,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(alchemist.addr, address(0));
        assertEq(alchemist.isApproved, true);
        // community propose new Alchemist but fail because community address is not set yet
        vm.expectRevert();
        giveUp.communityProposeAlchemist(MAX_RULES, ALCHEMIST2);
        // operator set community address
        vm.startPrank(giveUp.contractOwner());
        giveUp.setCommunityAddress(MAX_RULES, COMMUNITY1, "This campaign has fraud report percentage: fraudPct >= 50%");
        vm.stopPrank();
        // community can now propose new Alchemist
        vm.startPrank(COMMUNITY1);
        giveUp.communityProposeAlchemist(MAX_RULES, ALCHEMIST1);
        vm.stopPrank();
        (Alchemist memory alchemistAfterCommunityPropose,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(alchemistAfterCommunityPropose.addr, ALCHEMIST1);
        assertEq(alchemistAfterCommunityPropose.isApproved, true);
        // Arrange: in case community want to change Alchemist again -> Operator can help
        vm.startPrank(giveUp.contractOwner());
        giveUp.approveAlchemist(
            MAX_RULES, vetoAlchemistProposalFromRaiser, "proof about community want to change Alchemist 2nd time"
        );
        vm.stopPrank();
        // community propose new Alchemist
        vm.startPrank(COMMUNITY1);
        giveUp.communityProposeAlchemist(MAX_RULES, ALCHEMIST2);
        vm.stopPrank();
        (Alchemist memory alchemistAfterCommunityPropose2,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        // Assert: community propose new Alchemist successfuly
        assertEq(alchemistAfterCommunityPropose2.addr, ALCHEMIST2);
        assertEq(alchemistAfterCommunityPropose2.isApproved, true);
        // Assert raiser can't pay out in NON PROFIT campaign (they have to have Alchemist doing that)
        vm.startPrank(RAISER1);
        vm.expectRevert(); // "Invalid Pay Out Right"
        giveUp.payOutCampaign(MAX_RULES);
        vm.stopPrank();
        // Assert only Alchemist can TRIGGER pay out in NON PROFIT campaign (assert via successfully created token and liquidity pool for everyone to withdraw later on)
        vm.startPrank(ALCHEMIST2);
        (TokenTemplate1 resultTokenSuccessViaAlchemist, uint256 liquiditySuccessViaAlchemist) =
            giveUp.payOutCampaign(MAX_RULES);
        assertEq(address(resultTokenSuccessViaAlchemist) != address(0), true);
        assert(liquiditySuccessViaAlchemist > 0);
        vm.stopPrank();

        // Sub assert AFTER ABOVE PAYOUT SUCCESS: community change name and symbol for campaign final token failed because it's set
        vm.startPrank(COMMUNITY1);
        vm.expectRevert();
        giveUp.setCampaignFinalTokenNameAndSymbol("CommunityToken", "CTK", MAX_RULES);
        vm.stopPrank();
        // expect fail: operator help to reset symbol in order for community to change it's symbol again
        vm.startPrank(giveUp.contractOwner());
        vm.expectRevert("Token already created");
        giveUp.resetTokenSymbol(MAX_RULES);
        vm.startPrank(COMMUNITY1);
        vm.expectRevert("Token already set");
        giveUp.setCampaignFinalTokenNameAndSymbol("CommunityTokenGreatAgain", "CTKA", MAX_RULES);
        (,,,,, CampaignToken memory campaignToken) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(campaignToken.tokenSymbol, "RTK"); // symbol still not change to CTKA

        // TODO: update payOutCampaign thoroughly that allow participant to self withdraw.
    }
}
