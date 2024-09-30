// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console, console2} from "forge-std/Test.sol";
import {GiveUp129} from "../../src/GiveUp_129.sol";
import {DeployGiveUp129} from "../../script/DeployGiveUp129.s.sol";
import "../unit/Input_Params.sol";
import "../../src/GlobalVariables_12x.sol";
import {CommunityToken} from "../mock/CTK.sol";
import {RottenToken} from "../mock/ROTTEN.sol";
import {AnyToken} from "../mock/ANY.sol";
import {CreateOrUpdate, DonateOrVote, WithdrawOrRefund, PaidoutOrDelete, Util} from "../../script/Interactions.s.sol";
import {TokenTemplate1} from "../../src/TokenTemplate1.sol";
import {GiveUpLib1} from "../../src/lib/GLib_Base1.sol";
import {TestLib} from "../lib/TestLib.sol";
import {UniswapDeployer} from "../../script/UniswapDeployer.s.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {ContributionNFT} from "../../src/ContributionNFT.sol";

contract InteractionsTest_2 is Test {
    GiveUp129 giveUp;
    CommunityToken ctk;
    RottenToken rotten;
    AnyToken any;
    TokenTemplate1[] tokenTemplate1_List;
    ContributionNFT contributionNFT;

    IUniswapV2Factory factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    WETH deployedWeth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    using TestLib for GiveUp129;

    receive() external payable {}

    function initializeTestParams() internal pure returns (TestParams memory) {
        uint256[] memory haveFundTargets = new uint256[](2);
        haveFundTargets[0] = 90; // normal campaign
        haveFundTargets[1] = 0; // nonprofit campaign

        uint256[] memory pctForBackers = new uint256[](3);
        pctForBackers[0] = 0;
        pctForBackers[1] = 90;
        pctForBackers[2] = 100;

        bool[] memory changeAlchemists = new bool[](1);
        changeAlchemists[0] = true; // in this test we need alchemist because haveFundTarget is not 100
        // changeAlchemists[1] = true;

        return TestParams({
            haveFundTargets: haveFundTargets,
            pctForBackers: pctForBackers,
            changeAlchemists: changeAlchemists
        });
    }

    function setUp() external {
        uint256 platformFee = 0; // 1 -> NOTE LỖI ???; // 0.1 % -> THỬ 1e15 (đã chia), còn chưa chia phải là 1e17 (KHÔNG DÙNG ĐƯỢC VÌ LỖI arithmetic underflow or overflow (0x11) // 0;
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
     * main test
     */
    function testNormalAndNonprofitCampaigns() public {
        TestParams memory params = initializeTestParams();

        console2.log("set feeTo to OWNER");
        vm.prank(factory.feeToSetter());
        factory.setFeeTo(OWNER);

        // change platform fee: such as to 1%, Note: not yet deploy changeTax function below 1% !!!
        vm.prank(giveUp.contractOwner());
        giveUp.changeTax(1);

        runPaidOutDeleteTests(params);
    }

    function runPaidOutDeleteTests(TestParams memory params) private {
        for (uint256 i = 0; i < params.haveFundTargets.length; i++) {
            for (uint256 j = 0; j < params.pctForBackers.length; j++) {
                for (uint256 k = 0; k < params.changeAlchemists.length; k++) {
                    testCampaignScenario(params.haveFundTargets[i], params.pctForBackers[j], params.changeAlchemists[k]);
                }
            }
        }
    }

    function testCampaignScenario(uint256 haveFundTarget, uint256 pctForBackers, bool changeAlchemist) private {
        /**
         * Create campaign
         * - sc/v129/test-result/createCampaign_2_240923.txt
         */
        uint256 campaignId = createCampaign_2(haveFundTarget, pctForBackers, changeAlchemist);

        /**
         * Get some frequently used variables, below are some common used ways
         * // CampaignNoBacker memory c = TestLib.getLatestCampaign(giveUp); // tested ok
         * // CampaignNoBacker memory c = giveUp.getLatestCampaign(); // tested ok
         * // (C_Id memory cId,,,,) = giveUp.campaigns(campaignId); // quickest // console2.log("cId: ", cId.id);
         */
        (Alchemist memory alchemist,,,,,) = giveUp.getRemainMappingCampaignIdTo(campaignId); // console2.log("alchemist: ", alchemist.addr);

        /**
         * Perform donations and votes
         * - sc/v129/test-result/createCampaign_2_240923.txt
         */
        performDonationsAndVotes(campaignId);

        /**
         * Payout campaign
         * We have tested raiser payout in paidOut_1 sc/v129/test/integration/InteractionsTest.t.sol
         * now we'll test alchemist payout or platform owner payout
         */
        if (haveFundTarget != 100) {
            payoutCampaign(campaignId, alchemist.addr);
        } else {
            payoutCampaign(campaignId, giveUp.contractOwner());
        }

        /**
         * Test swap và check phí
         */
        testSwapAndCheckFee(campaignId);

        /**
         * Test removeInitialLiquidity
         * note: expect alchemist payout fail because alchemist is not yet approved.
         */
        testRemoveInitialLiquidity(campaignId);

        // NOTE TODO: test TRADER1 can remove liquidity anytime
    }

    /**
     * allow to create campaign with any haveFundTarget, pctForBackers, changeAlchemist
     * hardcoded for raiser1
     * already handle name and symbol of result token
     */
    function createCampaign_2(uint256 haveFundTarget, uint256 pctForBackers, bool changeAlchemist)
        private
        returns (uint256)
    {
        if (haveFundTarget != 100) {
            changeAlchemist = true;
        } // force to have alchemist
        CreateCampaignInput memory c_input = initializeCreateCampaignData(haveFundTarget, pctForBackers);
        vm.startPrank(RAISER1);
        uint256 returnCId = giveUp.createCampaign(
            c_input.haveFundTarget,
            c_input.content,
            c_input.options,
            c_input.timeline,
            c_input.group,
            c_input.deList,
            c_input.fund,
            c_input.pctForBackers,
            changeAlchemist ? ALCHEMIST1 : payable(address(0))
        );
        assertEq(returnCId, giveUp.nextCId() - 1);

        // Kết hợp các biến thành một chuỗi
        string memory resultTokenName = string(
            abi.encodePacked(
                TestLib.uint2str(returnCId),
                "_",
                TestLib.uint2str(haveFundTarget),
                "_",
                TestLib.uint2str(pctForBackers),
                "_",
                changeAlchemist ? "T" : "F"
            )
        );
        string memory resultTokenSymbol = string(abi.encodePacked("RST_", TestLib.uint2str(returnCId)));

        giveUp.setCampaignFinalTokenNameAndSymbol(resultTokenName, resultTokenSymbol, returnCId);

        vm.stopPrank();
        return returnCId;
    }

    function performDonationsAndVotes(uint256 campaignId) private {
        console2.log("performDonationsAndVotes");
        DonateOrVote donateOrVote = new DonateOrVote();

        vm.warp(block.timestamp + 86400 * 4);

        vm.startPrank(BACKER1);
        donateOrVote.donate(giveUp, campaignId, 0, 0, SEND_VALUE / 2);
        vm.stopPrank();

        vm.startPrank(BACKER2);
        donateOrVote.donate(giveUp, campaignId, 0, 0, SEND_VALUE / 2);
        vm.stopPrank();
    }

    function payoutCampaign(uint256 campaignId, address caller) private {
        console2.log("payoutCampaign: ", campaignId, caller);
        vm.startPrank(caller);
        (TokenTemplate1 resultToken,) = giveUp.payOutCampaign(campaignId);
        tokenTemplate1_List.push(resultToken); // save for later test
        vm.stopPrank();
    }

    function testRemoveInitialLiquidity(uint256 campaignId) private {
        // Lấy địa chỉ của TokenTemplate1 contract
        (,,,,, CampaignToken memory campaignToken) = giveUp.getRemainMappingCampaignIdTo(campaignId);
        TokenTemplate1 resultToken = TokenTemplate1(payable(campaignToken.tokenAddr));
        address pair = resultToken.pair();

        // Test removeInitialLiquidity cho raiser
        vm.startPrank(RAISER1);
        (, uint256 raiserSharePct,,,) = resultToken.raiserShare();
        if (raiserSharePct == 0) {
            vm.expectRevert("No share percentage");
            resultToken.removeInitialLiquidity(RAISER1);
        } else {
            string memory result = testRemoveLiquidity(pair, address(resultToken), RAISER1, "raiser");
            assertEq(
                result,
                "0 LP balance",
                "early participant can not remove liquidity by simply call Uniswap router removeLiquidityETH because their liquidity is held by resultToken contract!"
            );
            (uint256 amountTokenRaiser, uint256 amountETHRaiser) = resultToken.removeInitialLiquidity(RAISER1);
            // Kiểm tra các giá trị trả về
            assert(amountTokenRaiser > 0 && amountETHRaiser > 0);
        }
        vm.stopPrank();

        // Test removeInitialLiquidity cho alchemist (nếu có)
        uint256 amountTokenAlchemist;
        uint256 amountETHAlchemist;
        (address alchemistAddr, uint256 alchemistSharePct,,,) = resultToken.alchemistShare();
        if (alchemistAddr != address(0)) {
            vm.warp(block.timestamp + 31 days); // Đảm bảo đã qua thời gian khóa của alchemist
            vm.startPrank(alchemistAddr);
            if (alchemistSharePct == 0) {
                vm.expectRevert("No share percentage");
                resultToken.removeInitialLiquidity(alchemistAddr);
            } else {
                string memory result = testRemoveLiquidity(pair, address(resultToken), alchemistAddr, "alchemist");
                assertEq(
                    result,
                    "0 LP balance",
                    "early participant can not remove liquidity by simply call Uniswap router removeLiquidityETH because their liquidity is held by resultToken contract!"
                );
                (amountTokenAlchemist, amountETHAlchemist) = resultToken.removeInitialLiquidity(alchemistAddr);
                assert(amountTokenAlchemist > 0 && amountETHAlchemist > 0);
            }
            vm.stopPrank();
        }

        // Test removeInitialLiquidity cho backer
        // TODO: test with BACKER_SAFE_LOCK_PERIOD, check the amount of ETH backer can get back precisely
        vm.startPrank(BACKER1);
        uint256 backerIndex = resultToken.getBackerIndex(BACKER1);
        (, uint256 backerSharePct,,,) = resultToken.backerShare(backerIndex);
        uint256 initialBackerBalance = address(BACKER1).balance;
        console2.log("ETH balance of BACKER1 before removeInitialLiquidity: ", initialBackerBalance);
        if (backerSharePct == 0) {
            vm.expectRevert("No share percentage");
            resultToken.removeInitialLiquidity(BACKER1);
        } else {
            string memory result = testRemoveLiquidity(pair, address(resultToken), BACKER1, "backer");
            assertEq(
                result,
                "0 LP balance",
                "early participant can not remove liquidity by simply call Uniswap router removeLiquidityETH because their liquidity is held by resultToken contract!"
            );
            (uint256 amountTokenBacker, uint256 amountETHBacker) = resultToken.removeInitialLiquidity(BACKER1);
            assert(amountTokenBacker > 0 && amountETHBacker > 0);
        }
        vm.stopPrank();
        console2.log(
            "ETH balance of BACKER1 after removeInitialLiquidity: ",
            address(BACKER1).balance,
            "difference: ",
            address(BACKER1).balance - initialBackerBalance
        );
    }

    function testSwapAndCheckFee(uint256 campaignId) private {
        (,,,,, CampaignToken memory campaignToken) = giveUp.getRemainMappingCampaignIdTo(campaignId);
        TokenTemplate1 resultToken = TokenTemplate1(payable(campaignToken.tokenAddr));
        // assertEq(address(resultToken) != address(0), true, "resultToken should be created");
        address pair = resultToken.pair();

        vm.startPrank(TRADER1); // Phê duyệt cho router từ TRADER1
        resultToken.approve(address(router), type(uint256).max);
        deployedWeth.approve(address(router), type(uint256).max);
        vm.stopPrank();

        uint256 initialOwnerBalance = IERC20(pair).balanceOf(OWNER);

        // test scenario: a trader make some swaps then add liquidity then remove liquidity
        vm.deal(TRADER1, STARTING_USER_BALANCE); // 100 ETH
        vm.startPrank(TRADER1);
        // Thực hiện các swap
        uint256 numSwaps = 2;
        for (uint256 i = 0; i < numSwaps; i++) {
            performSwaps(address(resultToken), pair, i);
        }
        // performSwaps(address(resultToken), pair, numSwaps);
        vm.stopPrank();

        // Kiểm tra phí
        checkFees(pair);

        // Thêm thanh khoản
        vm.startPrank(TRADER1);
        address[] memory path = new address[](2);
        path[0] = address(deployedWeth);
        path[1] = address(resultToken);
        uint256 amountInETH = address(TRADER1).balance / 100;
        swapETHForTokens(path, amountInETH, numSwaps + 1); // get token to add liquidity later
        addMoreLiquidity(address(resultToken), TRADER1);
        vm.stopPrank();

        // hàm test để TRADER1 rút thanh khoản
        testRemoveLiquidity(pair, address(resultToken), TRADER1, "trader");

        uint256 finalOwnerBalance = IERC20(pair).balanceOf(OWNER);
        uint256 feeReceived = finalOwnerBalance - initialOwnerBalance;

        console2.log("Fee received by OWNER:", feeReceived);
        assertGt(feeReceived, 0, "OWNER should have received fees");
    }

    /**
     * for anyone to remove their liquidity. Just return if their liquidity is 0
     */
    function testRemoveLiquidity(address pair, address tokenAddress, address trader, string memory callerType)
        private
        returns (string memory result)
    {
        console2.log("testRemoveLiquidity - ", callerType);

        uint256 initialLPBalance = IERC20(pair).balanceOf(trader);
        if (initialLPBalance == 0) {
            console2.log(callerType, " must have initial LP balance");
            result = "0 LP balance";
            return result;
        }
        uint256 initialETHBalance = trader.balance;
        uint256 initialTokenBalance = IERC20(tokenAddress).balanceOf(trader);

        console2.log(callerType, "'s initial LP balance:", initialLPBalance);
        console2.log(callerType, "'s initial ETH balance:", initialETHBalance);
        console2.log(callerType, "'s initial token balance:", initialTokenBalance);

        vm.startPrank(trader);

        // Phê duyệt cho router sử dụng LP token
        IERC20(pair).approve(address(router), initialLPBalance);

        // Rút toàn bộ thanh khoản
        (uint256 amountToken, uint256 amountETH) =
            router.removeLiquidityETH(tokenAddress, initialLPBalance, 0, 0, trader, block.timestamp);

        vm.stopPrank();

        uint256 finalLPBalance = IERC20(pair).balanceOf(trader);
        uint256 finalETHBalance = trader.balance;
        uint256 finalTokenBalance = IERC20(tokenAddress).balanceOf(trader);

        console2.log(callerType, "'s final LP balance:", finalLPBalance);
        console2.log(callerType, "'s final ETH balance:", finalETHBalance);
        console2.log(callerType, "'s final token balance:", finalTokenBalance);

        // Các assert để kiểm tra
        assertEq(finalLPBalance, 0, "callerType must remove all LP token");
        assertGt(finalETHBalance, initialETHBalance, "callerType's ETH balance must increase after removing liquidity");
        assertGt(
            finalTokenBalance, initialTokenBalance, "callerType's token balance must increase after removing liquidity"
        );
        assertEq(
            amountToken, finalTokenBalance - initialTokenBalance, "callerType's token amount received is not correct"
        );
        assertEq(amountETH, finalETHBalance - initialETHBalance, "callerType's ETH amount received is not correct");

        console2.log("testRemoveLiquidity - ", callerType, " - success");
    }

    function performSwaps(address token, address pair, uint256 counter) private {
        console2.log("performSwaps");
        (uint112 reserve0Before, uint112 reserve1Before,) = IUniswapV2Pair(pair).getReserves();
        console2.log("Reserves before swaps - Token:", reserve0Before, "WETH:", reserve1Before);

        uint256 amountInETH_Temp = (uint256(reserve1Before) * MAX_SWAP_PERCENT) / 100;
        uint256 amountInETH =
            (address(TRADER1).balance > amountInETH_Temp) ? amountInETH_Temp : address(TRADER1).balance;

        address[] memory path = new address[](2);
        path[0] = address(deployedWeth);
        path[1] = token;
        swapETHForTokens(path, amountInETH, counter); // this is 1st swap of the sequence
        path[0] = address(token);
        path[1] = address(deployedWeth);
        uint256 amountInToken_Temp = (uint256(reserve0Before) * MAX_SWAP_PERCENT) / 100;
        uint256 swapperToken_Balance = IERC20(token).balanceOf(TRADER1);
        // console2.log("swapperToken_Balance", swapperToken_Balance);
        uint256 amountInToken = (swapperToken_Balance > amountInToken_Temp) ? amountInToken_Temp : swapperToken_Balance;
        swapTokensForETH(path, amountInToken, counter);
    }

    function swapETHForTokens(address[] memory path, uint256 amountInETH, uint256 counter) private {
        console2.log("swapETHForTokens", counter);

        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(amountInETH, path);
        uint256 amountOutMin = amounts[1] * 99 / 100; // adjust slippage here
        console2.log("amountOutMin", amountOutMin, "amountInETH", amountInETH);

        IUniswapV2Router01(router).swapExactETHForTokens{value: amountInETH}(
            amountOutMin, path, TRADER1, block.timestamp
        ); // NOTE NOTE NOTE
        console2.log("TRADER1 ETH balance after, ", counter, " swap:", address(TRADER1).balance);
        console2.log("TRADER1 token balance after, ", counter, " swap:", IERC20(path[1]).balanceOf(TRADER1));
    }

    function swapTokensForETH(address[] memory path, uint256 amountIn, uint256 counter) private {
        console2.log("swapTokensForETH", counter);

        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(amountIn, path);
        uint256 amountOutMin = amounts[1] * 99 / 100; // 1% slippage

        console2.log("TRADER1 ETH balance before, ", counter, " swap:", address(TRADER1).balance);
        IUniswapV2Router01(router).swapExactTokensForETH(amountIn, amountOutMin, path, TRADER1, block.timestamp); // NOTE NOTE NOTE
        console2.log("RAISER1 ETH balance after, ", counter, " swap:", address(TRADER1).balance); // 90906610893880149131 [9.09e19]
    }

    function checkFees(address pair) private view {
        (uint112 reserve0After, uint112 reserve1After,) = IUniswapV2Pair(pair).getReserves();
        console2.log("Reserves after swaps - Token:", reserve0After, "WETH:", reserve1After);

        address feeTo = factory.feeTo();
        assertEq(feeTo, OWNER, "feeTo should be set to OWNER");
    }

    function addMoreLiquidity(address token, address caller) private {
        console2.log("addMoreLiquidity");

        // get balance of token and weth of caller (TRADER1 in this example)
        uint256 tokenBalance = IERC20(token).balanceOf(caller);
        uint256 wethBalance = address(caller).balance;
        console2.log("tokenBalance", tokenBalance, "wethBalance", wethBalance);

        // require tokenBalance and wethBalance > 0
        require(tokenBalance > 0 && wethBalance > 0, "Balance must be greater than 0");

        // calculate amount of token and weth to add
        uint256 amountToken = tokenBalance * 99 / 100; // 1% slippage
        uint256 amountETH = (wethBalance > STARTING_USER_BALANCE / 100) ? STARTING_USER_BALANCE / 100 : wethBalance;

        // approve token and weth to router via msg.sender
        vm.startPrank(caller);
        IERC20(token).approve(address(router), type(uint256).max);
        deployedWeth.approve(address(router), type(uint256).max);

        // call addLiquidityETH
        IUniswapV2Router01(router).addLiquidityETH{value: amountETH}(token, amountToken, 0, 0, caller, block.timestamp);
        vm.stopPrank();
    }

    /**
     * include testNormalAndNonprofitCampaigns
     * adding test for ContributionNFT
     */
    function testContributionNFT() public {
        // prepare data for testing
        uint256 haveFundTarget = 50;
        uint256 campaignId = createCampaign_2(haveFundTarget, 99, true);
        (Alchemist memory alchemist,,,,,) = giveUp.getRemainMappingCampaignIdTo(campaignId); // console2.log("alchemist: ", alchemist.addr);
        performDonationsAndVotes(campaignId);
        if (haveFundTarget != 100) {
            payoutCampaign(campaignId, alchemist.addr);
        } else {
            payoutCampaign(campaignId, giveUp.contractOwner());
        }

        // // use the last created tokenTemplate1
        // TokenTemplate1 tokenTemplate1 = tokenTemplate1_List[tokenTemplate1_List.length - 1];
        (,,,,, CampaignToken memory campaignToken) = giveUp.getRemainMappingCampaignIdTo(campaignId);
        TokenTemplate1 tokenTemplate1 = TokenTemplate1(payable(campaignToken.tokenAddr));

        // Triển khai ContributionNFT
        contributionNFT = new ContributionNFT(address(tokenTemplate1));

        // Link ContributionNFT với TokenTemplate1
        vm.startPrank(tokenTemplate1.i_contractOwner());
        tokenTemplate1.setContributionNFTAddress(address(contributionNFT));
        vm.stopPrank();

        // // Kiểm tra tên và ký hiệu
        // assertEq(contributionNFT.name(), "Test Token_NFT", "Incorrect NFT name");
        // assertEq(contributionNFT.symbol(), "TT_NFT", "Incorrect NFT symbol");
        console2.log("name of contributionNFT: ", contributionNFT.name());
        console2.log("symbol of contributionNFT: ", contributionNFT.symbol());

        // Kiểm tra mint NFT
        // address testUser = address(0x123);
        vm.startPrank(ALCHEMIST1);
        // uint256 tokenId = contributionNFT.mintNFT(testUser, 100, "Backer");
        uint256 tokenId = tokenTemplate1.claimNFT(ALCHEMIST1);
        vm.stopPrank();
        // Kiểm tra thông tin NFT
        (address participant, uint256 amount, uint256 timestamp, string memory participantType) =
            contributionNFT.getContributionInfo(tokenId);
        assertEq(participant, ALCHEMIST1, "Incorrect participant");
        assertEq(amount, 1, "Incorrect amount");
        if (participant == ALCHEMIST1) {
            assertEq(participantType, "Alchemist", "Incorrect participant type");
        } else if (participant == RAISER1) {
            assertEq(participantType, "Raiser", "Incorrect participant type");
        } else if (participant == BACKER1) {
            assertEq(participantType, "Backer", "Incorrect participant type");
        }

        // Kiểm tra tokenURI
        string memory tokenURI = contributionNFT.tokenURI(tokenId);
        assertTrue(bytes(tokenURI).length > 0, "TokenURI should not be empty");

        console.log("ContributionNFT test passed successfully", timestamp);
    }
}
