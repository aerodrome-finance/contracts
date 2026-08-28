// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";
import {MockERC20WithTransferFee} from "utils/MockERC20WithTransferFee.sol";

contract RouterTest is BaseTest {
    Pool _pool;
    Pool poolFee;
    MockERC20WithTransferFee erc20Fee;

    function _setUp() public override {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        amounts[3] = 1e25;
        amounts[4] = 1e25;
        mintToken(address(WETH), owners, amounts);
        dealETH(owners, amounts);

        _addLiquidityToPool(address(owner), address(router), address(WETH), address(USDC), false, TOKEN_1, USDC_1);
        _pool = Pool(factory.getPool(address(USDC), address(WETH), false));

        erc20Fee = new MockERC20WithTransferFee("Mock Token", "FEE", 18);
        erc20Fee.mint(address(owner), TOKEN_100K);

        _seedPoolsWithLiquidity();
    }

    function _seedPoolsWithLiquidity() internal {
        USDC.approve(address(router), USDC_100K);
        router.addLiquidityETH{value: TOKEN_100K}(
            address(USDC),
            false,
            USDC_100K,
            USDC_100K,
            TOKEN_100K,
            address(owner),
            block.timestamp
        );
        vm.startPrank(address(owner2));
        USDC.approve(address(router), USDC_100K);
        router.addLiquidityETH{value: TOKEN_100K}(
            address(USDC),
            false,
            USDC_100K,
            USDC_100K,
            TOKEN_100K,
            address(owner),
            block.timestamp
        );
        vm.stopPrank();

        // create pool for transfer fee token
        erc20Fee.approve(address(router), TOKEN_100K);
        router.addLiquidityETH{value: TOKEN_100K}(
            address(erc20Fee),
            false,
            TOKEN_100K,
            TOKEN_100K,
            TOKEN_100K,
            address(owner),
            block.timestamp
        );
        poolFee = Pool(factory.getPool(address(erc20Fee), address(WETH), false));
    }

    function testCannotSortTokensSameRoute() public {
        vm.expectRevert(IRouter.SameAddresses.selector);
        router.sortTokens(address(_pool), address(_pool));
    }

    function testCannotSortTokensZeroAddress() public {
        vm.expectRevert(IRouter.ZeroAddress.selector);
        router.sortTokens(address(_pool), address(0));
    }

    function testCannotSwapNonApprovedFactory() public {
        vm.expectRevert(IRouter.PoolFactoryDoesNotExist.selector);
        router.poolFor(address(USDC), address(WETH), false, address(1));
    }

    function testCannotSendETHToRouter() public {
        vm.expectRevert(IRouter.OnlyWETH.selector);
        payable(address(router)).transfer(TOKEN_1);
    }

    function testRemoveETHLiquidity() public {
        uint256 initialEth = address(this).balance;
        uint256 initialUsdc = USDC.balanceOf(address(this));
        uint256 poolInitialEth = address(_pool).balance;
        uint256 poolInitialUsdc = USDC.balanceOf(address(_pool));

        // add liquidity to pool
        USDC.approve(address(router), USDC_100K);
        WETH.approve(address(router), TOKEN_100K);
        (, , uint256 liquidity) = router.addLiquidityETH{value: TOKEN_100K}(
            address(USDC),
            false,
            USDC_100K,
            USDC_100K,
            TOKEN_100K,
            address(owner),
            block.timestamp
        );

        assertEq(address(this).balance, initialEth - TOKEN_100K);
        assertEq(USDC.balanceOf(address(this)), initialUsdc - USDC_100K);

        (uint256 amountUSDC, uint256 amountETH) = router.quoteRemoveLiquidity(
            address(USDC),
            address(WETH),
            false,
            address(factory),
            liquidity
        );

        Pool(_pool).approve(address(router), liquidity);
        router.removeLiquidityETH(
            address(USDC),
            false,
            liquidity,
            amountUSDC,
            amountETH,
            address(owner),
            block.timestamp
        );

        assertEq(address(this).balance, initialEth);
        assertEq(USDC.balanceOf(address(this)), initialUsdc);
        assertEq(address(_pool).balance, poolInitialEth);
        assertEq(USDC.balanceOf(address(_pool)), poolInitialUsdc);
    }

    function testRouterPoolGetAmountsOutAndSwapExactTokensForETH() public {
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(WETH), false, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], _pool.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForETH(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function testRouterPoolGetAmountsOutAndSwapExactETHForTokens() public {
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(WETH), address(USDC), false, address(0));

        assertEq(router.getAmountsOut(TOKEN_1, routes)[1], _pool.getAmountOut(TOKEN_1, address(WETH)));

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, routes);
        USDC.approve(address(router), TOKEN_1);
        router.swapExactETHForTokens{value: TOKEN_1}(expectedOutput[1], routes, address(owner), block.timestamp);
    }

    // TESTS FOR FEE-ON-TRANSFER TOKENS

    function testRouterRemoveLiquidityETHSupportingFeeOnTransferTokens() public {
        uint256 liquidity = poolFee.balanceOf(address(owner));

        uint256 currentBalance = erc20Fee.balanceOf(address(poolFee));
        uint256 expectedBalanceAfterRemove = currentBalance - (erc20Fee.fee() * 2);
        // subtract 1,000 as even though we're removing all liquidity, MINIMUM_LIQUIDITY amount remains in pool
        expectedBalanceAfterRemove -= 1000;

        poolFee.approve(address(router), type(uint256).max);
        router.removeLiquidityETHSupportingFeeOnTransferTokens(
            address(erc20Fee),
            false,
            liquidity,
            0,
            0,
            address(owner),
            block.timestamp
        );

        assertEq(erc20Fee.balanceOf(address(owner)), expectedBalanceAfterRemove);
    }

    function testRouterSwapExactETHForTokensSupportingFeeOnTransferTokens() external {
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(WETH), address(erc20Fee), false, address(0));

        uint256 expectedOutput = router.getAmountsOut(TOKEN_1, routes)[1];
        assertEq(poolFee.getAmountOut(TOKEN_1, address(WETH)), expectedOutput);

        assertEq(erc20Fee.balanceOf(address(owner)), 0);
        uint256 actualExpectedOutput = expectedOutput - erc20Fee.fee();

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: TOKEN_1}(
            0,
            routes,
            address(owner),
            block.timestamp
        );

        assertEq(erc20Fee.balanceOf(address(owner)), actualExpectedOutput);
    }

    function testRouterSwapExactTokensForETHSupportingFeeOnTransferTokens() external {
        // first add the token balance to user to swap
        erc20Fee.mint(address(owner), TOKEN_1);

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(erc20Fee), address(WETH), false, address(0));

        uint256 expectedOutput = router.getAmountsOut(TOKEN_1, routes)[1];
        assertEq(poolFee.getAmountOut(TOKEN_1, address(erc20Fee)), expectedOutput);

        uint256 ethBalanceBefore = address(owner).balance;
        uint256 actualExpectedOutput = router.getAmountsOut(TOKEN_1 - erc20Fee.fee(), routes)[1];

        erc20Fee.approve(address(router), TOKEN_1);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(TOKEN_1, 0, routes, address(owner), block.timestamp);

        assertEq(address(owner).balance - ethBalanceBefore, actualExpectedOutput);
    }
}
