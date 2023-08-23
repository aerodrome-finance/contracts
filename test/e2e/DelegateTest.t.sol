// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./ExtendedBaseTest.sol";

contract DelegateTest is ExtendedBaseTest {
    function testMultipleDelegateFlow() public {
        // starting timestamp: 604801
        // test single block delegate actions
        IVotingEscrow.LockedBalance memory locked;
        IVotingEscrow.UserPoint memory userPoint;
        IVotingEscrow.GlobalPoint memory globalPoint;
        IVotingEscrow.Checkpoint memory checkpoint;

        // create lock 1 and check state
        // 1: +1 user point, +1 voting checkpoint
        // +1 global point
        // blk: 1, ts: 604801
        // nft id               1   2   3   4   5
        // user points:         1 | 0 | 0 | 0 | 0
        // voting checkpoints:  1 | 0 | 0 | 0 | 0
        // global point epoch:  1
        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 1

        locked = escrow.locked(1);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 126403200);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(126403200), -7927447995);

        assertEq(escrow.userPointEpoch(1), 1);
        userPoint = escrow.userPointHistory(1, 1);
        assertEq(userPoint.bias, 997260265926760005); // (TOKEN_1 / MAXTIME) * (126403200 - 604801)
        assertEq(userPoint.slope, 7927447995); // TOKEN_1 / MAXTIME
        assertEq(userPoint.ts, 604801);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 1);
        globalPoint = escrow.pointHistory(1);
        assertEq(globalPoint.bias, 997260265926760005); // (TOKEN_1 / MAXTIME) * (126403200 - 604801)
        assertEq(globalPoint.slope, 7927447995); // TOKEN_1 / MAXTIME
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, 0);

        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 1);
        checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1));
        assertEq(escrow.totalSupply(), escrow.getPastVotes(address(owner), 1, 604801));
        // create lock 2
        // 2: +1 user point, +1 voting checkpoint
        // global point overwritten
        // blk: 1, ts: 604801
        // nft id               1   2   3   4   5
        // user points:         1 | 1 | 0 | 0 | 0
        // voting checkpoints:  1 | 1 | 0 | 0 | 0
        // global point epoch:  1
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();

        locked = escrow.locked(2);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 126403200);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(126403200), -7927447995 * 2);

        assertEq(escrow.userPointEpoch(2), 1);
        userPoint = escrow.userPointHistory(2, 1);
        assertEq(userPoint.bias, 997260265926760005);
        assertEq(userPoint.slope, 7927447995);
        assertEq(userPoint.ts, 604801);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 1);
        globalPoint = escrow.pointHistory(1);
        assertEq(globalPoint.bias, 997260265926760005 * 2);
        assertEq(globalPoint.slope, 7927447995 * 2);
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, 0);

        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 1);
        checkpoint = escrow.checkpoints(2, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 604801) + escrow.getPastVotes(address(owner2), 2, 604801)
        );

        // lock permanent lock 1 in same block as creation
        // user point and global point overwritten
        // blk: 1, ts: 604801
        // nft id               1   2   3   4   5
        // user points:         1 | 1 | 0 | 0 | 0
        // voting checkpoints:  1 | 1 | 0 | 0 | 0
        // global point epoch:  1
        escrow.lockPermanent(1);

        locked = escrow.locked(1);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);
        assertEq(escrow.slopeChanges(126403200), -7927447995);

        assertEq(escrow.userPointEpoch(1), 1);
        userPoint = escrow.userPointHistory(1, 1);
        assertEq(userPoint.bias, 0);
        assertEq(userPoint.slope, 0);
        assertEq(userPoint.ts, 604801);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, TOKEN_1);

        assertEq(escrow.epoch(), 1);
        globalPoint = escrow.pointHistory(1);
        assertEq(globalPoint.bias, 997260265926760005);
        assertEq(globalPoint.slope, 7927447995);
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);
        assertEq(escrow.permanentLockBalance(), TOKEN_1);

        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 1);
        checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 604801) + escrow.getPastVotes(address(owner2), 2, 604801)
        );

        // delegate 1 to 2 in same block as lock creation
        // no new voting checkpoints, overwritten
        // blk: 1, ts: 604801
        // nft id               1   2   3   4   5
        // user points:         1 | 1 | 0 | 0 | 0
        // voting checkpoints:  1 | 1 | 0 | 0 | 0
        // global point epoch:  1
        escrow.delegate(1, 2);

        // voting checkpoint for 1 overwritten
        assertEq(escrow.delegates(1), 2);
        assertEq(escrow.numCheckpoints(1), 1);
        checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 2);

        // voting checkpoint for 2 overwritten
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 1);
        checkpoint = escrow.checkpoints(2, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 604801) + escrow.getPastVotes(address(owner2), 2, 604801)
        );

        // increase amount of lock 1 in same block as delegate
        // no new voting checkpoints, overwritten
        // 1: +1 user point
        // +1 global point
        // blk: 1, ts: 604801
        // nft id               1   2   3   4   5
        // user points:         1 | 1 | 0 | 0 | 0
        // voting checkpoints:  1 | 1 | 0 | 0 | 0
        // global point epoch:  1
        escrow.increaseAmount(1, TOKEN_1 * 9);

        locked = escrow.locked(1);
        assertEq(convert(locked.amount), TOKEN_1 * 10);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);
        assertEq(escrow.slopeChanges(126403200), -7927447995);

        assertEq(escrow.userPointEpoch(1), 1);
        userPoint = escrow.userPointHistory(1, 1);
        assertEq(userPoint.bias, 0);
        assertEq(userPoint.slope, 0);
        assertEq(userPoint.ts, 604801);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, TOKEN_1 * 10);

        assertEq(escrow.epoch(), 1);
        globalPoint = escrow.pointHistory(1);
        assertEq(globalPoint.bias, 997260265926760005);
        assertEq(globalPoint.slope, 7927447995);
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 10);
        assertEq(escrow.permanentLockBalance(), TOKEN_1 * 10);

        // voting checkpoints unchanged for 1
        assertEq(escrow.delegates(1), 2);
        assertEq(escrow.numCheckpoints(1), 1);
        checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 2);

        // voting checkpoint for 2 overwritten
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 1);
        checkpoint = escrow.checkpoints(2, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 10);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 604801) + escrow.getPastVotes(address(owner2), 2, 604801)
        );

        // 1 dedelegates in same block as increase amount
        // no new voting checkpoints, overwritten
        // blk: 1, ts: 604801
        // nft id               1   2   3   4   5
        // user points:         1 | 1 | 0 | 0 | 0
        // voting checkpoints:  1 | 1 | 0 | 0 | 0
        // global point epoch:  1
        escrow.delegate(1, 0);

        // voting checkpoint overwritten for 1
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 1);
        checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // voting checkpoint overwritten for 2
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 1);
        checkpoint = escrow.checkpoints(2, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 604801) + escrow.getPastVotes(address(owner2), 2, 604801)
        );

        // 1 redelegates to 2 in same block as dedelegate
        // no new voting checkpoints, overwritten
        // blk: 1, ts: 604801
        // nft id               1   2   3   4   5
        // user points:         1 | 1 | 0 | 0 | 0
        // voting checkpoints:  1 | 1 | 0 | 0 | 0
        // global point epoch:  1
        escrow.delegate(1, 2);

        // voting checkpoint overwritten for 1
        assertEq(escrow.delegates(1), 2);
        assertEq(escrow.numCheckpoints(1), 1);
        checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 2);

        // voting checkpoint overwritten for 2
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 1);
        checkpoint = escrow.checkpoints(2, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 10);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 604801) + escrow.getPastVotes(address(owner2), 2, 604801)
        );

        skipAndRoll(1 days);

        // create lock 3 a day later
        // 3: +1 user point, +1 voting checkpoint
        // +1 global point
        // blk: 2, ts: 691201
        // nft id               1   2   3   4   5
        // user points:         1 | 1 | 1 | 0 | 0
        // voting checkpoints:  1 | 1 | 1 | 0 | 0
        // global point epoch:  2
        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 3
        vm.stopPrank();

        locked = escrow.locked(3);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 126403200);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(126403200), -7927447995 * 2);

        assertEq(escrow.userPointEpoch(3), 1);
        userPoint = escrow.userPointHistory(3, 1);
        assertEq(userPoint.bias, 996575334419992005); // (TOKEN_1 / MAXTIME) * (126403200 - 691201)
        assertEq(userPoint.slope, 7927447995); // TOKEN_1 / MAXTIME
        assertEq(userPoint.ts, 691201);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 2);
        globalPoint = escrow.pointHistory(2);
        assertEq(globalPoint.bias, 996575334419992005 * 2); // 1 has decayed to the same bias of 3
        assertEq(globalPoint.slope, 7927447995 * 2);
        assertEq(globalPoint.ts, 691201);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 10);

        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 1);
        checkpoint = escrow.checkpoints(3, 0);
        assertEq(checkpoint.fromTimestamp, 691201);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2) + escrow.balanceOfNFT(3));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 691201) +
                escrow.getPastVotes(address(owner2), 2, 691201) +
                escrow.getPastVotes(address(owner3), 3, 691201)
        );

        // permanent lock 2
        // 2: +1 user point
        // global point overwritten
        // blk: 2, ts: 691201
        // nft id               1   2   3   4   5
        // user points:         1 | 2 | 1 | 0 | 0
        // voting checkpoints:  1 | 1 | 1 | 0 | 0
        // global point epoch:  2
        vm.prank(address(owner2));
        escrow.lockPermanent(2);

        locked = escrow.locked(2);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);
        assertEq(escrow.slopeChanges(126403200), -7927447995);

        assertEq(escrow.userPointEpoch(2), 2);
        userPoint = escrow.userPointHistory(2, 2);
        assertEq(userPoint.bias, 0);
        assertEq(userPoint.slope, 0);
        assertEq(userPoint.ts, 691201);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1);

        assertEq(escrow.epoch(), 2);
        globalPoint = escrow.pointHistory(2);
        assertEq(globalPoint.bias, 996575334419992005);
        assertEq(globalPoint.slope, 7927447995);
        assertEq(globalPoint.ts, 691201);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 11);
        assertEq(escrow.permanentLockBalance(), TOKEN_1 * 11);

        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 1);
        checkpoint = escrow.checkpoints(2, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 10);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2) + escrow.balanceOfNFT(3));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 691201) +
                escrow.getPastVotes(address(owner2), 2, 691201) +
                escrow.getPastVotes(address(owner3), 3, 691201)
        );

        skipAndRoll(1);
        // 2 delegates to 3
        // 2: +1 voting checkpoint
        // 3: +1 voting checkpoint
        // blk: 3, ts: 691202
        // nft id               1   2   3   4   5
        // user points:         1 | 2 | 1 | 0 | 0
        // voting checkpoints:  1 | 2 | 2 | 0 | 0
        // global point epoch:  2
        vm.prank(address(owner2));
        escrow.delegate(2, 3);

        // check voting checkpoints for 2
        assertEq(escrow.delegates(2), 3);
        assertEq(escrow.numCheckpoints(2), 2);
        checkpoint = escrow.checkpoints(2, 1);
        assertEq(checkpoint.fromTimestamp, 691202);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 10);
        assertEq(checkpoint.delegatee, 3);

        // check voting checkpoints for 3
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 2);
        checkpoint = escrow.checkpoints(3, 1);
        assertEq(checkpoint.fromTimestamp, 691202);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.balanceOfNFT(2), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner2), 2, 691202), TOKEN_1 * 10);
        // 996575334419992005 - 7927447995 * 1 (bias - slope * ts delta)
        assertEq(escrow.balanceOfNFT(3), 996575326492544010);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2) + escrow.balanceOfNFT(3));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 691202) +
                escrow.getPastVotes(address(owner2), 2, 691202) +
                escrow.getPastVotes(address(owner3), 3, 691202)
        );

        skipAndRoll(1 hours);
        // depositFor into 2 by owner
        // 2: +1 user point
        // 3: +1 voting checkpoint
        // +1 global point
        // blk: 4, ts: 694802
        // nft id               1   2   3   4   5
        // user points:         1 | 3 | 1 | 0 | 0
        // voting checkpoints:  1 | 2 | 3 | 0 | 0
        // global point epoch:  3
        escrow.depositFor(2, TOKEN_1 * 4);

        locked = escrow.locked(2);
        assertEq(convert(locked.amount), TOKEN_1 * 5);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);
        assertEq(escrow.slopeChanges(126403200), -7927447995);

        assertEq(escrow.userPointEpoch(2), 3);
        userPoint = escrow.userPointHistory(2, 3);
        assertEq(userPoint.bias, 0);
        assertEq(userPoint.slope, 0);
        assertEq(userPoint.ts, 694802);
        assertEq(userPoint.blk, 4);
        assertEq(userPoint.permanent, TOKEN_1 * 5);

        assertEq(escrow.epoch(), 3);
        globalPoint = escrow.pointHistory(3);
        // 996575334419992005 - 7927447995 * 3601 (bias - slope * ts delta)
        assertEq(globalPoint.bias, 996546787679762010);
        assertEq(globalPoint.slope, 7927447995);
        assertEq(globalPoint.ts, 694802);
        assertEq(globalPoint.blk, 4);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 15);
        assertEq(escrow.permanentLockBalance(), TOKEN_1 * 15);

        // voting checkpoint for 2 unchanged
        assertEq(escrow.delegates(2), 3);
        assertEq(escrow.numCheckpoints(2), 2);
        checkpoint = escrow.checkpoints(2, 1);
        assertEq(checkpoint.fromTimestamp, 691202);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 10);
        assertEq(checkpoint.delegatee, 3);

        // new voting checkpoint for 3
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 3);
        checkpoint = escrow.checkpoints(3, 2);
        assertEq(checkpoint.fromTimestamp, 694802);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 5);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2) + escrow.balanceOfNFT(3));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 694802) +
                escrow.getPastVotes(address(owner2), 2, 694802) +
                escrow.getPastVotes(address(owner3), 3, 694802)
        );

        skipAndRoll(1 weeks);
        // 1 delegates to 3
        // 1: +1 voting checkpoint (delegate to 3)
        // 2: +1 voting checkpoint (delegated balance decreased)
        // 3: +1 voting checkpoint (delegated balance increased)
        // +2 global points (one for last epoch, one for current action)
        // blk: 5, ts: 1299602
        // nft id               1   2   3   4   5
        // user points:         1 | 3 | 1 | 0 | 0
        // voting checkpoints:  2 | 3 | 4 | 0 | 0
        // global point epoch:  3
        escrow.delegate(1, 3);

        // new voting checkpoint for 1, delegate to 3
        assertEq(escrow.delegates(1), 3);
        assertEq(escrow.numCheckpoints(1), 2);
        checkpoint = escrow.checkpoints(1, 1);
        assertEq(checkpoint.fromTimestamp, 1299602);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 3);

        // new voting checkpoint for 2, delegate balance decreased
        assertEq(escrow.delegates(2), 3);
        assertEq(escrow.numCheckpoints(2), 3);
        checkpoint = escrow.checkpoints(2, 2);
        assertEq(checkpoint.fromTimestamp, 1299602);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 3);

        // new voting checkpoint for 3, delegate balance increased
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 4);
        checkpoint = escrow.checkpoints(3, 3);
        assertEq(checkpoint.fromTimestamp, 1299602);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 15);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2) + escrow.balanceOfNFT(3));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 1299602) +
                escrow.getPastVotes(address(owner2), 2, 1299602) +
                escrow.getPastVotes(address(owner3), 3, 1299602)
        );

        // 1 unlocks permanent lock in same block as delegate
        // 1: +1 user point, voting checkpoint overwritten (dedelegate)
        // 3: voting checkpoint overwritten (dedelegate)
        // +2 global points (one for last epoch, one for current action)
        // blk: 5, ts: 1299602
        // nft id               1   2   3   4   5
        // user points:         2 | 3 | 1 | 0 | 0
        // voting checkpoints:  2 | 3 | 4 | 0 | 0
        // global point epoch:  5
        escrow.unlockPermanent(1);

        locked = escrow.locked(1);
        assertEq(convert(locked.amount), TOKEN_1 * 10);
        assertEq(locked.end, 127008000);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(126403200), -7927447995);
        assertEq(escrow.slopeChanges(127008000), -79274479959);

        assertEq(escrow.userPointEpoch(1), 2);
        userPoint = escrow.userPointHistory(1, 2);
        assertEq(userPoint.bias, 9965467877928995682); // (TOKEN_1 * 10 / MAXTIME) * (127008000 - 1299602)
        assertEq(userPoint.slope, 79274479959); // TOKEN_1 * 10 / MAXTIME
        assertEq(userPoint.ts, 1299602);
        assertEq(userPoint.blk, 5);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 5);
        globalPoint = escrow.pointHistory(5);
        // 996546787679762010 - 7927447995 * 604800 = 991752267132386010 (decay 3 by another week)
        assertEq(globalPoint.bias, 9965467877928995682 + 991752267132386010); // bias of 1 + bias of 3
        assertEq(globalPoint.slope, 79274479959 + 7927447995); // slope of 1 + slope of 3
        assertEq(globalPoint.ts, 1299602);
        assertEq(globalPoint.blk, 5);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 5);
        assertEq(escrow.permanentLockBalance(), TOKEN_1 * 5);

        // overwrite voting checkpoint for 1
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 2);
        checkpoint = escrow.checkpoints(1, 1);
        assertEq(checkpoint.fromTimestamp, 1299602);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // overwrite voting checkpoint for 3
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 4);
        checkpoint = escrow.checkpoints(3, 3);
        assertEq(checkpoint.fromTimestamp, 1299602);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 5);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2) + escrow.balanceOfNFT(3));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner), 1, 1299602) +
                escrow.getPastVotes(address(owner2), 2, 1299602) +
                escrow.getPastVotes(address(owner3), 3, 1299602)
        );

        for (uint256 i = 0; i < 208; i++) {
            skipAndRoll(1 weeks);
            assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2) + escrow.balanceOfNFT(3));
            assertEq(
                escrow.totalSupply(),
                escrow.getPastVotes(address(owner), 1, block.timestamp) +
                    escrow.getPastVotes(address(owner2), 2, block.timestamp) +
                    escrow.getPastVotes(address(owner3), 3, block.timestamp)
            );
        }
        // 1 & 3 have expired
        // withdraw from 3 (i.e. burn)
        // 3: +1 user point, +1 voting checkpoint (burn)
        // + 209 global points (one per week, + one for action)
        // delegatedBalance on 3 still exists as 2 is still delegating to 3
        // blk: 213, ts: 127098002
        // nft id               1   2   3   4   5
        // user points:         2 | 3 | 2 | 0 | 0
        // voting checkpoints:  2 | 3 | 5 | 0 | 0
        // global point epoch:  214
        uint256 balance = AERO.balanceOf(address(owner3));
        vm.prank(address(owner3));
        escrow.withdraw(3);
        assertEq(AERO.balanceOf(address(owner3)) - balance, TOKEN_1);

        locked = escrow.locked(3);
        assertEq(convert(locked.amount), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);
        // slope changes not updated on burn, already in the past
        assertEq(escrow.slopeChanges(126403200), -7927447995);
        assertEq(escrow.slopeChanges(127008000), -79274479959);

        assertEq(escrow.userPointEpoch(3), 2);
        userPoint = escrow.userPointHistory(3, 2);
        assertEq(userPoint.bias, 0);
        assertEq(userPoint.slope, 0);
        assertEq(userPoint.ts, 127098002);
        assertEq(userPoint.blk, 213);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 214);
        globalPoint = escrow.pointHistory(214);
        assertEq(globalPoint.bias, 0);
        assertEq(globalPoint.slope, 0);
        assertEq(globalPoint.ts, 127098002);
        assertEq(globalPoint.blk, 213);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 5);

        // voting checkpoint for 2 unchanged
        assertEq(escrow.delegates(2), 3);
        assertEq(escrow.numCheckpoints(2), 3);
        checkpoint = escrow.checkpoints(2, 2);
        assertEq(checkpoint.fromTimestamp, 1299602);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 3);

        // new voting checkpoint for 3
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 5);
        checkpoint = escrow.checkpoints(3, 4);
        assertEq(checkpoint.fromTimestamp, 127098002);
        assertEq(checkpoint.owner, address(0));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 5);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.balanceOfNFT(1), 0);
        assertEq(escrow.balanceOfNFT(3), 0);
        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(1) + escrow.balanceOfNFT(2) + escrow.balanceOfNFT(3));
        assertEq(escrow.totalSupply(), TOKEN_1 * 5); // supply is from 2, but is delegated to 3 which has been burned
        assertEq(escrow.getPastVotes(address(owner), 1, 127098002), 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 127098002), 0);
        assertEq(escrow.getPastVotes(address(owner3), 3, 127098002), 0); // getVotes is 0 for owner3 as owner is now address(0)

        skipAndRoll(1);
        // 2 splits to 4 and 5
        // new user point created for 2, 4, 5
        // 1 global points created, overwritten twice for 4 and 5
        // new voting checkpoint for 2 (as burn)
        // new voting checkpoint for burned delegatee 3 (delegated balance decreased)
        // blk: 214, ts: 127098003
        // nft id               1   2   3   4   5
        // user points:         3 | 4 | 2 | 1 | 1
        // voting checkpoints:  2 | 4 | 5 | 1 | 1
        // global point epoch:  215
        escrow.toggleSplit(address(0), true);
        vm.prank(address(owner2));
        escrow.split(2, TOKEN_1);

        // burned nft
        locked = escrow.locked(2);
        assertEq(convert(locked.amount), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(2), 4);
        userPoint = escrow.userPointHistory(2, 4);
        assertEq(userPoint.bias, 0);
        assertEq(userPoint.slope, 0);
        assertEq(userPoint.ts, 127098003);
        assertEq(userPoint.blk, 214);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 215);
        globalPoint = escrow.pointHistory(215);
        assertEq(globalPoint.bias, 0);
        assertEq(globalPoint.slope, 0);
        assertEq(globalPoint.ts, 127098003);
        assertEq(globalPoint.blk, 214);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 5);
        assertEq(escrow.permanentLockBalance(), TOKEN_1 * 5);

        // voting checkpoint for 2 created for burn
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 4);
        checkpoint = escrow.checkpoints(2, 3);
        assertEq(checkpoint.fromTimestamp, 127098003);
        assertEq(checkpoint.owner, address(0));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // voting checkpoint for 3 created for dedelegate
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 6);
        checkpoint = escrow.checkpoints(3, 5);
        assertEq(checkpoint.fromTimestamp, 127098003);
        assertEq(checkpoint.owner, address(0));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // new nft points (4)
        locked = escrow.locked(4);
        assertEq(convert(locked.amount), TOKEN_1 * 4);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(4), 1);
        userPoint = escrow.userPointHistory(4, 1);
        assertEq(userPoint.bias, 0);
        assertEq(userPoint.slope, 0);
        assertEq(userPoint.ts, 127098003);
        assertEq(userPoint.blk, 214);
        assertEq(userPoint.permanent, TOKEN_1 * 4);

        // new nft points (5)
        locked = escrow.locked(5);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(5), 1);
        userPoint = escrow.userPointHistory(5, 1);
        assertEq(userPoint.bias, 0);
        assertEq(userPoint.slope, 0);
        assertEq(userPoint.ts, 127098003);
        assertEq(userPoint.blk, 214);
        assertEq(userPoint.permanent, TOKEN_1);

        assertEq(escrow.totalSupply(), escrow.balanceOfNFT(4) + escrow.balanceOfNFT(5));
        assertEq(
            escrow.totalSupply(),
            escrow.getPastVotes(address(owner2), 4, 127098003) + escrow.getPastVotes(address(owner2), 5, 127098003)
        );

        // check historical balance, votes and supply
        // net state at end of 604801:
        // 1 => create lock with amount TOKEN_1, lock permanent and increase amount by TOKEN_1 * 9
        // 2 => create lock with amount TOKEN_1
        // 1 delegated to 2
        assertEq(escrow.balanceOfNFTAt(1, 604800), 0);
        assertEq(escrow.balanceOfNFTAt(1, 604801), TOKEN_1 * 10);
        assertEq(escrow.balanceOfNFTAt(1, 604800), 0);
        assertEq(escrow.balanceOfNFTAt(1, 604801), TOKEN_1 * 10);
        assertEq(escrow.balanceOfNFTAt(2, 604800), 0);
        assertEq(escrow.balanceOfNFTAt(2, 604801), 997260265926760005);
        assertEq(escrow.balanceOfNFTAt(2, 604800), 0);
        assertEq(escrow.balanceOfNFTAt(2, 604801), 997260265926760005);

        assertEq(escrow.getPastVotes(address(owner), 1, 604800), 0);
        assertEq(escrow.getPastVotes(address(owner), 1, 604801), 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604800), 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604801), TOKEN_1 * 10 + 997260265926760005);
        assertEq(escrow.getPastTotalSupply(604800), 0);
        assertEq(escrow.getPastTotalSupply(604801), TOKEN_1 * 10 + 997260265926760005);

        // net state at end of 691201:
        // 3 => create lock with amount TOKEN_1
        // 2 => lock permanent
        assertEq(escrow.balanceOfNFTAt(2, 691200), 996575342347440000);
        assertEq(escrow.balanceOfNFTAt(2, 691201), TOKEN_1);
        assertEq(escrow.balanceOfNFTAt(3, 691200), 0);
        assertEq(escrow.balanceOfNFTAt(3, 691201), 996575334419992005);

        assertEq(escrow.getPastVotes(address(owner2), 2, 691200), TOKEN_1 * 10 + 996575342347440000); // 1 delegating to 2
        assertEq(escrow.getPastVotes(address(owner2), 2, 691201), TOKEN_1 * 11); // 2 locked permanent
        assertEq(escrow.getPastVotes(address(owner3), 3, 691200), 0);
        assertEq(escrow.getPastVotes(address(owner3), 3, 691201), 996575334419992005);

        assertEq(escrow.getPastTotalSupply(691200), TOKEN_1 * 10 + 996575342347440000);
        assertEq(escrow.getPastTotalSupply(691201), TOKEN_1 * 11 + 996575334419992005);

        // net state at end of 691202:
        // 2 delegates to 3
        assertEq(escrow.balanceOfNFTAt(2, 691202), TOKEN_1);
        assertEq(escrow.balanceOfNFTAt(3, 691202), 996575326492544010);

        assertEq(escrow.getPastVotes(address(owner2), 2, 691202), TOKEN_1 * 10); // 1 delegating to 2
        assertEq(escrow.getPastVotes(address(owner3), 3, 691202), TOKEN_1 + 996575326492544010); //2 delegating to 3

        assertEq(escrow.getPastTotalSupply(691202), TOKEN_1 * 11 + 996575326492544010);

        // net state at end of 694802:
        // 2 => deposit for TOKEN_1 * 4
        assertEq(escrow.balanceOfNFTAt(2, 694802), TOKEN_1 * 5);
        assertEq(escrow.balanceOfNFTAt(3, 694802), 996546787679762010);

        assertEq(escrow.getPastVotes(address(owner2), 2, 694802), TOKEN_1 * 10); // 1 delegating to 2
        assertEq(escrow.getPastVotes(address(owner3), 3, 694802), TOKEN_1 * 5 + 996546787679762010); // 2 delegating to 3

        assertEq(escrow.getPastTotalSupply(694802), TOKEN_1 * 15 + 996546787679762010);

        // net state at end of 1299602:
        // 1 unlocks permanent (also dedelegates from 2)
        assertEq(escrow.balanceOfNFTAt(1, 1299602), 9965467877928995682);
        assertEq(escrow.balanceOfNFTAt(2, 1299602), TOKEN_1 * 5);
        assertEq(escrow.balanceOfNFTAt(3, 1299602), 991752267132386010);

        assertEq(escrow.getPastVotes(address(owner), 1, 1299601), 0);
        assertEq(escrow.getPastVotes(address(owner), 1, 1299602), 9965467877928995682);
        assertEq(escrow.getPastVotes(address(owner2), 2, 1299601), TOKEN_1 * 10); // 1 delegating to 2
        assertEq(escrow.getPastVotes(address(owner2), 2, 1299602), 0);
        assertEq(escrow.getPastVotes(address(owner3), 3, 1299601), TOKEN_1 * 5 + 991752275059834005); // 2 delegating to 3
        assertEq(escrow.getPastVotes(address(owner3), 3, 1299602), TOKEN_1 * 5 + 991752267132386010); // 2 delegating to 3

        assertEq(escrow.getPastTotalSupply(1299602), TOKEN_1 * 5 + 9965467877928995682 + 991752267132386010);

        // net state at end of 127098002:
        // 1, 3 have expired
        // 3 is withdrawn
        assertEq(escrow.balanceOfNFTAt(1, 127098002), 0);
        assertEq(escrow.balanceOfNFTAt(2, 127098002), TOKEN_1 * 5);
        assertEq(escrow.balanceOfNFTAt(3, 127098002), 0);

        assertEq(escrow.getPastVotes(address(owner), 1, 127098001), 0);
        assertEq(escrow.getPastVotes(address(owner), 1, 127098002), 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 127098001), 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 127098002), 0);
        assertEq(escrow.getPastVotes(address(owner3), 3, 127098001), TOKEN_1 * 5); // 2 delegating to 3
        assertEq(escrow.getPastVotes(address(owner3), 3, 127098002), 0); // 3 is burned

        assertEq(escrow.getPastTotalSupply(127098002), TOKEN_1 * 5);
    }
}
