// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./ExtendedBaseTest.sol";

contract VotingEscrowTest is ExtendedBaseTest {
    function testVotingEscrowFlow() public {
        // starting timestamp: 604801
        IVotingEscrow.LockedBalance memory locked;
        IVotingEscrow.UserPoint memory userPoint;
        IVotingEscrow.GlobalPoint memory globalPoint;

        // create lock 1 and check state
        // 1: +1 user point
        // +1 global point
        // blk: 1, ts: 604801
        // nft id               1
        // user points:         1
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
        assertEq(globalPoint.bias, 997260265926760005);
        assertEq(globalPoint.slope, 7927447995);
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, 0);

        // update global checkpoint, overwritten
        // blk: 1, ts: 604801
        // nft id               1
        // user points:         1
        // global point epoch:  1
        escrow.checkpoint();

        assertEq(escrow.epoch(), 1);
        globalPoint = escrow.pointHistory(1);
        assertEq(globalPoint.bias, 997260265926760005); // (TOKEN_1 / MAXTIME) * (127008000 - 1209600)
        assertEq(globalPoint.slope, 7927447995); // TOKEN_1 / MAXTIME
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, 0);
        globalPoint = escrow.pointHistory(2);

        // user increases amount in same block
        // user point overwritten
        // global point overwritten
        // blk: 1, ts: 604801
        // nft id               1
        // user points:         1
        // global point epoch:  1
        escrow.increaseAmount(1, TOKEN_1);

        locked = escrow.locked(1);
        assertEq(convert(locked.amount), TOKEN_1 * 2);
        assertEq(locked.end, 126403200);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(126403200), -15854895991);

        assertEq(escrow.userPointEpoch(1), 1);
        userPoint = escrow.userPointHistory(1, 1);
        assertEq(userPoint.bias, 1994520531979318409); // (TOKEN_1 / MAXTIME) * 2 * (126403200 - 604801)
        assertEq(userPoint.slope, 15854895991);
        assertEq(userPoint.ts, 604801);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 1);
        globalPoint = escrow.pointHistory(1);
        assertEq(globalPoint.bias, 1994520531979318409); // (TOKEN_1 / MAXTIME) * 2 * (126403200 - 604801)
        assertEq(globalPoint.slope, 15854895991);
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, 0);

        skipAndRoll(1 hours);
        // increase amount in different block
        // 1: +1 user point
        // +1 global point
        // blk: 2, ts: 608401
        // nft id               1
        // user points:         2
        // global point epoch:  2
        escrow.increaseAmount(1, TOKEN_1);

        locked = escrow.locked(1);
        assertEq(convert(locked.amount), TOKEN_1 * 3);
        assertEq(locked.end, 126403200);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(126403200), -23782343987);

        assertEq(escrow.userPointEpoch(1), 2);
        // check prior point
        userPoint = escrow.userPointHistory(1, 1);
        assertEq(userPoint.bias, 1994520531979318409);
        assertEq(userPoint.slope, 15854895991);
        assertEq(userPoint.ts, 604801);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, 0);
        userPoint = escrow.userPointHistory(1, 2);
        assertEq(userPoint.bias, 2991695181593523613); // slope * (126403200 - 608401)
        assertEq(userPoint.slope, 23782343987);
        assertEq(userPoint.ts, 608401);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 2);
        globalPoint = escrow.pointHistory(1);
        assertEq(globalPoint.bias, 1994520531979318409);
        assertEq(globalPoint.slope, 15854895991);
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, 0);
        globalPoint = escrow.pointHistory(2);
        assertEq(globalPoint.bias, 2991695181593523613);
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 608401);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, 0);

        skipAndRoll(1 weeks); // blk: 3
        skipAndRoll(1 weeks); // blk: 4
        vm.roll(10); // blk: 10 (at least 1 blk per epoch)

        // two weeks have passed
        // expect checkpoint to write three new global points, once at start of each epoch
        // and once more at the current timestamp
        // +3 global points
        // blk: 10, ts: 1814400
        // nft id               1
        // user points:         2
        // global point epoch:  5
        escrow.checkpoint();

        assertEq(escrow.epoch(), 5);
        // last point preserved
        globalPoint = escrow.pointHistory(2);
        assertEq(globalPoint.bias, 2991695181593523613);
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 608401);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, 0);
        // when checkpoints are skipped during epochs, escrow attempts to
        // smooth the block numbers in the checkpoints across the epochs
        // based on the total time elapsed since the last checkpoint
        // and the total number of blocks that have occurred since the last checkpoint
        globalPoint = escrow.pointHistory(3);
        assertEq(globalPoint.bias, 2977397260170883200);
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 1209600);
        assertEq(globalPoint.blk, 5);
        assertEq(globalPoint.permanentLockBalance, 0);
        globalPoint = escrow.pointHistory(4);
        assertEq(globalPoint.bias, 2963013698527545600);
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 1814400);
        assertEq(globalPoint.blk, 9);
        assertEq(globalPoint.permanentLockBalance, 0);
        globalPoint = escrow.pointHistory(5);
        assertEq(globalPoint.bias, 2962928058306848413);
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 1818001);
        assertEq(globalPoint.blk, 10);
        assertEq(globalPoint.permanentLockBalance, 0);

        // extend locktime in same block
        // 1: +1 user point
        // global point overwritten
        // blk: 10, ts: 1814400
        // nft id               1
        // user points:         3
        // global point epoch:  5
        escrow.increaseUnlockTime(1, MAXTIME);

        locked = escrow.locked(1);
        assertEq(convert(locked.amount), TOKEN_1 * 3);
        assertEq(locked.end, 127612800);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(126403200), 0);
        assertEq(escrow.slopeChanges(127612800), -23782343987);

        assertEq(escrow.userPointEpoch(1), 3);
        // check prior point
        userPoint = escrow.userPointHistory(1, 2);
        assertEq(userPoint.bias, 2991695181593523613); // slope * (127612800 - 1818001)
        assertEq(userPoint.slope, 23782343987);
        assertEq(userPoint.ts, 608401);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);
        userPoint = escrow.userPointHistory(1, 3);
        assertEq(userPoint.bias, 2991695181593523613); // slope * (127612800 - 1818001)
        assertEq(userPoint.slope, 23782343987);
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 10);
        assertEq(userPoint.permanent, 0);

        assertEq(escrow.epoch(), 5);
        globalPoint = escrow.pointHistory(4);
        assertEq(globalPoint.bias, 2963013698527545600);
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 1814400);
        assertEq(globalPoint.blk, 9);
        assertEq(globalPoint.permanentLockBalance, 0);
        globalPoint = escrow.pointHistory(5);
        assertEq(globalPoint.bias, 2991695181593523613);
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 1818001);
        assertEq(globalPoint.blk, 10);
        assertEq(globalPoint.permanentLockBalance, 0);

        skipToNextEpoch(0);
        // checkpoint at start of next epoch
        // +1 global point only, as checkpoint occurs on flip
        // blk: 11, ts: 2419200
        // nft id               1
        // user points:         3
        // global point epoch:  6
        escrow.checkpoint();

        assertEq(escrow.epoch(), 6);
        globalPoint = escrow.pointHistory(5);
        assertEq(globalPoint.bias, 2991695181593523613);
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 1818001);
        assertEq(globalPoint.blk, 10);
        assertEq(globalPoint.permanentLockBalance, 0);
        globalPoint = escrow.pointHistory(6);
        assertEq(globalPoint.bias, 2977397260170883200); // slope * (127612800 - 2419200)
        assertEq(globalPoint.slope, 23782343987);
        assertEq(globalPoint.ts, 2419200);
        assertEq(globalPoint.blk, 11);
        assertEq(globalPoint.permanentLockBalance, 0);
    }
}
