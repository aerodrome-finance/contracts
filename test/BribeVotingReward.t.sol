// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract BribeVotingRewardTest is BaseTest {
    event NotifyReward(address indexed from, address indexed reward, uint256 indexed epoch, uint256 amount);

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
        skip(1);
    }

    function testGetRewardWithZeroTotalSupply() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // check earned is correct
        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        // add bribe for epoch 2
        LR.approve(address(bribeVotingReward), TOKEN_1 * 2);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        // remove supply by voting for other pool
        pools[0] = address(pool2);
        voter.vote(1, pools, weights);

        assertEq(bribeVotingReward.totalSupply(), 0);

        skipToNextEpoch(1);

        // check can still claim bribe
        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testGetRewardWithMultipleStaggeredRewardsInOneEpoch() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create a bribe
        LR.approve(address(bribeVotingReward), reward);
        bribeVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skip(1 days);

        // create another bribe for the same pool in the same epoch
        LR.approve(address(bribeVotingReward), reward2);
        bribeVotingReward.notifyRewardAmount((address(LR)), reward2);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        // expect both rewards
        uint256 totalReward = reward + reward2;
        assertEq(post - pre, totalReward);
    }

    function testCannotGetRewardMoreThanOncePerEpochWithSingleReward() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.startPrank(address(voter));
        // claim first time
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        skip(1);
        // claim second time
        bribeVotingReward.getReward(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1 / 2);
    }

    function testCannotGetRewardMoreThanOncePerEpochWithMultipleRewards() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        // rewards
        address[] memory rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(LR);

        vm.startPrank(address(voter));
        // claim first time
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        // claim second time
        bribeVotingReward.getReward(1, rewards);
        vm.stopPrank();

        uint256 post_post = LR.balanceOf(address(owner));
        assertEq(post_post, post);
        assertEq(post_post - pre, TOKEN_1 / 2);
    }

    function testCannotGetRewardIfNotVoterOrOwnerOrApproved() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;

        // create a bribe
        LR.approve(address(bribeVotingReward), reward);
        bribeVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        vm.prank(address(owner2));
        vm.expectRevert(IReward.NotAuthorized.selector);
        bribeVotingReward.getReward(1, rewards);
    }

    function testGetRewardWithMultipleVotes() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create a bribe
        LR.approve(address(bribeVotingReward), reward);
        bribeVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        skipToNextEpoch(1 hours + 1);

        // create another bribe for the same pool the following week
        LR.approve(address(bribeVotingReward), reward2);
        bribeVotingReward.notifyRewardAmount((address(LR)), reward2);

        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        uint256 totalReward = reward + reward2;
        assertEq(post - pre, totalReward);
    }

    function testGetRewardWithVotesForDifferentPoolsAcrossEpochs() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create a bribe for pool in epoch 0
        LR.approve(address(bribeVotingReward), reward);
        bribeVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1 hours + 1);

        // create a bribe for pool2 in epoch 1
        LR.approve(address(bribeVotingReward2), reward2);
        bribeVotingReward2.notifyRewardAmount((address(LR)), reward2);
        pools[0] = address(pool2);

        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // check rewards accrue correctly for pool
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        assertEq(post - pre, reward / 2);

        // check rewards accrue correctly for pool2
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));

        assertEq(post - pre, reward2);
    }

    function testGetRewardWithPassiveVote() public {
        skip(1 weeks / 2);

        // create a bribe in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(bribeVotingReward)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);
        skip(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        // create another bribe in epoch 1 but do not vote
        LR.approve(address(bribeVotingReward), TOKEN_1 * 2);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        assertEq(LR.balanceOf(address(bribeVotingReward)), TOKEN_1 * 2);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 2);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 * 2);
    }

    function testGetRewardWithPassiveVotes() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount((address(LR)), TOKEN_1);

        // vote in epoch 0
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);
        skip(1);

        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        // epoch 1: five epochs pass, with an incrementing reward
        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        LR.approve(address(bribeVotingReward), TOKEN_1 * 2);
        bribeVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 2);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        // epoch 2
        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 3);

        LR.approve(address(bribeVotingReward), TOKEN_1 * 3);
        bribeVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 3);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 3);

        // epoch 3
        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 6);

        LR.approve(address(bribeVotingReward), TOKEN_1 * 4);
        bribeVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 4);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 6);

        // epoch 4
        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 10);

        LR.approve(address(bribeVotingReward), TOKEN_1 * 5);
        bribeVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 5);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 10);

        // epoch 5
        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 15);

        LR.approve(address(bribeVotingReward), TOKEN_1 * 6);
        bribeVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 6);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 15);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // total rewards: 1 + 2 + 3 + 4 + 5 + 6
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        assertEq(post - pre, TOKEN_1 * 21);
    }

    function testCannotGetRewardInSameWeekIfEpochYetToFlip() public {
        /// tests that rewards deposited that week cannot be claimed until next week
        skip(1 weeks / 2);

        // create bribe in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount((address(LR)), TOKEN_1);

        // vote in epoch 0
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        skipToNextEpoch(1);

        // create bribe in epoch 1
        LR.approve(address(bribeVotingReward), TOKEN_1 * 2);
        bribeVotingReward.notifyRewardAmount((address(LR)), TOKEN_1 * 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // claim before flip but after rewards are re-deposited into bribe
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);

        skipToNextEpoch(1);

        // claim after flip
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 * 2);
    }

    function testGetRewardWithSingleVoteAndPoke() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1;
        uint256 reward2 = TOKEN_1 * 2;

        // create a bribe in epoch 0
        LR.approve(address(bribeVotingReward), reward);
        bribeVotingReward.notifyRewardAmount((address(LR)), reward);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);
        skip(1);

        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        // create a bribe in epoch 1
        LR.approve(address(bribeVotingReward), reward2);
        bribeVotingReward.notifyRewardAmount((address(LR)), reward2);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);
        skip(1 hours);

        voter.poke(1);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));

        uint256 total = reward + reward2;
        assertEq(post - pre, total);
    }

    function testGetRewardWithSingleCheckpoint() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(bribeVotingReward)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // cannot claim
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, 0);

        // fwd half a week
        skipToNextEpoch(1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testGetRewardWithSingleCheckpointWithOtherVoter() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(bribeVotingReward)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        skipToNextEpoch(1);

        // deliver bribe
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, TOKEN_1 / 2);
    }

    function testGetRewardWithSingleCheckpointWithOtherStaggeredVoter() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        assertEq(LR.balanceOf(address(bribeVotingReward)), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        // vote delayed
        skip(1 days);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // fwd
        skipToNextEpoch(1);

        // deliver bribe
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertGt(post - pre, TOKEN_1 / 2); // 500172176312657261
        uint256 diff = post - pre;

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertLt(post - pre, TOKEN_1 / 2); // 499827823687342738
        uint256 diff2 = post - pre;

        assertEq(diff + diff2, TOKEN_1 - 1); // -1 for rounding
    }

    function testGetRewardWithSkippedClaims() public {
        skip(1 weeks / 2);

        uint256 reward = TOKEN_1; // epoch 0 reward
        uint256 reward2 = TOKEN_1 * 2; // epoch1 reward
        uint256 reward3 = TOKEN_1 * 3; // epoch3 reward

        // create bribe with amount reward in epoch 0
        LR.approve(address(bribeVotingReward), reward);
        bribeVotingReward.notifyRewardAmount(address(LR), reward);
        assertEq(LR.balanceOf(address(bribeVotingReward)), reward);

        // vote for pool
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        // check reward amount is correct
        uint256 expectedReward = reward / 2;
        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, expectedReward);
        earned = bribeVotingReward.earned(address(LR), 2);
        assertEq(earned, expectedReward);

        // create bribe with amount reward2 in epoch 1
        LR.approve(address(bribeVotingReward), reward2);
        bribeVotingReward.notifyRewardAmount(address(LR), reward2);
        assertEq(LR.balanceOf(address(bribeVotingReward)), reward + reward2);

        skip(1 hours);

        // vote again for same pool
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        expectedReward = (reward + reward2) / 2;
        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, expectedReward);
        earned = bribeVotingReward.earned(address(LR), 2);
        assertEq(earned, expectedReward);

        // create bribe with amount reward3 in epoch 2
        LR.approve(address(bribeVotingReward), reward3);
        bribeVotingReward.notifyRewardAmount(address(LR), reward3);
        assertEq(LR.balanceOf(address(bribeVotingReward)), reward + reward2 + reward3);
        skip(1 hours);

        // poked into voting for same pool
        voter.poke(1);
        voter.poke(2);

        skipToNextEpoch(1);

        expectedReward = (reward + reward2 + reward3) / 2;
        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, expectedReward);
        earned = bribeVotingReward.earned(address(LR), 2);
        assertEq(earned, expectedReward);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, expectedReward);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, expectedReward);
    }

    function testCannotClaimRewardForPoolIfPokedButVotedForOtherPool() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        address[] memory pools2 = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        pools2[0] = address(pool2);
        weights[0] = 10000;

        // create a bribe in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, TOKEN_1 / 2);

        skip(1);

        // create a bribe for pool in epoch 1
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // create a bribe for pool2 in epoch 1
        LR.approve(address(bribeVotingReward2), TOKEN_1 * 2);
        bribeVotingReward2.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        // poke causes id 1 to "vote" for pool
        voter.poke(1);
        skip(1 hours);

        // vote for pool2 in epoch 1
        voter.vote(1, pools2, weights);

        // go to next epoch
        skipToNextEpoch(1);

        // earned for pool should be 0
        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        // earned for pool for nft 2 should be full bribe amount
        earned = bribeVotingReward.earned(address(LR), 2);
        assertEq(earned, TOKEN_1);

        // earned for pool2 should be TOKEN_1
        earned = bribeVotingReward2.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 * 2);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 * 2);
    }

    function testGetRewardWithAlternatingVotes() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        address[] memory pools2 = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        pools2[0] = address(pool2);
        weights[0] = 10000;

        // create a bribe in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        // fwd half a week
        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        skip(1);

        // create a bribe for pool in epoch 1
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // create a bribe for pool2 in epoch 1
        LR.approve(address(bribeVotingReward2), TOKEN_1 * 2);
        bribeVotingReward2.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        voter.vote(1, pools2, weights);
        vm.prank(address(owner3));
        voter.vote(3, pools2, weights);

        // go to next week
        skipToNextEpoch(1 hours + 1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        voter.vote(1, pools, weights);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        earned = bribeVotingReward2.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    // same test as above but with some initial checkpoints in place
    function testGetRewardWithAlternatingVotesWithInitialCheckpoints() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        address[] memory pools2 = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        pools2[0] = address(pool2);
        weights[0] = 10000;

        // add initial checkpoints
        for (uint256 i = 0; i < 5; i++) {
            // vote for pool in epoch 0
            voter.vote(1, pools, weights);
            vm.prank(address(owner2));
            voter.vote(2, pools, weights);

            // fwd half a week
            skipToNextEpoch(1 hours + 1);
        }

        // create a bribe in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        // fwd half a week
        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        skip(1);

        // create a bribe for pool in epoch 1
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // create a bribe for pool2 in epoch 1
        LR.approve(address(bribeVotingReward2), TOKEN_1 * 2);
        bribeVotingReward2.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        voter.vote(1, pools2, weights);
        vm.prank(address(owner3));
        voter.vote(3, pools2, weights);

        // go to next week
        skipToNextEpoch(1 hours + 1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        voter.vote(1, pools, weights);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
        earned = bribeVotingReward2.earned(address(LR), 1);
        assertEq(earned, TOKEN_1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testCannotClaimRewardForPoolIfPokedButReset() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create a bribe in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);
        skip(1);

        // create a bribe for pool in epoch 1
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        skip(1 hours);

        // poke causes id 1 to "vote" for pool
        voter.poke(1);
        skip(1);

        // abstain in epoch 1
        voter.reset(1);

        // go to next epoch
        skipToNextEpoch(1);

        // earned for pool should be 0
        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);
    }

    function testGetRewardWithVoteThenPoke() public {
        /// tests poking makes no difference to voting outcome
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create a bribe in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);
        skip(1);

        // create a bribe for pool in epoch 1
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        skip(1 hours);

        voter.vote(1, pools, weights);
        skip(1 hours);

        // get poked an hour later
        voter.poke(1);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // go to next epoch
        skipToNextEpoch(1);

        // earned for pool should be 0
        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);
    }

    function testGetRewardWithVotesForMultiplePools() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](2);
        uint256[] memory weights = new uint256[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        weights[0] = 2;
        weights[1] = 8;

        // create a bribe in epoch 0 for pool
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        // create a usdc bribe in epoch 1 for pool2
        USDC.approve(address(bribeVotingReward2), USDC_1);
        bribeVotingReward2.notifyRewardAmount(address(USDC), USDC_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights); // 20% to pool, 80% to pool2

        // flip weights around
        weights[0] = 8;
        weights[1] = 2;
        vm.prank(address(owner2));
        voter.vote(2, pools, weights); // 80% to pool, 20% to pool2

        skipToNextEpoch(1);

        // check pool bribes are correct
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 5);

        pre = LR.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        assertEq(post - pre, (TOKEN_1 * 4) / 5);

        // check pool2 bribes are correct
        rewards[0] = address(USDC);
        pre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(1, rewards);
        post = USDC.balanceOf(address(owner));
        assertEq(post - pre, (USDC_1 * 4) / 5);

        pre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(2, rewards);
        post = USDC.balanceOf(address(owner2));
        assertEq(post - pre, USDC_1 / 5);
    }

    function testCannotGetRewardForNewPoolVotedAfterEpochFlip() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create a bribe for pool and pool2 in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        USDC.approve(address(bribeVotingReward2), USDC_1);
        bribeVotingReward2.notifyRewardAmount(address(USDC), USDC_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        // owner3 votes for pool2
        pools[0] = address(pool2);
        vm.prank(address(owner3));
        voter.vote(3, pools, weights);

        // go to next epoch but do not distribute
        skipToNextEpoch(1 hours + 1);

        // vote for pool2 shortly after epoch flips
        voter.vote(1, pools, weights);
        skip(1);

        // attempt to claim from initial pool currently voted for fails
        uint256 pre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(1, rewards);
        uint256 post = USDC.balanceOf(address(owner));
        assertEq(post - pre, 0);

        // claim last week's rewards
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);
    }

    function testCannotGetRewardInSameEpochAsVote() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create a bribe for pool in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        skip(1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, 0);

        skipToNextEpoch(1);

        // create a bribe for pool in epoch 1
        LR.approve(address(bribeVotingReward), TOKEN_1 * 2);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1 hours);

        // vote for pool in epoch 1
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        // attempt claim again after vote, only get rewards from epoch 0
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        skipToNextEpoch(1);

        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testCannotGetRewardInSameEpochAsVoteWithFuzz(uint256 ts) public {
        skipToNextEpoch(1 hours + 1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create a bribe for pool in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));

        ts = bound(ts, 0, 1 weeks - (1 hours) - 2);
        skipAndRoll(ts);

        assertEq(bribeVotingReward.earned(address(LR), 1), 0);
    }

    function testGetRewardWithVoteAndNotifyRewardInDifferentOrders() public {
        skip(1 weeks / 2);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // set up votes
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 10000;

        // create a bribe for pool in epoch 0
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        skip(1 hours);

        // vote for pool in epoch 0
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);
        skip(1 hours);

        // vote first, then create bribe
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        LR.approve(address(bribeVotingReward), TOKEN_1 * 2);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        skip(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        skipToNextEpoch(1);

        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, (TOKEN_1 * 3) / 2);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, (TOKEN_1 * 3) / 2);
    }

    function testDepositAndWithdrawCreatesCheckpoints() public {
        skip(1 weeks / 2);

        uint256 numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 0); // no existing checkpoints

        (uint256 ts, uint256 balance) = bribeVotingReward.checkpoints(1, 0);
        assertEq(ts, 0);
        assertEq(balance, 0);

        // deposit by voting
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        uint256 expectedTs = block.timestamp;
        uint256 expectedBal = escrow.balanceOfNFT(1);

        // check single user and supply checkpoint created
        numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 1);
        (uint256 sTs, uint256 sBalance) = bribeVotingReward.supplyCheckpoints(0);
        assertEq(sTs, expectedTs);
        assertEq(sBalance, expectedBal);

        (ts, balance) = bribeVotingReward.checkpoints(1, 0);
        assertEq(ts, expectedTs);
        assertEq(balance, expectedBal);

        skipToNextEpoch(1 hours + 1);

        // withdraw by voting for other pool
        pools[0] = address(pool2);
        voter.vote(1, pools, weights);

        numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 2);

        expectedTs = block.timestamp;

        // check new checkpoint created
        (ts, balance) = bribeVotingReward.checkpoints(1, 1);
        assertEq(ts, expectedTs);
        assertEq(balance, 0); // balance 0 on withdraw
        (sTs, sBalance) = bribeVotingReward.supplyCheckpoints(1);
        assertEq(sTs, expectedTs);
        assertEq(sBalance, 0);
    }

    function testDepositAndWithdrawWithinSameEpochOverwritesCheckpoints() public {
        skip(1 weeks / 2);

        // test vote and poke overwrites checkpoints
        // deposit by voting
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        voter.vote(1, pools, weights);

        uint256 expectedTs = block.timestamp;
        uint256 expectedBal = escrow.balanceOfNFT(1);

        // check single user and supply checkpoint created
        uint256 numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 1);

        (uint256 sTs, uint256 sBalance) = bribeVotingReward.supplyCheckpoints(0);
        assertEq(sTs, expectedTs);
        assertEq(sBalance, expectedBal);

        (uint256 ts, uint256 balance) = bribeVotingReward.checkpoints(1, 0);
        assertEq(ts, expectedTs);
        assertEq(balance, expectedBal);

        // poked after one day. any checkpoints created should overwrite prior checkpoints.
        skip(1 days);
        voter.poke(1);

        expectedTs = block.timestamp;
        expectedBal = escrow.balanceOfNFT(1);

        numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 1);
        (sTs, sBalance) = bribeVotingReward.supplyCheckpoints(0);
        assertEq(sTs, expectedTs);
        assertEq(sBalance, expectedBal);

        (ts, balance) = bribeVotingReward.checkpoints(1, 0);
        assertEq(ts, expectedTs);
        assertEq(sBalance, expectedBal);

        // check poke and reset/withdraw overwrites checkpoints
        skipToNextEpoch(1 hours + 1);

        // poke to create a checkpoint in new epoch
        voter.poke(1);

        // check old checkpoints are not overridden
        numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 2);
        (sTs, sBalance) = bribeVotingReward.supplyCheckpoints(0);
        assertEq(sTs, expectedTs);
        assertEq(sBalance, expectedBal);

        (ts, balance) = bribeVotingReward.checkpoints(1, 0);
        assertEq(ts, expectedTs);
        assertEq(sBalance, expectedBal);

        expectedTs = block.timestamp;
        expectedBal = escrow.balanceOfNFT(1);

        numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 2);
        (sTs, sBalance) = bribeVotingReward.supplyCheckpoints(1);
        assertEq(sTs, expectedTs);
        assertEq(sBalance, expectedBal);

        (ts, balance) = bribeVotingReward.checkpoints(1, 1);
        assertEq(ts, expectedTs);
        assertEq(sBalance, expectedBal);

        // withdraw via reset after one day, expect supply to be zero
        skip(1 days);
        voter.reset(1);

        expectedTs = block.timestamp;

        numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 2);
        (sTs, sBalance) = bribeVotingReward.supplyCheckpoints(1);
        assertEq(sTs, expectedTs);
        assertEq(sBalance, 0);

        (ts, balance) = bribeVotingReward.checkpoints(1, 1);
        assertEq(ts, expectedTs);
        assertEq(sBalance, 0);
    }

    function testDepositFromManyUsersInSameTimestampOverwritesSupplyCheckpoint() public {
        skip(1 weeks / 2);

        // deposit by voting
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        // test two (supply) checkpoints at same ts
        voter.vote(1, pools, weights);

        uint256 ownerBal = escrow.balanceOfNFT(1);
        uint256 owner2Bal = escrow.balanceOfNFT(2);
        uint256 totalSupply = ownerBal + owner2Bal;

        // check single user and supply checkpoint created
        uint256 numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 1);
        (uint256 sTs, uint256 sBalance) = bribeVotingReward.supplyCheckpoints(0);
        assertEq(sTs, block.timestamp);
        assertEq(sBalance, ownerBal);

        (uint256 ts, uint256 balance) = bribeVotingReward.checkpoints(1, 0);
        assertEq(ts, block.timestamp);
        assertEq(balance, ownerBal);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        numSupply = bribeVotingReward.supplyNumCheckpoints();
        assertEq(numSupply, 1);
        (sTs, sBalance) = bribeVotingReward.supplyCheckpoints(0);
        assertEq(sTs, block.timestamp);
        assertEq(sBalance, totalSupply);

        (ts, balance) = bribeVotingReward.checkpoints(2, 0);
        assertEq(ts, block.timestamp);
        assertEq(balance, owner2Bal);
    }

    function testGetRewardWithSeparateRewardClaims() public {
        skip(1 weeks / 2);

        // create a LR bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        skipToNextEpoch(1);

        // create usdc bribe, vote passively this epoch
        USDC.approve(address(bribeVotingReward), USDC_1);
        bribeVotingReward.notifyRewardAmount(address(USDC), USDC_1);

        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, TOKEN_1 / 2);

        earned = bribeVotingReward.earned(address(USDC), 1);
        assertEq(earned, 0);

        skipToNextEpoch(1);

        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        // claim LR reward first
        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1 / 2);

        skipToNextEpoch(1);

        // claim USDC the week after
        rewards[0] = address(USDC);
        pre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = USDC.balanceOf(address(owner));
        assertEq(post - pre, USDC_1 / 2);
    }

    function testCannotNotifyRewardWithZeroAmount() public {
        vm.expectRevert(IReward.ZeroAmount.selector);
        bribeVotingReward.notifyRewardAmount(address(LR), 0);
    }

    function testCannotNotifyRewardWithUnwhitelistedToken() public {
        address token = address(new MockERC20("TEST", "TEST", 18));

        assertEq(voter.isWhitelistedToken(token), false);

        vm.expectRevert(IReward.NotWhitelisted.selector);
        bribeVotingReward.notifyRewardAmount(token, TOKEN_1);
    }

    function testNotifyRewardAmountWithWhiteListedToken() public {
        LR.approve(address(bribeVotingReward), TOKEN_1);
        uint256 pre = LR.balanceOf(address(owner));
        vm.expectEmit(true, true, true, true, address(bribeVotingReward));
        emit NotifyReward(address(owner), address(LR), 604800, TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);
        uint256 post = LR.balanceOf(address(owner));

        assertEq(bribeVotingReward.isReward(address(LR)), true);
        assertEq(bribeVotingReward.tokenRewardsPerEpoch(address(LR), 604800), TOKEN_1);
        assertEq(pre - post, TOKEN_1);
        assertEq(LR.balanceOf(address(bribeVotingReward)), TOKEN_1);

        skip(1 hours);

        LR.approve(address(bribeVotingReward), TOKEN_1 * 2);
        pre = LR.balanceOf(address(owner));
        vm.expectEmit(true, true, true, true, address(bribeVotingReward));
        emit NotifyReward(address(owner), address(LR), 604800, TOKEN_1 * 2);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1 * 2);
        post = LR.balanceOf(address(owner));

        assertEq(bribeVotingReward.tokenRewardsPerEpoch(address(LR), 604800), TOKEN_1 * 3);
        assertEq(pre - post, TOKEN_1 * 2);
        assertEq(LR.balanceOf(address(bribeVotingReward)), TOKEN_1 * 3);
    }
}
