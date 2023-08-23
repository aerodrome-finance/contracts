// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract LockedManagedRewardTest is BaseTest {
    event NotifyReward(address indexed from, address indexed reward, uint256 indexed epoch, uint256 amount);

    LockedManagedReward lockedManagedReward;
    uint256 mTokenId;

    function _setUp() public override {
        // ve
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.prank(address(governor));
        mTokenId = escrow.createManagedLockFor(address(owner4));
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        skip(1);
    }

    function testCannotNotifyRewardIfNotVotingEscrow() public {
        vm.prank(address(owner2));
        vm.expectRevert(IReward.NotVotingEscrow.selector);
        lockedManagedReward.notifyRewardAmount(address(AERO), 0);
    }

    function testCannotNotifyRewardWithZeroAmount() public {
        vm.prank(address(escrow));
        vm.expectRevert(IReward.ZeroAmount.selector);
        lockedManagedReward.notifyRewardAmount(address(AERO), 0);
    }

    function testCannotNotifyRewardAmountIfNotEscrowToken() public {
        address token = address(new MockERC20("TEST", "TEST", 18));
        assertEq(voter.isWhitelistedToken(token), false);

        vm.prank(address(escrow));
        vm.expectRevert(IReward.NotEscrowToken.selector);
        lockedManagedReward.notifyRewardAmount(token, TOKEN_1);
    }

    function testNotifyRewardAmount() public {
        deal(address(AERO), address(escrow), TOKEN_1 * 3);

        vm.prank(address(escrow));
        AERO.approve(address(lockedManagedReward), TOKEN_1);
        uint256 pre = AERO.balanceOf(address(escrow));
        vm.prank(address(escrow));
        vm.expectEmit(true, true, true, true, address(lockedManagedReward));
        emit NotifyReward(address(escrow), address(AERO), 604800, TOKEN_1);
        lockedManagedReward.notifyRewardAmount(address(AERO), TOKEN_1);
        uint256 post = AERO.balanceOf(address(escrow));

        assertEq(lockedManagedReward.isReward(address(AERO)), true);
        assertEq(lockedManagedReward.tokenRewardsPerEpoch(address(AERO), 604800), TOKEN_1);
        assertEq(pre - post, TOKEN_1);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), TOKEN_1);

        skip(1 hours);

        vm.prank(address(escrow));
        AERO.approve(address(lockedManagedReward), TOKEN_1 * 2);
        pre = AERO.balanceOf(address(escrow));
        vm.prank(address(escrow));
        vm.expectEmit(true, true, true, true, address(lockedManagedReward));
        emit NotifyReward(address(escrow), address(AERO), 604800, TOKEN_1 * 2);
        lockedManagedReward.notifyRewardAmount(address(AERO), TOKEN_1 * 2);
        post = AERO.balanceOf(address(escrow));

        assertEq(lockedManagedReward.tokenRewardsPerEpoch(address(AERO), 604800), TOKEN_1 * 3);
        assertEq(pre - post, TOKEN_1 * 2);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), TOKEN_1 * 3);
    }

    function testCannotGetRewardIfNotSingleToken() public {
        skip(1 weeks / 2);

        voter.depositManaged(1, mTokenId);
        _addLockedReward(TOKEN_1);

        skipToNextEpoch(1);

        address[] memory rewards = new address[](2);
        rewards[0] = address(AERO);
        rewards[1] = address(WETH);

        vm.prank(address(escrow));
        vm.expectRevert(IReward.NotSingleToken.selector);
        lockedManagedReward.getReward(1, rewards);
    }

    function testCannotGetRewardIfNotEscrowToken() public {
        skip(1 weeks / 2);

        address token = address(new MockERC20("TEST", "TEST", 18));
        address[] memory rewards = new address[](1);
        rewards[0] = token;

        vm.prank(address(escrow));
        vm.expectRevert(IReward.NotEscrowToken.selector);
        lockedManagedReward.getReward(1, rewards);
    }

    function testCannotGetRewardIfNotVotingEscrow() public {
        skip(1 weeks / 2);

        voter.depositManaged(1, mTokenId);
        _addLockedReward(TOKEN_1);

        skipToNextEpoch(1);

        address[] memory rewards = new address[](1);
        rewards[0] = address(AERO);

        vm.prank(address(owner2));
        vm.expectRevert(IReward.NotVotingEscrow.selector);
        lockedManagedReward.getReward(1, rewards);
    }

    function testGetReward() public {
        skip(1 weeks / 2);

        uint256 pre = convert(escrow.locked(1).amount);
        voter.depositManaged(1, mTokenId);
        _addLockedReward(TOKEN_1);

        skipToNextEpoch(1 hours + 1);

        voter.withdrawManaged(1);
        uint256 post = convert(escrow.locked(1).amount);

        assertEq(post - pre, TOKEN_1);
    }

    function _addLockedReward(uint256 _amount) internal {
        deal(address(AERO), address(distributor), _amount);
        vm.startPrank(address(distributor));
        AERO.approve(address(escrow), _amount);
        escrow.depositFor(mTokenId, _amount);
        vm.stopPrank();
    }
}
