// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract PoolFactoryTest is BaseTest {
    function testCannotSetFeeManagerIfNotFeeManager() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPoolFactory.NotFeeManager.selector);
        factory.setFeeManager(address(owner));
    }

    function testCannotSetFeeManagerToZeroAddress() public {
        vm.prank(factory.feeManager());
        vm.expectRevert(IPoolFactory.ZeroAddress.selector);
        factory.setFeeManager(address(0));
    }

    function testFeeManagerCanSetFeeManager() public {
        factory.setFeeManager(address(owner2));
        assertEq(factory.feeManager(), address(owner2));
    }

    function testCannotSetPauserIfNotPauser() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPoolFactory.NotPauser.selector);
        factory.setPauser(address(owner2));
    }

    function testCannotSetPauserToZeroAddress() public {
        vm.prank(factory.pauser());
        vm.expectRevert(IPoolFactory.ZeroAddress.selector);
        factory.setPauser(address(0));
    }

    function testPauserCanSetPauser() public {
        factory.setPauser(address(owner2));
        assertEq(factory.pauser(), address(owner2));
    }

    function testCannotPauseIfNotPauser() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPoolFactory.NotPauser.selector);
        factory.setPauseState(true);
    }

    function testPauserCanPause() public {
        assertEq(factory.isPaused(), false);
        factory.setPauseState(true);
        assertEq(factory.isPaused(), true);
    }

    function testCannotChangeFeesIfNotFeeManager() public {
        vm.prank(address(owner2));
        vm.expectRevert(IPoolFactory.NotFeeManager.selector);
        factory.setFee(true, 2);

        vm.prank(address(owner2));
        vm.expectRevert(IPoolFactory.NotFeeManager.selector);
        factory.setCustomFee(address(pool), 5);
    }

    function testCannotSetFeeAboveMax() public {
        vm.expectRevert(IPoolFactory.FeeTooHigh.selector);
        factory.setFee(true, 301); // 301 bps = 3.01%

        vm.expectRevert(IPoolFactory.FeeTooHigh.selector);
        factory.setCustomFee(address(pool), 301); // 301 bps = 3.01%
    }

    function testCannotSetZeroFee() public {
        vm.expectRevert(IPoolFactory.ZeroFee.selector);
        factory.setFee(true, 0);
    }

    function testFeeManagerCanSetMaxValues() public {
        // Can set to 420 to indicate 0% fee
        factory.setCustomFee(address(pool), 420);
        assertEq(factory.getFee(address(pool), true), 0);
        // Can set to 1%
        factory.setCustomFee(address(pool), 100);
        assertEq(factory.getFee(address(pool), true), 100);
        assertEq(factory.getFee(address(pool), false), 100);
        // does not impact regular fee of other pool
        assertEq(factory.getFee(address(pool2), true), 5);
        assertEq(factory.getFee(address(pool2), false), 30);

        factory.setFee(true, 100);
        assertEq(factory.getFee(address(pool2), true), 100);
        assertEq(factory.getFee(address(pool2), false), 30);
        factory.setFee(false, 100);
        assertEq(factory.getFee(address(pool2), false), 100);

        factory.setCustomFee(address(pool), 420);
        assertEq(factory.getFee(address(pool), true), 0);
    }

    function testSetCustomFee() external {
        // differentiate fees for stable / non-stable
        factory.setFee(true, 42);
        factory.setFee(false, 69);

        // pool does not have custom fees- return fee correlating to boolean
        assertEq(factory.getFee(address(pool), true), 42);
        assertEq(factory.getFee(address(pool), false), 69);

        factory.setCustomFee(address(pool), 11);
        assertEq(factory.getFee(address(pool), true), 11);
        assertEq(factory.getFee(address(pool), false), 11);

        // setting custom fee back to 0 gives default stable / non-stable fees
        factory.setCustomFee(address(pool), 0);
        assertEq(factory.getFee(address(pool), true), 42);
        assertEq(factory.getFee(address(pool), false), 69);

        // setting custom fee to 420 indicates there is 0% fee for the pool
        factory.setCustomFee(address(pool), 420);
        assertEq(factory.getFee(address(pool), true), 0);
        assertEq(factory.getFee(address(pool), false), 0);
    }

    function testCannotSetCustomFeeForNonExistentPool() external {
        vm.expectRevert(IPoolFactory.InvalidPool.selector);
        factory.setCustomFee(address(1), 5);
    }
}
