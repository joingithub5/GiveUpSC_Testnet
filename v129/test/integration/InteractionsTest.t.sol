//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {GiveUp129} from "../../src/GiveUp_129.sol";
import {DeployGiveUp129} from "../../script/DeployGiveUp129.s.sol";
import "../unit/Input_Params.sol";
import "../../src/GlobalVariables_12x.sol";
import {CommunityToken} from "../mock/CTK.sol";
import {RottenToken} from "../mock/ROTTEN.sol";
import {AnyToken} from "../mock/ANY.sol";
import {CreateOrUpdate, DonateOrVote, WithdrawOrRefund, PaidoutOrDelete, Util} from "../../script/Interactions.s.sol";

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

    function setUp() external {
        uint256 platformFee = 0; // if pass these params from outside will cost gas
        string memory nativeTokenSymbol = "ETH";
        DeployGiveUp129 deployGiveUp129 = new DeployGiveUp129();
        (giveUp, ctk, rotten, any) = deployGiveUp129.run(platformFee, nativeTokenSymbol);
        vm.deal(RAISER1, STARTING_USER_BALANCE);
        vm.deal(RAISER2, STARTING_USER_BALANCE);
        vm.deal(BACKER1, STARTING_USER_BALANCE);
        vm.deal(BACKER2, STARTING_USER_BALANCE);
        console.log("address of giveUp, address of this GiveUp129Test: ", address(giveUp), address(this));
    }

    /**
     * donation campaign type, no Alchemist
     */
    modifier campaign_100_0_Created() {
        CreateCampaignInput memory c_input = initializeCampaignData_100_0(); // set target fund is 0.1 ether (SEND_VALUE)
        vm.prank(RAISER1); // create a normal campaign via RAISER1, not via address(this)
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
        assertEq(returnCId, giveUp.presentCId() - 1);
        _;
    }

    /**
     * Non Profit Campaign Type + have Alchemist
     */
    modifier campaign_0_90_Created() {
        vm.prank(RAISER1);
        CreateCampaignInput memory c_input = initializeCreateCampaignData(0, 90);
        giveUp.createCampaign(
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
        _;
    }

    modifier initWLToken() {
        vm.startPrank(giveUp.contractOwner());
        giveUp.addWhiteListToken(address(ctk), "firstToken");
        giveUp.addWhiteListToken(address(rotten), "rotten");
        assert(giveUp.getIsTokenWhitelisted(address(ctk)));
        assert(giveUp.getIsTokenWhitelisted(address(rotten)));
        vm.stopPrank();
        _;
    }

    function getLatestCampaign() public view returns (CampaignNoBacker memory) {
        CampaignNoBacker[] memory campaignsNoBacker = giveUp.getCampaigns();
        CampaignNoBacker memory campaign = campaignsNoBacker[(giveUp.presentCId() - 1) - MAX_RULES]; // cause getCampaigns() compressed and reindexed
        return campaign;
    }

    /* test updateCampaign:
    1. contract owner CAN'T update raiser's campaign if he IS NOT the raiser ...
    2. only raiser can update ...
    3. ... with strict condition ... 
    forge test --match-test testUpdateCampaign -vvvv
    */
    function testUpdateCampaign() public campaign_100_0_Created {
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
        uintFieldToChange[0] = "firstTokenTarget"; // update fund target, arrange "firstToken" is CTK token
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
            assertEq(campaignAfterUpdate.cFunded.firstTokenTarget, 0);
            assertEq(campaignAfterUpdate.cFunded.equivalentUSDTarget, 0);
        } else {
            assertEq(campaignAfterUpdate.cFunded.firstTokenTarget, uintValueToChange[0]);
            assertEq(campaignAfterUpdate.cFunded.equivalentUSDTarget, uintValueToChange[1]);
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
        // bool voteSuccess = donateToCampaign(0, cId, 0, 0);
        bool voteSuccess = donateOrVote.vote(giveUp, cId, 0, 0);
        vm.stopPrank();
        // Assert 3: anyone can vote after campaign start
        assertEq(voteSuccess, true);

        // AAA 4: then the raiser want to update campaign (for example: change haveFundTarget) but fail because campaign can not be updated after started
        vm.startPrank(raiser);
        vm.expectRevert("start time must be now or in future");
        createOrUpdate.updateCampaign(
            giveUp, cId, newHaveFundTarget, newPctForBackers, uintFieldToChange, uintValueToChange
        );

        // // AAA 5: the raiser try again with new data inputs but still fail (same reason as AAA 4) -- obmit because CompilerError: Stack too deep ...
        // string[] memory uintFieldToChange1 = new string[](1);
        // uintFieldToChange1[0] = "startAt";
        // uint256[] memory uintValueToChange1 = new uint256[](1);
        // uintValueToChange1[0] = block.timestamp + 60; // add 60 seconds
        // // UpdateCampaignInput memory data1 = initializeUpdateCampaignData(
        // //     cId, newHaveFundTarget, newPctForBackers, uintFieldToChange1, uintValueToChange1
        // // );
        // vm.expectRevert();
        // // bool success5 = updateCampaign(data1);
        // createOrUpdate.updateCampaign(
        //     giveUp, cId, newHaveFundTarget, newPctForBackers, uintFieldToChange1, uintValueToChange1
        // );
        // // console.log("Assert that raiser can not update campaign after started! >>", success5);
        vm.stopPrank();
    }

    /* test donateToCampaign, requestRefund: _100_0 is campaign type that has 100% fund for raiser, 0% for backers
    1. donate/vote will fail before startAt time 
    2. ... set proper timeframe (after campaign start) -> donate, withdraw
    3. = 2nd test + enough donation amount to trigger campaign 'APPROVED' status
    4. donate fail after campaign is 'APPROVED' (different from testDonateToCampaign_0_90())
    => notice emit Action
    forge test --match-test testDonateToCampaign -vvvv
    */
    function testDonateVoteWithdraw_100_0() public campaign_100_0_Created initWLToken {
        // Arrange & Act 1 : test donateToCampaign before campaign start -> will fail
        DonateOrVote donateOrVote = new DonateOrVote();
        vm.startPrank(BACKER2);
        vm.expectRevert("Campaign' status: OPEN -> Campaign can NOT be donated."); // Assert 1: campaign can not be donate before started
        // bool donateBeforeCampaignStart = donateToCampaign(SEND_VALUE, MAX_RULES, 0, 0);
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
        assertEq(getLatestCampaign().cFunded.amtFunded, SEND_VALUE / 10);

        // Assert 2b: test donateWhiteListTokenToCampaign (vote & donate)
        // at frist I use donateWLTokenAfterCampaignStart() but later move it to sc/v129/script/Interactions.s.sol -> voteWLToken, donateWLToken
        // bool voteWLTokenSuccess = voteWLTokenAfterCampaignStart(BACKER1, MAX_RULES, 0, 0, address(ctk));
        // bool donateWLTokenSuccess =
        //     donateWLTokenAfterCampaignStart(BACKER1, MAX_RULES, 0, 1111, address(ctk), SEND_TOKEN_AMT);
        vm.startPrank(BACKER1);
        bool voteWLTokenSuccess = donateOrVote.voteWLToken(giveUp, MAX_RULES, 0, 0, ctk);
        vm.startPrank(BACKER1);
        // vm.prank(BACKER1); // >> [FAIL. Reason: cannot override an ongoing prank with a single vm.prank; use vm.startPrank to override the current prank]
        bool donateWLTokenSuccess = donateOrVote.donateWLToken(giveUp, MAX_RULES, 0, 1111, ctk, SEND_TOKEN_AMT);
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

        // Arrange & Act 2c: test requestRefund with an incorrect option
        vm.prank(BACKER1);
        string memory withdrawWIncorrectOption = giveUp.requestRefund(MAX_RULES, true, 1);
        // Assert 2c: Can not refund/ withdraw because provided option is not correct
        assertEq(withdrawWIncorrectOption, "Remove vote option FAILED + Nothing to refund");
        console.log("|-> requestRefund - withdrawWOption: ", withdrawWIncorrectOption);

        // Assert 2d: test requestRefund all options (mean not donate or vote for any option anymore) -> will be checked for timelock
        vm.prank(BACKER1);
        string memory withdrawAllOptions = giveUp.requestRefund(MAX_RULES, true, 99);
        C_Backer[] memory backers = giveUp.getBackersOfCampaign(MAX_RULES);
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
        ); // BACKER CAN NOT withdraw if a DONATION campaign (distinguished by haveFundTarget > 0) is 'APPROVED' !!! BE CAUTION !!!
        string memory withdrawAfterCampaignMetTarget = giveUp.requestRefund(MAX_RULES, true, 99);
        console.log(
            "|-> requestRefund - withdrawAfterCampaignMetTarget: try to withdraw but fail because campaign is 'APPROVED' and haveFundTarget > 0",
            withdrawAfterCampaignMetTarget
        );
        CampaignNoBacker memory c = getLatestCampaign();
        assert(c.cFunded.amtFunded >= c.cFunded.target);
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
        vm.expectRevert("Campaign' status: APPROVED -> Campaign can NOT be donated."); // Moreover BACKER CAN NOT DONATE MORE THAN THE EXPECTED TARGET if a DONATION campaign (distinguished by haveFundTarget > 0) is 'APPROVED' !!! NOTICE !!!
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
     */
    function testDonateVoteWithdraw_0_90_p1() public initWLToken {
        /* NOTE:
        Because haveFundTarget = 0 -> this is a non profit campaign -> when have any donation, campaign status
        will be "APPROVED_UNLIMITED" (not "APPROVED")
        */

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
        // bool donateBeforeCampaignStart = donateToCampaign(SEND_VALUE, MAX_RULES, 0, 0);
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
        assertEq(getLatestCampaign().cFunded.amtFunded, SEND_VALUE / 10);

        // Assert 2b: test donateWhiteListTokenToCampaign (vote & donate)
        vm.startPrank(BACKER1);
        bool voteWLTokenSuccess = donateOrVote.voteWLToken(giveUp, cId, 0, 0, ctk);
        vm.startPrank(BACKER1);
        // vm.prank(BACKER1); // >> [FAIL. Reason: cannot override an ongoing prank with a single vm.prank; use vm.startPrank to override the current prank]
        bool donateWLTokenSuccess = donateOrVote.donateWLToken(giveUp, cId, 0, 1111, ctk, SEND_TOKEN_AMT);
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
        // Assert 2c: Can not refund/ withdraw because provided option is not correct
        assertEq(withdrawWOption, "Remove vote option FAILED + Nothing to refund");
        console.log("|-> requestRefund - withdrawWOption: ", withdrawWOption);

        // Assert 2d: test requestRefund all options (mean not donate or vote for any option anymore) -> will need 2 step, 1st: register, 2nd: wait for timelock to over then withdraw
        vm.prank(BACKER1);
        string memory withdrawAllOptions_register = giveUp.requestRefund(cId, true, 99);
        assertEq(
            withdrawAllOptions_register,
            "Successfully registered early withdrawal at timelock index 1. Please wait and make withdraw again AFTER 3 block numbers!"
        ); // hard code the return message to test
        // Arrange 2e: assuming 1 block.number == 60 seconds, we increase 1 block.number and increase timestamp 60 seconds
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 60);
        // Act 2e: test requestRefund 2nd times after successfully registered but still in delay time frame (3 blocks) -> expect falure notice
        vm.prank(BACKER1);
        string memory withdrawAllOptions_WithinDelayTimeFrame = giveUp.requestRefund(cId, true, 99);
        assertEq(
            withdrawAllOptions_WithinDelayTimeFrame,
            "You are in waiting period of 3 block numbers, please wait until it's over!. Index: 1"
        ); // hard code the return message to test
        // Arrange 2f: continue to increase 3 block.number and timestamp correspondingly
        vm.roll(block.number + 3);
        vm.warp(block.timestamp + 180);
        // Act 2f: test requestRefund 3rd times after successfully registered and after waiting period
        vm.prank(BACKER1);
        string memory withdrawAllOptions_3rdTime = giveUp.requestRefund(cId, true, 99);
        // Assert 2f: withdraw success
        C_Backer[] memory backers = giveUp.getBackersOfCampaign(cId);
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
        // Arrange S1: BACKER2 trigger withdraw all
        vm.startPrank(BACKER2);
        string memory withdrawAfterCampaignApprovedUnlimitted = giveUp.requestRefund(cId, true, 99);
        assertEq(
            withdrawAfterCampaignApprovedUnlimitted,
            "Successfully registered early withdrawal at timelock index 0. Please wait and make withdraw again AFTER 3 block numbers!"
        ); // hard code the return message to test

        // Arrange S1: assuming 1 block time pass
        vm.warp(block.timestamp + 60); // 345901
        vm.roll(block.number + 1); // 6
        // Assert S1: backer trigger withdraw all again while in waiting period -> expect falure notice
        // vm.prank(BACKER2);
        string memory withdrawAllOptions_WithinDelayTimeFrame = giveUp.requestRefund(cId, true, 99);
        assertEq(
            withdrawAllOptions_WithinDelayTimeFrame,
            "You are in waiting period of 3 block numbers, please wait until it's over!. Index: 0"
        ); // hard code the return message to test
        // C_Backer[] memory backers_temp_to_check = giveUp.getBackersOfCampaign(cId);
        // console.log(backers_temp_to_check[0].fundInfo.requestRefundBlockNumber);

        // Arrange S1: while wait donate for another option
        vm.startPrank(BACKER2);
        bool donateToAnotherOptionS1 = donateOrVote.donate(giveUp, cId, 1, 1999, SEND_VALUE);
        assertEq(donateToAnotherOptionS1, true);
        // Arrange S1: after waiting time he proceed withdraw all
        vm.warp(block.timestamp + 240); // 346141
        vm.roll(block.number + 4); // 10
        // vm.warp(block.timestamp + 240);
        // vm.roll(block.number + 4);
        console.log("block.number", block.number, "timestamp", block.timestamp);
        // Assert S1: try withdraw all -> expect success
        vm.startPrank(BACKER2);
        string memory withdrawAll_S1_Final = giveUp.requestRefund(cId, true, 99);
        console.log("withdrawAll_S1_Final", withdrawAll_S1_Final);
        C_Backer[] memory backers = giveUp.getBackersOfCampaign(cId);
        C_Backer memory latestBacker = backers[backers.length - 1];
        assertEq(
            withdrawAll_S1_Final,
            "Successfully registered early withdrawal at timelock index 2. Please wait and make withdraw again AFTER 3 block numbers!"
        ); // hard code the return message to test
        assertEq(latestBacker.backer, address(BACKER2));
        assertEq(backers[0].backer, address(BACKER2)); // make sure we're working with the same backer
        assertEq(backers[0].fundInfo.refunded, false); // and this backer, at previous return index 0, is not refunded yet

        // làm thêm hàm get contribution of a campaign at specific index

        // /* OLD CODE:
        // 3b: then try to withdraw WILL ALWAYS SUCCEED because campaign is "APPROVED_UNLIMITED" and haveFundTarget = 0 */
        // vm.startPrank(BACKER2);
        // string memory withdrawAfterCampaignApprovedUnlimitted = giveUp.requestRefund(cId, true, 99);
        // C_Backer[] memory backers1 = giveUp.getBackersOfCampaign(cId);
        // C_Backer memory latestBacker1 = backers1[backers1.length - 1];
        // assertEq(latestBacker1.backer, address(BACKER2));

        // console.log(
        //     "|-> requestRefund - withdrawAfterCampaignApprovedUnlimitted: try to withdraw WILL ALWAYS SUCCEED because campaign is 'APPROVED_UNLIMITED' and haveFundTarget = 0",
        //     withdrawAfterCampaignApprovedUnlimitted
        // );
        // CampaignNoBacker memory c = getLatestCampaign();
        // assert(c.cFunded.amtFunded >= c.cFunded.target);
        // console.log(
        //     "3. = 2nd test + ANY donation amount to trigger campaign 'APPROVED_UNLIMITED' status: ",
        //     donateAfterCampaignStartWithAnyAmt,
        //     " check contract balance = ",
        //     address(giveUp).balance
        // );
        // // assertEq(latestBacker1.refunded, true); // e.g. succeed
        // assertEq(latestBacker1.fundInfo.refunded, true); // e.g. succeed
    }

    /**
     * ... vote, donate, withdraw, payout / contractFundedInfo ...
     */
    function testPaidOutDelete_100_0() public campaign_100_0_Created initWLToken {
        DonateOrVote donateOrVote = new DonateOrVote();
        PaidoutOrDelete paidoutOrDelete = new PaidoutOrDelete();
        uint256 raiserBalanceBeforePaidout = RAISER1.balance;
        uint256 raiserCTK_BalanceBeforePaidout = ctk.balanceOf(RAISER1);
        uint256 nativeTokenDonation = 0;
        uint256 ctkTokenDonation = 0;
        // Assert: Alchemist not effect payout when haveFundTarget = 100 (raiser have all the power to payout)
        vm.startPrank(RAISER1);
        giveUp.raiserChangeAlchemist(MAX_RULES, payable(address(0)));
        (Alchemist memory alchemistBeforeCampaignStart,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(address(0), alchemistBeforeCampaignStart.addr);
        vm.stopPrank();

        // Arrange & Act 1 : donateToCampaign after campaign start but not make campaign meet fund target
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)
        vm.startPrank(BACKER2); // if obmit will take address of this GiveUp129InteractionsTest contract
        bool donateAfterCampaignStart = donateOrVote.donate(giveUp, MAX_RULES, 0, 0, SEND_VALUE / 10);
        nativeTokenDonation = nativeTokenDonation + (SEND_VALUE / 10);
        vm.stopPrank();

        // Assert: Raiser can not propose to change alchemist after campaign start
        vm.startPrank(RAISER1);
        vm.expectRevert("Can not propose Alchemist after campaign start"); // "Raiser can not propose to change alchemist after campaign start, if he want to in this case he has to have his community to help him"
        giveUp.raiserChangeAlchemist(MAX_RULES, ALCHEMIST1);
        (Alchemist memory alchemistAfterCampaignStart,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(alchemistBeforeCampaignStart.addr, alchemistAfterCampaignStart.addr);
        vm.stopPrank();

        // Assert 1a: campaign can be donated after started
        assertEq(donateAfterCampaignStart, true);
        assertEq(getLatestCampaign().cFunded.amtFunded, nativeTokenDonation);
        // uint256 cTotalNativeToken = uint256(vm.getStorageAt(address(giveUp), uint256(uint256(keccak256("contractFundedInfo.cTotalNativeToken")))));
        assertEq(giveUp.getContractFundedInfo().cTotalNativeToken, nativeTokenDonation); // contract accrued above native token donation

        // Assert 1b: vote & donate more with whiteListToken
        vm.startPrank(BACKER1);
        bool voteWLTokenSuccess = donateOrVote.voteWLToken(giveUp, MAX_RULES, 0, 0, ctk);
        vm.startPrank(BACKER1);
        bool donateWLTokenSuccess = donateOrVote.donateWLToken(giveUp, MAX_RULES, 0, 1111, ctk, SEND_TOKEN_AMT);
        ctkTokenDonation = ctkTokenDonation + SEND_TOKEN_AMT;
        vm.stopPrank();

        console.log(
            "1. make some vote, donate native token, whiteListToken, check contract balance = ", address(giveUp).balance
        );
        console.log("voteWLTokenSuccess, donateWLTokenSuccess: ", voteWLTokenSuccess, donateWLTokenSuccess);

        // Arrange & Act 2 : donateToCampaign after campaign start and make campaign meet fund target
        vm.startPrank(RAISER2);
        bool donateAfterCampaignStartWithTargetAmt = donateOrVote.donate(giveUp, MAX_RULES, 0, 0, SEND_VALUE);
        nativeTokenDonation = nativeTokenDonation + SEND_VALUE;
        assertEq(donateAfterCampaignStartWithTargetAmt, true);
        vm.stopPrank();
        CampaignNoBacker memory c = getLatestCampaign();
        assert(c.cFunded.amtFunded >= c.cFunded.target);
        assert(c.cStatus.campaignStatus == campaignStatusEnum.APPROVED);
        assertEq(c.cFunded.amtFunded, nativeTokenDonation);
        assertEq(c.cFunded.firstTokenFunded, ctkTokenDonation);
        ContractFunded memory contractFundedInfo = giveUp.getContractFundedInfo();
        assertEq(contractFundedInfo.cTotalNativeToken, nativeTokenDonation); // contract accrued above native token donation
        assertEq(contractFundedInfo.cTotalFirstToken, ctkTokenDonation); // contract accrued above ctk token donation (ctk is first priority token)
        console.log(
            "2. donate and make sure to trigger campaign 'APPROVED' status: >> ",
            c.cStatus.campaignStatus == campaignStatusEnum.APPROVED
        );

        // Arrange 3: test non raiser, raiser Paidout
        vm.startPrank(RAISER2);
        vm.expectRevert("Invalid Pay Out Right"); // non raiser fail
        paidoutOrDelete.payOutCampaign(giveUp, MAX_RULES);
        vm.stopPrank();
        // Assert 3a: check contract balance before raiser Paidout
        assertEq(address(giveUp).balance, nativeTokenDonation);
        assertEq(ctk.balanceOf(address(giveUp)), ctkTokenDonation);
        // Act 3: raiser Paidout
        vm.startPrank(c.cId.raiser);
        bool raiserPaidout = paidoutOrDelete.payOutCampaign(giveUp, MAX_RULES);
        vm.stopPrank();
        // Assert 3b: check amount raiser, platform receive when campaign tax = 0, haveFundTarget = 100
        assertEq(raiserPaidout, true); // raiser paidout succeed
        assertEq(address(giveUp).balance, 0);
        assertEq(ctk.balanceOf(address(giveUp)), 0);
        assertEq(RAISER1.balance, raiserBalanceBeforePaidout + nativeTokenDonation); // 100110000000000000000 [1.001e20]
        assertEq(ctk.balanceOf(RAISER1), raiserCTK_BalanceBeforePaidout + ctkTokenDonation); // 100
        ContractFunded memory contractFundedInfoAfterPaidout = giveUp.getContractFundedInfo();
        assertEq(contractFundedInfoAfterPaidout.cTotalNativeToken, nativeTokenDonation); // contract did not deduct successfully paidout campaign: OK
        assertEq(contractFundedInfoAfterPaidout.cTotalFirstToken, ctkTokenDonation); // contract did not deduct successfully paidout campaign: OK
        console.log(
            "contractFundedInfoAfterPaidout.cTotalNativeToken ...",
            contractFundedInfoAfterPaidout.cTotalNativeToken,
            contractFundedInfoAfterPaidout.cTotalFirstToken
        );

        // Assert 3c: check TotalFundedCampaign did not deducted because this campaign is successfully paidout
        console.log(
            "getTotalFundedCampaign did not deducted because this campaign is successfully paidout: ",
            contractFundedInfoAfterPaidout.totalFundedCampaign
        );
        assertEq(contractFundedInfoAfterPaidout.totalFundedCampaign, 1);

        // next: ... fine tune with campaign tax, haveFundTarget (check if formular correct)
        // uint256 campaignTax = giveUp.campaignTax();
        // uint256 haveFundTarget = c.cId.haveFundTarget;
    }

    /**
     * expand testPaidOutDelete_100_0 with calculation for platform, alchemist, backers
     * _90_10 mean: (take raised amount = 100 ETH as example)
     * - platform get 10% of raised amount = 10 ETH, remain = 90
     * - backers get 10% of 90% of raised amount = 9 ETH, remain = 81
     * - because haveFundTarget 90% => alchemist get 10%  of remain of raised amount = 8.1 ETH, remain = 72.9
     * - raiser finally get remain of raised amount = 72.9
     * NEXT: if _0_10 (haveFundTarget = 0), how much alchemist will get???
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
        uint256 newCTax = giveUp.changeTax(10);
        vm.stopPrank();
        assertEq(newCTax, 10);

        // Arrange donating:
        DonateOrVote donateOrVote = new DonateOrVote();
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe (after campaign start)
        vm.startPrank(BACKER1); // donate ctk: SEND_TOKEN_AMT for option 0, feedback 1110
        bool donateWLTokenSuccess = donateOrVote.donateWLToken(giveUp, MAX_RULES, 0, 1110, ctk, SEND_TOKEN_AMT);
        vm.stopPrank();
        assertEq(donateWLTokenSuccess, true);
        vm.startPrank(BACKER2); // donate native token: SEND_VALUE / 10 for option 1, feedback 1111
        bool donateAfterCampaignStart = donateOrVote.donate(giveUp, MAX_RULES, 1, 1111, SEND_VALUE / 10);
        vm.stopPrank();
        assertEq(donateAfterCampaignStart, true);
        vm.startPrank(RAISER2); // donate native token: SEND_VALUE for option 1, feedback 1112
        bool donateAfterCampaignStartWithTargetAmt = donateOrVote.donate(giveUp, MAX_RULES, 1, 1112, SEND_VALUE);
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
        // vm.expectRevert();
        bool raiserPaidoutFail = paidoutOrDelete.payOutCampaign(giveUp, c.cId.id);
        vm.stopPrank();
        assertEq(raiserPaidoutFail, true);
        // 0 < haveFundTarge: raiser can not self payout unless set alchemist's address
        console.log("0 < haveFundTarge: raiser can't self payout unless set alchemist's address >> ", raiserPaidoutFail); // └─ ← [Revert] ERC20InvalidSpender(0x0000000000000000000000000000000000000000)
            // giveUp.signAcceptance ?
            // giveUp.transferERC20
            // giveUp.updateAlchemist
    }

    /* ...testing add, remove white list token */
    function testWhiteListTokenInteractions() public {
        // uint256 snapshot = vm.snapshot(); // saves the state https://book.getfoundry.sh/cheatcodes/snapshots

        vm.startPrank(giveUp.contractOwner());
        giveUp.addWhiteListToken(address(rotten), "firstToken");
        assertEq(giveUp.getIsTokenWhitelisted(address(rotten)), true);
        assertEq(giveUp.getTokenAddrToPriority(address(rotten)), "firstToken");
        assertEq(giveUp.getPriorityToTokenAddr("firstToken"), address(rotten));
        assertEq(giveUp.WLAddresses(0), address(rotten));

        vm.expectRevert("Priority is already used"); // because Priority "firstToken" is already used
        giveUp.addWhiteListToken(address(ctk), "firstToken");

        // Arrange & Act: remove address(rotten)
        giveUp.removeWhiteListToken(address(rotten));
        // Assert
        assertEq(giveUp.getIsTokenWhitelisted(address(rotten)), false);
        assertEq(giveUp.getTokenAddrToPriority(address(rotten)), "");
        assertEq(giveUp.getPriorityToTokenAddr("firstToken"), address(0));
        vm.expectRevert(); // "array is empty -> no item at index 0"
        giveUp.WLAddresses(0);

        // Arrange & Act: add address(ctk) again with previous failed priority
        giveUp.addWhiteListToken(address(ctk), "firstToken");
        // Assert
        assertEq(giveUp.getIsTokenWhitelisted(address(ctk)), true);
        assertEq(giveUp.getTokenAddrToPriority(address(ctk)), "firstToken");
        assertEq(giveUp.getPriorityToTokenAddr("firstToken"), address(ctk));
        assertEq(giveUp.WLAddresses(0), address(ctk));
        vm.stopPrank();
        // vm.revertTo(snapshot); // restores the state
    }

    function testDeleteCampaign() public campaign_100_0_Created initWLToken {
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
        console.log("campaignBeforeDelete.cFunded.firstTokenFunded", campaignBeforeDelete.cFunded.firstTokenFunded);
        vm.prank(giveUp.contractOwner());
        bool deleteSuccess = giveUp.deleteCampaign(MAX_RULES);
        CampaignNoBacker memory c = getLatestCampaign();
        assertEq(c.cFunded.paidOut.nativeTokenPaidOut, false); // nativeTokenPaidOut not change to true because this is a failed campaign
        assertEq(c.cFunded.firstTokenFunded, 0); // firstTokenFunded reset to 0 because this is a failed campaign and have to refund backers
        assertEq(c.cFunded.paidOut.firstTokenPaidOut, false); // firstTokenPaidOut false = not paid out yet
        assert(deleteSuccess);
        console.log("getTotalFundedCampaign after", giveUp.getContractFundedInfo().totalFundedCampaign);
        assertEq(giveUp.getContractFundedInfo().totalFundedCampaign, 0);

        // Assert 1d: contract deducted above refund amount.
        assertEq(giveUp.getContractFundedInfo().cTotalFirstToken, 0);
    }

    /**
     * test vote, donate interaction with other information, mainly to check whether vote, donate result are correct
     * e.g: a backers vote, donate for many options, have feedback then withdraw votes, donation etc.
     */
    function testVoteDonateInteraction() public campaign_100_0_Created initWLToken {
        /* Arrange 1: vote & donate. Remember that donate with option also vote for that option. In general:
        - a donation by default is a vote plus a donate => will be recorded in cBacker mapping and have getter function getBackersOfCampaign
        - voter address will be record at cFunded.voterAddr
        */
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
        assertEq(c1.cFunded.voterAddr.length, 1); // assert total backers address (both voter and donator) is 1 (only BACKER1 above)

        C_Backer[] memory backersBeforeWithdraw = giveUp.getBackersOfCampaign(MAX_RULES);
        vm.startPrank(BACKER1);
        assertEq(backersBeforeWithdraw.length, c1.cFunded.totalDonating); // assert total donations is ALWAYS equal totalDonating
        console.log(
            "NOTE: cFunded.totalDonating will save total donating, cFunded.presentDonating only save active donating"
        );
        console.log("cFunded.totalDonating ALWAYS equal backers' length, now it = ", backersBeforeWithdraw.length);

        VoteData[] memory backer1_votes_before_withdraw = util.getVoterOptions(giveUp, MAX_RULES);
        assertEq(backer1_votes_before_withdraw.length, 4); // assert total votes until now is 4
        console.log("backer1_votes_before_withdraw: (will be 4) >> ", backer1_votes_before_withdraw.length);

        // Arrange & Act 2: in testDonateVoteWithdraw_100_0 already test unvote/ undonate with incorrect option, now we'll test unvote/ undonate with correct option
        vm.startPrank(BACKER1);
        string memory withdrawVoteOption_1 = giveUp.requestRefund(MAX_RULES, true, 1); // withdraw vote for option 1
        assertEq(getLatestCampaign().cFunded.voterAddr.length, 1); // "check cFunded.voterAddr.length after 1 withdraw: (1 will be correct)
        console.log("|-> requestRefund - withdrawVoteOption_1: ", withdrawVoteOption_1);
        vm.startPrank(BACKER1);
        string memory withdrawDonateWLTokenOption_4_Feedback_4444 = giveUp.requestRefund(MAX_RULES, true, 4); // withdraw donate for option 4
        assertEq(getLatestCampaign().cFunded.voterAddr.length, 1); // "check cFunded.voterAddr.length after 2 withdraw: (1 will be correct)
        console.log(
            "|-> requestRefund - withdrawDonateWLTokenOption_4_Feedback_4444: ",
            withdrawDonateWLTokenOption_4_Feedback_4444
        );
        vm.stopPrank();
        // Assert 2a: withdraws success
        assertEq(withdrawVoteOption_1, "Remove vote option SUCCESS + Nothing to refund");
        assertEq(withdrawDonateWLTokenOption_4_Feedback_4444, "Proscessed 1 donation(s)");
        // Assert 2b: update campaign info again and make assertion
        C_Backer[] memory backersAfterWithdraws = giveUp.getBackersOfCampaign(MAX_RULES);
        CampaignNoBacker memory c2 = getLatestCampaign();
        assertEq(backersAfterWithdraws.length, c2.cFunded.totalDonating); // assert total donations is ALWAYS equal totalDonating
        assertEq(c2.cFunded.presentDonating, c2.cFunded.totalDonating - 1); // because withdrew 1 donation for option 4 above
        vm.startPrank(BACKER1);
        VoteData[] memory backer1_votes_after_withdraws = util.getVoterOptions(giveUp, MAX_RULES);
        if (backer1_votes_after_withdraws.length > 0) {
            assertEq(backer1_votes_after_withdraws.length, 2);
            console.log("backer1_votes_after_withdraws: (2 will be correct)", backer1_votes_after_withdraws.length); // because withdraw 1 vote, 1 donation in total 4
            assertEq(c2.cFunded.voterAddr.length, 1);
            console.log(
                "if there's vote from backer1 then voterAddr.length = (1 will be correct) ", c2.cFunded.voterAddr.length
            );
        }
        // AAA 3: backer1 continue withdraw all options -> check voterAddr.length, refunded
        vm.startPrank(BACKER1);
        string memory backer1WithdrawAllOptions = giveUp.requestRefund(MAX_RULES, true, 99);
        // instead of withdraw all using code 99 above, can replace by 2 separate withdraws as below code
        // string memory backer1WithdrawAllOptions = giveUp.requestRefund(MAX_RULES, true, 2);
        // vm.startPrank(BACKER1);
        // string memory withdrawOption0 = giveUp.requestRefund(MAX_RULES, true, 0);

        assertEq(backer1WithdrawAllOptions, "Proscessed 1 donation(s)"); // because knowing that only 1 donation left
        CampaignNoBacker memory c3 = getLatestCampaign();
        assertEq(c3.cFunded.voterAddr.length, 0); // no voter/ backer left
        assertEq(c3.cFunded.presentDonating, 0); // no backer left
        C_Backer[] memory backersAfterWithdrawAll = giveUp.getBackersOfCampaign(MAX_RULES);
        assertEq(backersAfterWithdrawAll.length, c2.cFunded.totalDonating); // assert total donations is ALWAYS equal totalDonating
        assertEq(backersAfterWithdrawAll[0].backer, address(BACKER1));
        for (uint256 i = 0; i < backersAfterWithdrawAll.length; i++) {
            // assertEq(backersAfterWithdrawAll[i].refunded, true); // e.g. succeed
            assertEq(backersAfterWithdrawAll[i].fundInfo.refunded, true); // e.g. succeed
        }
        vm.stopPrank();
    }

    /**
     * Test scenario: Non Profit Campaign Interactions Between Raiser, Alchemist, Community and Platform Operator. Focusing on who can finally payout.
     * - Raiser don't want community to propose Alchemist except Raiser himself, he want to propose a fraud Alchemist, in this case he just turn off the option that allow community to change Alchemist -> assert community can not change it after campaign started.
     * - Operator approve the Alchemist proposal.
     * - Community reported some fraud
     * ***** end part 1 test => testNonProfitCampaignPayoutRight_P1() *****
     * ***** start part 2 test => testNonProfitCampaignPayoutRight_P2() *****
     * - Community want to change Alchemist proposal and submit with proofs
     * - Base on rules: (BACKERS COMMUNITY FIRST - BECAUSE THEY'RE THE PAYER) Operator approve community proposal and set campaign to the situation that neither raiser or alchemist can payout (add more logic here) until community set new Alchemist.
     * - Then the community set their prefered Alchemist -> campaign can be paidout and new Alchemist can receive payout.
     * - Besides, operator can set campaign status to SUSPENDING to prevent raiser or alchemist from payout when community report fraud (highest level of report)
     * - Assert the payout (try with raiser and alchemist)
     */
    function testNonProfitCampaignPayoutRight_P1() public campaign_0_90_Created {
        // Assert 1: raiser turn off the option that allow community to change Alchemist
        (Alchemist memory alchemistBefore,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(alchemistBefore.raiserPrivilegeInNoTargetCampaign, false);
        vm.startPrank(RAISER1);
        giveUp.turnOffCommunityProposeAlchemist(MAX_RULES);
        vm.stopPrank();
        (Alchemist memory alchemistAfter,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(alchemistAfter.raiserPrivilegeInNoTargetCampaign, true);
        // Sub assert: raiser set name and symbol for the token that will be created to reward backers in case campaign success
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
        assertEq(getLatestCampaign().cFunded.amtFunded, SEND_VALUE * 2);
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
        assertEq(fraudRateIndexes.fraudPct, fraudRealtimePct); // expect 100% here
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
        assertEq(rateDetailAfterRemove.timestamp > 0, true);
        assertEq(rateDetailAfterRemove.star, 0);
        assertEq(rateDetailAfterRemove.campaignId, MAX_RULES);
        assertEq(rateDetailAfterRemove.ratedObject, "raiser");
        assertEq(rateDetailAfterRemove.content, "backer1 remove his previous fraud report because it's testing");
        // Assert fraudRateIndexes in mappingCId updated correctly
        (,,,, FraudRateIndexes memory fraudRateIndexesAfter,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(fraudRateIndexesAfter.rateId, 0); // no normal rate so far, so next id is 0
        assertEq(fraudRateIndexesAfter.fraudReportId, 3); // there's 3 fraud report from BACKER1 above so far (2 add, 1 remove), so next id (or total fraud report so far) is 3
        assertEq(fraudRateIndexesAfter.fraudPct, 50); // expect 50% here
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
        giveUp.communityProposeAlchemist(MAX_RULES, ALCHEMIST2);
        vm.stopPrank();
        (Alchemist memory alchemistAfterCommunityPropose,,,,,) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);
        assertEq(alchemistAfterCommunityPropose.addr, ALCHEMIST2);
        assertEq(alchemistAfterCommunityPropose.isApproved, true);

        // Assert raiser can't pay out within NON PROFIT campaign (they have to have Alchemist doing that)
        vm.startPrank(RAISER1);
        vm.expectRevert(); // "Invalid Pay Out Right"
        bool raiserPaidoutFailInNonProfitCampaign = giveUp.payOutCampaign(MAX_RULES);
        vm.stopPrank();
        assertEq(raiserPaidoutFailInNonProfitCampaign, false);
        vm.startPrank(ALCHEMIST2);
        bool onlyAlchemistCanPaidoutInNonProfitCampaign = giveUp.payOutCampaign(MAX_RULES);
        assertEq(onlyAlchemistCanPaidoutInNonProfitCampaign, true);
        vm.stopPrank();

        // Sub assert: community set name and symbol for campaign final token failed because it's set
        vm.startPrank(COMMUNITY1);
        vm.expectRevert();
        giveUp.setCampaignFinalTokenNameAndSymbol("CommunityToken", "CTK", MAX_RULES);
        vm.stopPrank();

        // continue testing from notes in testNonProfitCampaignPayoutRight_P1
    }
}
