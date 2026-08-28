// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract PoolFeesTest is BaseTest {
    function _setUp() public override {
        factory.setFee(true, 2); // 2 bps = 0.02%
    }

    function testSwapAndClaimFees() public {
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pool.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, assertedOutput[1], routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        address poolFees = pool.poolFees();
        assertEq(USDC.balanceOf(poolFees), 200); // 0.01% -> 0.02%
        uint256 b = USDC.balanceOf(address(owner));
        pool.claimFees();
        assertGt(USDC.balanceOf(address(owner)), b);
    }

    function testFeeManagerCanChangeFeesAndClaim() public {
        factory.setFee(true, 3); // 3 bps = 0.03%

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pool.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);

        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, assertedOutput[1], routes, address(owner), block.timestamp);

        skip(1801);
        vm.roll(block.number + 1);
        address poolFees = pool.poolFees();
        assertEq(USDC.balanceOf(poolFees), 300);
        uint256 b = USDC.balanceOf(address(owner));
        pool.claimFees();
        assertGt(USDC.balanceOf(address(owner)), b);
    }
}
