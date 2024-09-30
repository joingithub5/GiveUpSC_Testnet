// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.5;

import {Test, console2} from "forge-std/Test.sol";
import {UniswapDeployer} from "../../script/UniswapDeployer.s.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";

import {AnyToken} from "../mock/ANY.sol";
import "./Input_Params.sol";

import {Token} from "../mock/TokenTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapTests is Test {
    IUniswapV2Factory factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    WETH deployedWeth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() public {
        UniswapDeployer deployer = new UniswapDeployer();
        deployer.run();
    }

    function test_uniswapFactory() public view {
        assert(factory.feeToSetter() != address(0));
        assertEq(factory.feeToSetter(), OWNER);
    }

    function test_wrappedEther() public view {
        assert(abi.encode(deployedWeth.name()).length > 0);
    }

    function test_deployedRouter() public view {
        assert(router.WETH() != address(0));
    }

    function addLiqTokenWETH() internal returns (AnyToken, address) {
        // reference code: https://github.com/aurelien-cuvelier/local-uniswapv2-foundry/blob/master/test/UniswapDeployer.t.sol
        // Credit to this guide: https://www.youtube.com/watch?v=izz4xYKNZQM&list=WL&index=32&t=7s

        vm.deal(RAISER1, STARTING_USER_BALANCE); // 100 ETH
        vm.startPrank(RAISER1);
        AnyToken token = new AnyToken(msg.sender);
        uint256 tokenAmount = STARTING_USER_BALANCE * 10; // 10**3; // 10 (default ~ 1000 token); // 10**9; // change from * 10 to * 10**9 to test token with more decimals  // 1000 token
        uint256 ethAmount = STARTING_USER_BALANCE / 100; // now (default ~ 1 ETH); // 10 for previous comment test;
        console2.log("mint 2000 token to RAISER1", tokenAmount * 2);
        token.mint(RAISER1, tokenAmount * 2); // mint to msg.sender will make this test fail
        token.approve(address(router), type(uint256).max);
        deployedWeth.approve(address(router), type(uint256).max);
        /**
         * Note: have to update /lib/v2-periphery/contracts/libraries/UniswapV2Library.sol -> function pairFor for new init code hash
         * /out/UniswapV2Pair.sol/UniswapV2Pair.json -> bytecode content -> e.g https://emn178.github.io/online-tools/keccak_256.html -> select hex input (obmit 0x at beginning) -> get init code hash to paste back to UniswapV2Library.sol -> pairFor function
         * https://www.youtube.com/watch?v=izz4xYKNZQM&t=1386s
         * If this test faile, it'll effect others test (I don't know other way to fix it atm)
         */
        (,, uint256 liquidity) = IUniswapV2Router01(router).addLiquidityETH{value: ethAmount}(
            address(token),
            tokenAmount, // token.balanceOf(address(this)),
            tokenAmount, // * 95 / 100, // 5% slippage
            ethAmount, // * 95 / 100, // 5% slippage
            RAISER1, // msg.sender will fail
            block.timestamp + 1000
        );

        address pair = factory.getPair(address(token), address(deployedWeth));
        console2.log("pair", pair, "RAISER1 balance of pair: ", IERC20(pair).balanceOf(RAISER1));
        // Assert: RAISER1 finally got the liquidity token
        assertEq(liquidity, IERC20(pair).balanceOf(RAISER1)); //99999999999999999000 [9.999e19] , not 1e20 because of 0.001% fee!
        return (token, pair);
    }

    function performSwaps(AnyToken token, address pair, uint256 counter) internal {
        console2.log("performSwaps");
        (uint112 reserve0Before, uint112 reserve1Before,) = IUniswapV2Pair(pair).getReserves();
        console2.log("Reserves before swaps - Token:", reserve0Before, "WETH:", reserve1Before);

        uint256 amountInCanBeChangedForTest = STARTING_USER_BALANCE * 10; // STARTING_USER_BALANCE * 10**8; // STARTING_USER_BALANCE * 10 //  100 token

        /**
         * Make some adjustment to limit the amount of token to swap
         * can lead to statistic comment will not be accurate
         * statistic comment is for scenario where STARTING_USER_BALANCE = 100;
         * amountIn = STARTING_USER_BALANCE * 10
         * tokenAmount = STARTING_USER_BALANCE * 10 ~ 1000 token
         * ethAmount = STARTING_USER_BALANCE / 10 ~ 10 ETH
         */
        uint256 maxSwapAmount = (uint256(reserve0Before) * MAX_SWAP_PERCENT) / 100;
        uint256 amountIn = amountInCanBeChangedForTest > maxSwapAmount ? maxSwapAmount : amountInCanBeChangedForTest; // Math.min(amountInTemp, maxSwapAmount);

        uint256 amountInETH = STARTING_USER_BALANCE / 100; // 1 ETH

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(deployedWeth);

        // Swap token to ETH
        swapTokensForETH(path, amountIn, counter);

        // Swap ETH to token
        path[0] = address(deployedWeth);
        path[1] = address(token);
        swapETHForTokens(path, amountInETH, counter);
    }

    function swapTokensForETH(address[] memory path, uint256 amountIn, uint256 counter) internal {
        console2.log("swapTokensForETH");
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(amountIn, path); // ← [Return] 1000000000000000000000 [1e21], 10000000000000000000 [1e19], 1
        uint256 amountOutMin = amounts[1] * 99 / 100; // 1% slippage

        console2.log("RAISER1 ETH balance before, ", counter, " swap:", address(RAISER1).balance);
        IUniswapV2Router01(router).swapExactTokensForETH(amountIn, amountOutMin, path, RAISER1, block.timestamp); // ← [Return] [100000000000000000000 [1e20], 906610893880149131 [9.066e17]]
        console2.log("RAISER1 ETH balance after, ", counter, " swap:", address(RAISER1).balance); // 90906610893880149131 [9.09e19]
    }

    function swapETHForTokens(address[] memory path, uint256 amountInETH, uint256 counter) internal {
        console2.log("swapETHForTokens");
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(amountInETH, path); // ← [Return] [1000000000000000000 [1e18], 108687582655742007296 [1.086e20]]
        uint256 amountOutMin = amounts[1] * 99 / 100; // 1% slippage

        console2.log("amountOutMin", amountOutMin, "amountInETH", amountInETH);
        IUniswapV2Router01(router).swapExactETHForTokens{value: amountInETH}(
            amountOutMin, path, RAISER1, block.timestamp
        ); // ← [Return] [1000000000000000000 [1e18], 108687582655742007296 [1.086e20]]
        console2.log("RAISER1 ETH balance after, ", counter, " swap:", address(RAISER1).balance); // 89906610893880149131 [8.99e19] ~ 89.9 ETH
        console2.log("RAISER1 token balance after, ", counter, " swap:", IERC20(path[1]).balanceOf(RAISER1)); // 1008687582655742007296 [1.008e21] ~ 1008 token
    }

    function checkFees(address pair) internal view {
        console2.log("checkFees");
        (uint112 reserve0After, uint112 reserve1After,) = IUniswapV2Pair(pair).getReserves(); // ← [Return] 991312417344257992704 [9.913e20], 10093389106119850869 [1.009e19]
        console2.log("Reserves after swaps - Token:", reserve0After, "WETH:", reserve1After);

        address feeTo = factory.feeTo();
        assertEq(feeTo, OWNER, "feeTo should be set to OWNER");
    }

    function addMoreLiquidity(AnyToken token) internal {
        console2.log("addMoreLiquidity");
        IUniswapV2Router01(router).addLiquidityETH{value: STARTING_USER_BALANCE / 100}(
            address(token), 100 * 10 ** 18, 0, 0, RAISER1, block.timestamp
        );
    }

    function test_swapAndCheckFee() public {
        console2.log("set feeTo to OWNER");
        vm.prank(factory.feeToSetter());
        factory.setFeeTo(OWNER);

        (AnyToken token, address pair) = addLiqTokenWETH();
        uint256 initialOwnerBalance = IERC20(pair).balanceOf(OWNER);

        performSwaps(token, pair, 1); // replaced by below code

        uint256 numSwaps = 229; // Thực hiện 1+229=230 cặp swap (token->ETH và ETH->token)
        for (uint256 i = 2; i < numSwaps + 2; i++) {
            performSwaps(token, pair, i);
        }

        checkFees(pair);

        addMoreLiquidity(token);

        uint256 finalOwnerBalance = IERC20(pair).balanceOf(OWNER);
        uint256 feeReceived = finalOwnerBalance - initialOwnerBalance;

        console2.log("Fee received by OWNER:", feeReceived); // 1 performSwaps ~ 4749822864953164 [4.749e15]; 230 performSwaps ~ 1043140438230532235 [1.043e18] <-> 1.043 ETH
        assertGt(feeReceived, 0, "OWNER should have received fees");

        vm.stopPrank();
    }
}
