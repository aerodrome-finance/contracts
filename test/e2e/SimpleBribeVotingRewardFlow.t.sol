// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./ExtendedBaseTest.sol";

contract SimpleBribeVotingRewardFlow is ExtendedBaseTest {
    function _setUp() public override {
        skip(1 hours);
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAX_TIME);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAX_TIME);
        vm.stopPrank();
        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAX_TIME);
        vm.stopPrank();

        // create smaller veNFTs
        vm.startPrank(address(owner4));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAX_TIME / 4);
        vm.stopPrank();
        skip(1);
    }

    function testMultiEpochBribeVotingRewardFlow() public {
        // set up votes and rewards
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        address[] memory rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(USDC);

        // @dev note that the tokenId corresponds to the owner number
        // i.e. owner owns tokenId 1
        //      owner2 owns tokenId 2...
        // test with both LR & USDC throughout to account for different decimals

        /// epoch zero
        // test two voters with differing balances
        // owner + owner 4 votes
        // owner has max lock time
        // owner4 has quarter of max lock time
        uint256 currentBribe = TOKEN_1;
        uint256 usdcBribe = USDC_1;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), usdcBribe);
        voter.vote(1, pools, weights); // balance: 997231719186530010
        vm.prank(address(owner4));
        voter.vote(4, pools, weights); // balance: 249286513795874010
        skipToNextEpoch(1);
        /// epoch one
        // expect distributions to be:
        // ~4 parts to owner
        // ~1 part to owner
        uint256 pre = LR.balanceOf(address(owner));
        uint256 usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        uint256 usdcPost = USDC.balanceOf(address(owner));
        assertApproxEqRel(post - pre, (currentBribe * 800014) / 1000000, 1e13);
        assertApproxEqRel(usdcPost - usdcPre, (usdcBribe * 800014) / 1000000, 1e13);

        pre = LR.balanceOf(address(owner4));
        usdcPre = USDC.balanceOf(address(owner4));
        vm.prank(address(voter));
        bribeVotingReward.getReward(4, rewards);
        post = LR.balanceOf(address(owner4));
        usdcPost = USDC.balanceOf(address(owner4));
        assertApproxEqRel(post - pre, (currentBribe * 1999862) / 10000000, 1e13);
        assertApproxEqRel(usdcPost - usdcPre, (usdcBribe * 1999862) / 10000000, 1e13);

        // test bribe delivered late in the week
        skip(1 weeks / 2);
        currentBribe = TOKEN_1 * 2;
        usdcBribe = USDC_1 * 2;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), usdcBribe);
        skip(1);

        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        vm.prank(address(owner4));
        voter.reset(4);

        /// epoch two
        skipToNextEpoch(1);

        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(post - pre, currentBribe / 2);
        assertEq(usdcPost - usdcPre, usdcBribe / 2);

        pre = LR.balanceOf(address(owner2));
        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(post - pre, currentBribe / 2);
        assertEq(usdcPost - usdcPre, usdcBribe / 2);

        // test deferred claiming of bribes
        uint256 deferredBribe = TOKEN_1 * 3;
        uint256 deferredUsdcBribe = USDC_1 * 3;
        _createBribeWithAmount(bribeVotingReward, address(LR), deferredBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), deferredUsdcBribe);
        skip(1 hours);

        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);

        /// epoch three
        skipToNextEpoch(1);

        // test multiple reward tokens for pool2
        currentBribe = TOKEN_1 * 4;
        usdcBribe = USDC_1 * 4;
        _createBribeWithAmount(bribeVotingReward2, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward2, address(USDC), usdcBribe);
        skip(1);

        // skip claiming this epoch, but check earned
        uint256 earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, deferredBribe / 2);
        earned = bribeVotingReward.earned(address(USDC), 1);
        assertEq(earned, deferredUsdcBribe / 2);
        earned = bribeVotingReward.earned(address(LR), 2);
        assertEq(earned, deferredBribe / 2);
        earned = bribeVotingReward.earned(address(USDC), 2);
        assertEq(earned, deferredUsdcBribe / 2);
        skip(1 hours);

        // vote for pool2 instead with owner3
        pools[0] = address(pool2);
        voter.vote(1, pools, weights);
        vm.prank(address(owner3));
        voter.vote(3, pools, weights);

        /// epoch four
        skipToNextEpoch(1);

        // claim for first voter
        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(post - pre, currentBribe / 2);
        assertEq(usdcPost - usdcPre, usdcBribe / 2);

        // claim for second voter
        pre = LR.balanceOf(address(owner3));
        usdcPre = USDC.balanceOf(address(owner3));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(3, rewards);
        post = LR.balanceOf(address(owner3));
        usdcPost = USDC.balanceOf(address(owner3));
        assertEq(post - pre, currentBribe / 2);
        assertEq(usdcPost - usdcPre, usdcBribe / 2);

        // claim deferred bribe
        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(post - pre, deferredBribe / 2);
        assertEq(usdcPost - usdcPre, deferredUsdcBribe / 2);

        pre = LR.balanceOf(address(owner2));
        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        usdcPost = USDC.balanceOf(address(owner2));
        assertEq(post - pre, deferredBribe / 2);
        assertEq(usdcPost - usdcPre, deferredUsdcBribe / 2);

        // test staggered votes
        currentBribe = TOKEN_1 * 5;
        usdcBribe = USDC_1 * 5;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), usdcBribe);
        skip(1 hours);

        // owner re-locks to max time, is currently 4 weeks ahead
        escrow.increaseUnlockTime(1, MAX_TIME);

        pools[0] = address(pool);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights); // balance: 978082175809808010
        skip(1 days);
        voter.vote(1, pools, weights); // balance: 996575326492544010

        /// epoch five
        skipToNextEpoch(1);

        // owner share: 996575326492544010/(978082175809808010+996575326492544010) ~= .505
        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertApproxEqRel(post - pre, (currentBribe * 504683) / 1000000, PRECISION);
        assertApproxEqRel(usdcPost - usdcPre, (usdcBribe * 504683) / 1000000, PRECISION);

        // owner2 share: 978082175809808010/(978082175809808010+996575326492544010) ~= .495
        pre = LR.balanceOf(address(owner2));
        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        usdcPost = USDC.balanceOf(address(owner2));
        assertApproxEqRel(post - pre, (currentBribe * 495317) / 1000000, PRECISION);
        assertApproxEqRel(usdcPost - usdcPre, (usdcBribe * 495317) / 1000000, PRECISION);

        currentBribe = TOKEN_1 * 6;
        usdcBribe = USDC_1 * 6;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), usdcBribe);

        // test votes with different vote size
        // owner2 increases amount
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(2, TOKEN_1);
        vm.stopPrank();

        skip(1 hours);

        voter.vote(1, pools, weights); // balance: 992465745379384005
        vm.prank(address(owner2));
        voter.vote(2, pools, weights); // balance: 1946575326502534409

        /// epoch six
        skipToNextEpoch(1);

        // owner share: 992465745379384005/(992465745379384005+1946575326502534409) ~= .338
        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        assertApproxEqRel(post - pre, (currentBribe * 338) / 1000, 1e15); // 3 decimal places
        assertApproxEqRel(usdcPost - usdcPre, (usdcBribe * 338) / 1000, 1e15);

        // owner2 share: 1946575326502534409/(992465745379384005+1946575326502534409) ~= .662
        pre = LR.balanceOf(address(owner2));
        usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(voter));
        bribeVotingReward.getReward(2, rewards);
        post = LR.balanceOf(address(owner2));
        usdcPost = USDC.balanceOf(address(owner2));
        assertApproxEqRel(post - pre, (currentBribe * 662) / 1000, 1e15);
        assertApproxEqRel(usdcPost - usdcPre, (usdcBribe * 662) / 1000, 1e15);

        skip(1 hours);
        // stop voting with owner2
        vm.prank(address(owner2));
        voter.reset(2);

        // test multiple pools. only bribe pool1 with LR, pool2 with USDC
        // create normal bribes for pool
        currentBribe = TOKEN_1 * 7;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        // create usdc bribe for pool2
        usdcBribe = USDC_1 * 7;
        _createBribeWithAmount(bribeVotingReward2, address(USDC), usdcBribe);
        skip(1);

        // re-lock owner + owner3
        escrow.increaseUnlockTime(1, MAX_TIME);
        vm.prank(address(owner3));
        escrow.increaseUnlockTime(3, MAX_TIME);
        skip(1 hours);

        pools = new address[](2);
        weights = new uint256[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        weights[0] = 2000;
        weights[1] = 8000;

        voter.vote(1, pools, weights); // 1 votes 20% pool 80 pool2
        weights[0] = 8000;
        weights[1] = 2000;
        vm.prank(address(owner3));
        voter.vote(3, pools, weights); // 3 votes 80% pool 20%% pool2

        skipToNextEpoch(1);

        // owner should receive 1/5, owner3 should receive 4/5 of pool bribes
        pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        assertEq(post - pre, currentBribe / 5);

        pre = LR.balanceOf(address(owner3));
        vm.prank(address(voter));
        bribeVotingReward.getReward(3, rewards);
        post = LR.balanceOf(address(owner3));
        assertEq(post - pre, (currentBribe * 4) / 5);

        // owner should receive 4/5, owner3 should receive 1/5 of pool2 bribes
        rewards[0] = address(USDC);
        delete rewards[1];
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(1, rewards);
        usdcPost = USDC.balanceOf(address(owner));
        assertEq(usdcPost - usdcPre, (usdcBribe * 4) / 5);

        usdcPre = USDC.balanceOf(address(owner3));
        vm.prank(address(voter));
        bribeVotingReward2.getReward(3, rewards);
        usdcPost = USDC.balanceOf(address(owner3));
        assertEq(usdcPost - usdcPre, usdcBribe / 5);

        skipToNextEpoch(1);

        // test passive voting
        currentBribe = TOKEN_1 * 8;
        usdcBribe = USDC_1 * 8;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), usdcBribe);
        skip(1 hours);

        pools = new address[](1);
        weights = new uint256[](1);
        pools[0] = address(pool);
        weights[0] = 500;
        rewards[0] = address(LR);
        rewards[1] = address(USDC);
        voter.vote(1, pools, weights);
        vm.prank(address(owner3));
        voter.vote(3, pools, weights);

        skipToNextEpoch(1);

        // check earned
        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, currentBribe / 2);
        earned = bribeVotingReward.earned(address(USDC), 1);
        assertEq(earned, usdcBribe / 2);
        earned = bribeVotingReward.earned(address(LR), 3);
        assertEq(earned, currentBribe / 2);
        earned = bribeVotingReward.earned(address(USDC), 3);
        assertEq(earned, usdcBribe / 2);

        currentBribe = TOKEN_1 * 9;
        usdcBribe = USDC_1 * 9;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), usdcBribe);

        uint256 expected = (TOKEN_1 * 8) / 2;
        // check earned remains the same even if bribe gets re-deposited
        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, expected);
        earned = bribeVotingReward.earned(address(LR), 3);
        assertEq(earned, expected);
        expected = (USDC_1 * 8) / 2;
        earned = bribeVotingReward.earned(address(USDC), 1);
        assertEq(earned, expected);
        earned = bribeVotingReward.earned(address(USDC), 3);
        assertEq(earned, expected);

        skipToNextEpoch(1);

        currentBribe = TOKEN_1 * 10;
        usdcBribe = USDC_1 * 10;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), usdcBribe);

        expected = (TOKEN_1 * 8 + TOKEN_1 * 9) / 2;
        earned = bribeVotingReward.earned(address(LR), 1);
        assertEq(earned, expected);
        earned = bribeVotingReward.earned(address(LR), 3);
        assertEq(earned, expected);
        expected = (USDC_1 * 8 + USDC_1 * 9) / 2;
        earned = bribeVotingReward.earned(address(USDC), 1);
        assertEq(earned, expected);
        earned = bribeVotingReward.earned(address(USDC), 3);
        assertEq(earned, expected);

        skipToNextEpoch(1);

        currentBribe = TOKEN_1 * 11;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);

        pre = LR.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        post = LR.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));
        expected = (TOKEN_1 * 8 + TOKEN_1 * 9 + TOKEN_1 * 10) / 2;
        assertEq(post - pre, expected);
        expected = (USDC_1 * 8 + USDC_1 * 9 + USDC_1 * 10) / 2;
        assertEq(usdcPost - usdcPre, expected);

        pre = LR.balanceOf(address(owner3));
        usdcPre = USDC.balanceOf(address(owner3));
        vm.prank(address(voter));
        bribeVotingReward.getReward(3, rewards);
        post = LR.balanceOf(address(owner3));
        usdcPost = USDC.balanceOf(address(owner3));
        expected = (TOKEN_1 * 8 + TOKEN_1 * 9 + TOKEN_1 * 10) / 2;
        assertEq(post - pre, expected);
        expected = (USDC_1 * 8 + USDC_1 * 9 + USDC_1 * 10) / 2;
        assertEq(usdcPost - usdcPre, expected);
    }

    function testCanClaimRewardAfterTransferWhileVoted() public {
        // set up votes and rewards
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        address[] memory rewards = new address[](2);
        rewards[0] = address(LR);
        rewards[1] = address(USDC);

        uint256 currentBribe = TOKEN_1;
        uint256 usdcBribe = USDC_1;
        _createBribeWithAmount(bribeVotingReward, address(LR), currentBribe);
        _createBribeWithAmount(bribeVotingReward, address(USDC), usdcBribe);
        voter.vote(1, pools, weights);
        vm.prank(address(owner4));
        voter.vote(4, pools, weights);

        skip(1 days);

        // simulate sale of nft to other owner3
        escrow.transferFrom(address(owner), address(owner3), 1);
        assertFalse(escrow.isApprovedOrOwner(address(owner), 1));

        skipToNextEpoch(1);

        /// epoch one
        // expect distributions to be:
        // ~4 parts to owner3 (new owner of nft)
        // ~1 part to owner4
        uint256 pre = LR.balanceOf(address(owner3));
        uint256 usdcPre = USDC.balanceOf(address(owner3));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner3));
        uint256 usdcPost = USDC.balanceOf(address(owner3));
        assertApproxEqRel(post - pre, (currentBribe * 800014) / 1000000, 1e13);
        assertApproxEqRel(usdcPost - usdcPre, (usdcBribe * 800014) / 1000000, 1e13);

        pre = LR.balanceOf(address(owner4));
        usdcPre = USDC.balanceOf(address(owner4));
        vm.prank(address(voter));
        bribeVotingReward.getReward(4, rewards);
        post = LR.balanceOf(address(owner4));
        usdcPost = USDC.balanceOf(address(owner4));
        assertApproxEqRel(post - pre, (currentBribe * 1999862) / 10000000, 1e13);
        assertApproxEqRel(usdcPost - usdcPre, (usdcBribe * 1999862) / 10000000, 1e13);
    }
}
