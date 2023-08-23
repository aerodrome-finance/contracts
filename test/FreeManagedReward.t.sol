// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract FreeManagedRewardTest is BaseTest {
    event NotifyReward(address indexed from, address indexed reward, uint256 indexed epoch, uint256 amount);

    FreeManagedReward freeManagedReward;
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
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        skip(1);
    }

    function testCannotNotifyRewardWithZeroAmount() public {
        vm.expectRevert(IReward.ZeroAmount.selector);
        freeManagedReward.notifyRewardAmount(address(LR), 0);
    }

    function testCannotNotifyRewardAmountIfTokenNotWhitelisted() public {
        address token = address(new MockERC20("TEST", "TEST", 18));

        assertEq(voter.isWhitelistedToken(token), false);

        vm.expectRevert(IReward.NotWhitelisted.selector);
        freeManagedReward.notifyRewardAmount(token, TOKEN_1);
    }

    function testNotifyRewardAmount() public {
        LR.approve(address(freeManagedReward), TOKEN_1);
        uint256 pre = LR.balanceOf(address(owner));
        vm.expectEmit(true, true, true, true, address(freeManagedReward));
        emit NotifyReward(address(owner), address(LR), 604800, TOKEN_1);
        freeManagedReward.notifyRewardAmount(address(LR), TOKEN_1);
        uint256 post = LR.balanceOf(address(owner));

        assertEq(freeManagedReward.isReward(address(LR)), true);
        assertEq(freeManagedReward.tokenRewardsPerEpoch(address(LR), 604800), TOKEN_1);
        assertEq(pre - post, TOKEN_1);
        assertEq(LR.balanceOf(address(freeManagedReward)), TOKEN_1);

        skip(1 hours);

        LR.approve(address(freeManagedReward), TOKEN_1 * 2);
        pre = LR.balanceOf(address(owner));
        vm.expectEmit(true, true, true, true, address(freeManagedReward));
        emit NotifyReward(address(owner), address(LR), 604800, TOKEN_1 * 2);
        freeManagedReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        post = LR.balanceOf(address(owner));

        assertEq(freeManagedReward.tokenRewardsPerEpoch(address(LR), 604800), TOKEN_1 * 3);
        assertEq(pre - post, TOKEN_1 * 2);
        assertEq(LR.balanceOf(address(freeManagedReward)), TOKEN_1 * 3);
    }

    function testCannotGetRewardIfNotOwnerOrApproved() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;

        // create a bribe
        LR.approve(address(freeManagedReward), reward);
        freeManagedReward.notifyRewardAmount((address(LR)), reward);

        voter.depositManaged(1, mTokenId);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.prank(address(owner2));
        vm.expectRevert(IReward.NotAuthorized.selector);
        freeManagedReward.getReward(1, rewards);
    }

    function testGetReward() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;

        // create a bribe
        LR.approve(address(freeManagedReward), reward);
        freeManagedReward.notifyRewardAmount((address(LR)), reward);

        voter.depositManaged(1, mTokenId);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        freeManagedReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        assertEq(post - pre, TOKEN_1);
    }
}
