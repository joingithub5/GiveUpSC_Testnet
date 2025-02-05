//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {GiveUp129} from "../../src/GiveUp_129.sol";
import {DeployGiveUp129} from "../../script/DeployGiveUp129.s.sol";
import "./Input_Params.sol";
import "../../src/GlobalVariables_12x.sol";
import {CommunityToken} from "../mock/CTK.sol";
import {RottenToken} from "../mock/ROTTEN.sol";
import {AnyToken} from "../mock/ANY.sol";
import {TokenTemplate1} from "../../src/TokenTemplate1.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {GiveUpDeployer} from "../../src/GiveUpDeployer.sol"; // update to UUPS proxy

contract GiveUp129UnitTest is Test {
    GiveUp129 giveUp;
    CommunityToken ctk;
    RottenToken rotten;
    AnyToken any;
    // TokenTemplate1 tokenTemplate1;
    GiveUpDeployer public deployer; // update to UUPS proxy
    address public proxyAddress; // update to UUPS proxy

    function setUp() external {
        uint256 platformFee = 0; // if pass these params from outside will cost gas
        string memory nativeTokenSymbol = "ETH";

        // Sử dụng DeployGiveUp129 để triển khai các hợp đồng
        DeployGiveUp129 deployGiveUp129 = new DeployGiveUp129(); // update to UUPS proxy
        // (giveUp, ctk, rotten, any) = deployGiveUp129.run(platformFee, nativeTokenSymbol); // update to UUPS proxy
        (giveUp, ctk, rotten, any, deployer, proxyAddress) = deployGiveUp129.run(platformFee, nativeTokenSymbol); // update to UUPS proxy

        // deployer = new GiveUpDeployer(); // update to UUPS proxy
        // bytes32 salt = keccak256("test_salt"); // update to UUPS proxy
        // GiveUp129 implementation = new GiveUp129(); // update to UUPS proxy
        // proxyAddress = deployer.getGiveUp129Address(salt, address(implementation), platformFee, nativeTokenSymbol); // update to UUPS proxy

        // DeployGiveUp129 deployGiveUp129 = new DeployGiveUp129(); // replaced after update to UUPS proxy
        // (giveUp, ctk, rotten, any) = deployGiveUp129.run(platformFee, nativeTokenSymbol); // replaced after update to UUPS proxy

        vm.deal(RAISER1, STARTING_USER_BALANCE);
        vm.deal(RAISER2, STARTING_USER_BALANCE);
        vm.deal(BACKER1, STARTING_USER_BALANCE);
        vm.deal(BACKER2, STARTING_USER_BALANCE);
        console.log(
            "address of giveUp, address of this GiveUp129Test, msg.sender: ", address(giveUp), address(this), msg.sender
        );
    }

    function testPresentCIdAndRuleId() public view {
        console.log("at initial, MAX_RULES: ", MAX_RULES, " must equal next campaign id: ", giveUp.nextCId());
        assertEq(giveUp.nextCId(), MAX_RULES);
        assertEq(giveUp.ruleId(), 0);
    }

    // function testOwnerIsMessageSender() public view {
    //     console.log("contractOwner is msg.sender who deploy the contract");
    //     // assertEq(giveUp.contractOwner(), msg.sender);
    //     assertEq(giveUp.contractOwner(), OWNER);
    // }

    function testOwnerIsMessageSender() public {
        assertEq(giveUp.contractOwner(), OWNER);
        console.log(
            "contractOwner is msg.sender who deploy the contract which was specified by function transferOwnership ... deployGiveUp129 in GiveUpDeployer.sol"
        );
        vm.prank(OWNER);
        address ownerView = giveUp.contractOwner();
        assertEq(ownerView, OWNER, "Owner view of contractOwner should be OWNER");

        vm.prank(address(0x1234));
        address nonOwnerView = giveUp.contractOwner();
        assertEq(nonOwnerView, OWNER, "Non-owner view of contractOwner should still be OWNER");

        console.log("don't use msg.sender because it'll be default to Foundry address");
    }

    function testOutsideCantSendNativeTokenDirectlyToContract() public campaign_100_0_Created {
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe to donate when campaign start
        donateToCampaign(SEND_VALUE * 2, MAX_RULES, 0, 0);
        vm.expectRevert("can not directly send native token to contract, must send via donateToCampaign function ...");
        vm.startPrank(RAISER1);
        (bool success,) = address(giveUp).call{value: SEND_VALUE}("");
        address payable giveUpPayable = payable(address(giveUp));
        vm.expectRevert();
        giveUpPayable.transfer(SEND_VALUE);
        vm.stopPrank();
        console.log(success, " contract balance = ", address(giveUp).balance);
    }

    /**
     * donation campaign type, no Alchemist
     */
    modifier campaign_100_0_Created() {
        vm.prank(RAISER1); // create a normal campaign via RAISER1, not via address(this)
        CreateCampaignInput memory c_input = initializeCampaignData_100_0();
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

    /**
     * Non Profit Campaign Type + Alchemist
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
        CampaignNoBacker memory campaign = campaignsNoBacker[(giveUp.nextCId() - 1) - MAX_RULES]; // cause getCampaigns() compressed and reindexed
        return campaign;
    }

    /**
     * Note: this function usually used in this test file, not widely used
     */
    function donateToCampaign(uint256 _amount, uint256 _campaignId, uint256 _option, uint256 _feedback)
        public
        returns (bool)
    {
        bool result = giveUp.donateToCampaign{value: _amount}(_campaignId, _option, _feedback);
        return result;
    }

    /* test createCampaign 
    forge test --match-test testCreateCampaign
    */
    function testCreateCampaign() public campaign_100_0_Created {
        console.log("anyone can create new campaign -> need 8 variables ...");
        console.log("msg.sender is ...: ", msg.sender);
        address raiser = getLatestCampaign().cId.raiser;
        console.log("campaign's raiser is ...: ", raiser, "equal to RAISER1: ", RAISER1);
        assertEq(raiser, RAISER1);
        // next: check ruler's campaigns informations: w/ ruler's address, etc.
    }

    /* test donateToCampaign: _0_90 is campaign type that has 0% fund for raiser (like Non Profit campaign), 90% for backers
    1st donation make campaign meet target, 2nd donation then still be accepted because raiser don't want to get the fund instead giving them to backers, alchemist. This type of campaign allow amount funded greater than target.
    forge test --match-test testDonateToCampaign_0_90 -vvvv
    */
    function testDonateToCampaign_0_90() public campaign_0_90_Created {
        // Arrange
        (
            Alchemist memory alchemist,
            Community memory community,
            MultiPayment memory multiPayment,
            string[] memory content,
            ,
        ) = giveUp.getRemainMappingCampaignIdTo(MAX_RULES);

        // Act
        vm.warp(block.timestamp + 86400 * 4); // set proper timeframe to donate when campaign start
        bool donationMakeCampaignMeetTarget = donateToCampaign(SEND_VALUE * 2, MAX_RULES, 0, 0);
        console.log(
            "donationMakeCampaignMeetTarget: ",
            donationMakeCampaignMeetTarget,
            " check contract balance = ",
            address(giveUp).balance
        );
        bool continueDonating = donateToCampaign(SEND_VALUE, MAX_RULES, 0, 0);
        console.log("continueDonating: ", continueDonating, " check contract balance = ", address(giveUp).balance);
        // Assert
        CampaignNoBacker memory thisCampaign = getLatestCampaign();
        uint256 amtFunded = thisCampaign.cFunded.raisedFund.amtFunded;
        assertEq(amtFunded, address(giveUp).balance);
        assertEq(alchemist.addr, ALCHEMIST1);
        assertEq(alchemist.isApproved, false);
        assertEq(community.presentAddr, address(0));
        assertEq(alchemist.raiserPrivilegeInNoTargetCampaign, false);
        assertEq(multiPayment.planBatch, 0);
        assertEq(content.length, 0);
    }

    function testChangeTax() public {
        uint256 campaignTax_before = giveUp.campaignTax();
        uint256 new_campaignTax = campaignTax_before + 10;
        vm.startPrank(giveUp.contractOwner());
        giveUp.changeTax(new_campaignTax);
        uint256 campaignTax_after = giveUp.campaignTax();
        assertEq(campaignTax_after, new_campaignTax);
        vm.stopPrank();
    }

    // function testChangeNativeToken() public {
    //     string memory new_nativeToken = "TEST";
    //     vm.startPrank(giveUp.contractOwner());
    //     giveUp.changeNativeTokenSymbol(new_nativeToken);
    //     string memory nativeToken_after = giveUp.nativeTokenSymbol();
    //     assertEq(nativeToken_after, new_nativeToken);
    //     vm.stopPrank();
    // }

    function testDelayBlockNumberToPreventFrontRun() public {
        uint256 oldNumber = giveUp.delayBlockNumberToPreventFrontRun();
        vm.startPrank(giveUp.contractOwner());
        giveUp.changeDelayBlockNumberToPreventFrontRun(oldNumber + 1);
        uint256 newNumber = giveUp.delayBlockNumberToPreventFrontRun();
        assertEq(newNumber, oldNumber + 1);
        vm.stopPrank();
    }

    function testRulerAddr() public {
        address rulerAddrBefore = giveUp.rulerAddr();
        console.log("rulerAddrBefore: ", rulerAddrBefore);
        vm.expectRevert("You're not Authorized");
        giveUp.changeRulerAddr(RAISER1);
        vm.startPrank(giveUp.contractOwner());
        giveUp.changeRulerAddr(RAISER1);
        address rulerAddrAfter = giveUp.rulerAddr();
        assertEq(rulerAddrAfter, RAISER1);
        vm.startPrank(RAISER1);
        giveUp.changeRulerAddr(RAISER2);
        assertEq(giveUp.rulerAddr(), RAISER2);
        vm.stopPrank();
    }

    function testPenaltyContract() public {
        address penaltyContractBefore = giveUp.penaltyContract();
        console.log("penaltyContractBefore: ", penaltyContractBefore);
        vm.expectRevert("You're not Contract Owner");
        giveUp.changePenaltyContract(payable(RAISER1));
        vm.startPrank(giveUp.contractOwner());
        giveUp.changePenaltyContract(payable(RAISER1));
        address penaltyContractAfter = giveUp.penaltyContract();
        assertEq(penaltyContractAfter, RAISER1);
        vm.stopPrank();
    }

    function testGetCIdFromAddressAndIndex() public campaign_100_0_Created {
        vm.startPrank(RAISER1);
        assertEq(giveUp.getCIdFromAddressAndIndex(RAISER1, 0), MAX_RULES);
        assertEq(giveUp.getNextCampaignCounterOfAddress(RAISER1), 1);
        vm.stopPrank();
    }

    function testGetRateDetail() public campaign_100_0_Created {
        // when campaign is created, get rateDetail With 0 Index will return the default value of RateDetail
        RateDetail memory rateDetail = giveUp.getRateDetail(MAX_RULES, 0);
        assertEq(rateDetail.rater, address(0));
        assertEq(rateDetail.timestamp, 0);
        assertEq(rateDetail.star, 0);
        assertEq(rateDetail.campaignId, 0);
        assertEq(rateDetail.ratedObject, "");
        assertEq(rateDetail.content, "");
        // get rateDetail With Any Index will also return the same default value of RateDetail
        RateDetail memory rateDetailWithAnyIndex = giveUp.getRateDetail(MAX_RULES, 1);
        assertEq(rateDetailWithAnyIndex.rater, address(0));
        assertEq(rateDetailWithAnyIndex.timestamp, 0);
        assertEq(rateDetailWithAnyIndex.star, 0);
        assertEq(rateDetailWithAnyIndex.campaignId, 0);
        assertEq(rateDetailWithAnyIndex.ratedObject, "");
        assertEq(rateDetailWithAnyIndex.content, "");
    }

    /**
     * similar to testGetRateDetail above
     */
    function testGetRateDetailOfFraudReport() public campaign_100_0_Created {
        // when campaign is created, get rateDetail With 0 Index will return the default value of RateDetail
        RateDetail memory rateDetail = giveUp.getRateDetailOfFraudReport(MAX_RULES, 0);
        assertEq(rateDetail.rater, address(0));
        assertEq(rateDetail.timestamp, 0);
        assertEq(rateDetail.star, 0);
        assertEq(rateDetail.campaignId, 0);
        assertEq(rateDetail.ratedObject, "");
        assertEq(rateDetail.content, "");
        // get rateDetail With Any Index will also return the same default value of RateDetail
        RateDetail memory rateDetailWithAnyIndex = giveUp.getRateDetailOfFraudReport(MAX_RULES, 1);
        assertEq(rateDetailWithAnyIndex.rater, address(0));
        assertEq(rateDetailWithAnyIndex.timestamp, 0);
        assertEq(rateDetailWithAnyIndex.star, 0);
        assertEq(rateDetailWithAnyIndex.campaignId, 0);
        assertEq(rateDetailWithAnyIndex.ratedObject, "");
        assertEq(rateDetailWithAnyIndex.content, "");
    }

    /**
     * test getBackerFraudReport at initial stage will return default value of FraudReport
     * assert at least isFraudNow must be false
     */
    function testGetBackerFraudReport() public campaign_100_0_Created {
        FraudReport memory fraudReport = giveUp.getBackerFraudReport(MAX_RULES, BACKER1);
        assertEq(fraudReport.isFraudNow, false);
        assertEq(fraudReport.reportId, 0);
        assertEq(fraudReport.reportIDHistory.length, 0);
    }

    // // TODO:
    // // Unit test for swapWLTokenToNativeToken
    // function testSwapWLTokenToNativeToken(address _tokenAddr, uint256 _amount) public {
    //     uint256 initialNativeTokenBalance = address(this).balance;
    //     uint256 initialTokenBalance = IERC20(_tokenAddr).balanceOf(address(this));

    //     uint256 ethReceived = swapWLTokenToNativeToken(_tokenAddr, _amount);

    //     assertGt(ethReceived, 0, "No ETH received from swap");
    //     assertEq(address(this).balance, initialNativeTokenBalance + ethReceived, "Incorrect ETH balance after swap");
    //     assertEq(
    //         IERC20(_tokenAddr).balanceOf(address(this)),
    //         initialTokenBalance - _amount,
    //         "Incorrect token balance after swap"
    //     );
    // }
}
