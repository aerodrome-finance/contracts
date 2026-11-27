// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Pool} from "contracts/Pool.sol";
import {PoolFactory} from "contracts/factories/PoolFactory.sol";
import {MockERC20} from "utils/MockERC20.sol";

/// @notice Regression test for aerodrome-finance/contracts#16:
///         `Pool._get_y` used `_k(x0, y + 1)` where `_f(x0, y + 1)` is correct.
///         `_k` re-applies decimals scaling to x0/y, which are already 1e18-scaled
///         inside `_get_y`. With 18-decimal tokens `_k == _f` (no-op); with a
///         6-decimal token `_k` is wildly larger than `_f`, so the dy == 0
///         branch returns `y + 1` even though `f(x0, y + 1) < xy` — i.e. the
///         returned y is NOT the smallest y with `f(x0, y) >= xy`, and
///         `getAmountOut` overpays by 1 wei in the case below.
contract PoolGetYTest is Test {
    MockERC20 usdc; // 6 decimals
    MockERC20 frax; // 18 decimals
    Pool pool;
    PoolFactory factory;

    // Trial found by brute-force search over the exact integer arithmetic of
    // `_f` / `_d` / `_get_y` (see report): a stable USDC/FRAX pool with
    // reserves 210604 raw USDC / 10549661728470919411 raw FRAX, swapping
    // 1792 raw USDC in. Fee is set to 0, so `getAmountOut` receives the
    // full 1792 raw USDC (scaled 1792e12).
    uint256 constant RESERVE_USDC = 210604;
    uint256 constant RESERVE_FRAX = 10549661728470919411;
    uint256 constant AMOUNT_IN_USDC = 1792;
    // Fixed code: _get_y returns y = 10519876551001140060, so
    // amountOut = 10549661728470919411 - 10519876551001140060
    //           = 29785177469779351 raw FRAX.
    // Buggy code returns y = 10519876551001140059 (one less), so amountOut
    // is 29785177469779352 — 1 wei too much, and f(x0, y_buggy) < xy:
    // f = 247374689145744085713 < xy = 247374689145744085727.
    uint256 constant EXPECTED_AMOUNT_OUT = 29785177469779351;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        frax = new MockERC20("FRAX", "FRAX", 18);

        Pool implementation = new Pool();
        factory = new PoolFactory(address(implementation));
        pool = Pool(factory.createPool(address(usdc), address(frax), true));
        // 420 is PoolFactory.ZERO_FEE_INDICATOR: getAmountOut charges no fee.
        factory.setCustomFee(address(pool), 420);

        // First mint: 0.1 token of each (scaled 1e17 each, equal as required
        // for a stable pool's first mint).
        deal(address(usdc), address(this), 100000);
        deal(address(frax), address(this), 100000000000000000);
        usdc.transfer(address(pool), 100000);
        frax.transfer(address(pool), 100000000000000000);
        pool.mint(address(this));

        // Second mint: top up to the target (imbalanced) reserves.
        deal(address(usdc), address(this), RESERVE_USDC - 100000);
        deal(address(frax), address(this), RESERVE_FRAX - 100000000000000000);
        usdc.transfer(address(pool), RESERVE_USDC - 100000);
        frax.transfer(address(pool), RESERVE_FRAX - 100000000000000000);
        pool.mint(address(this));

        (uint256 r0, uint256 r1, ) = pool.getReserves();
        address token0 = pool.token0();
        if (token0 == address(usdc)) {
            assertEq(r0, RESERVE_USDC);
            assertEq(r1, RESERVE_FRAX);
        } else {
            assertEq(r0, RESERVE_FRAX);
            assertEq(r1, RESERVE_USDC);
        }
    }

    function testGetAmountOutDyZeroCaseDoesNotOverpay() public {
        uint256 amountOut = pool.getAmountOut(AMOUNT_IN_USDC, address(usdc));
        assertEq(amountOut, EXPECTED_AMOUNT_OUT);
    }
}
