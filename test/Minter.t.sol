// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract MinterTest is BaseTest {
    using stdStorage for StdStorage;
    uint256 tokenId;

    event AcceptTeam(address indexed _newTeam);
    event Nudge(uint256 indexed _period, uint256 _oldRate, uint256 _newRate);

    function _setUp() public override {
        AERO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);

        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        skip(1 hours);
        voter.vote(tokenId, pools, weights);
    }

    function testMinterDeploy() public {
        assertEq(minter.MAXIMUM_TAIL_RATE(), 100); // 1%
        assertEq(minter.MINIMUM_TAIL_RATE(), 1); // .01%
        assertEq(minter.WEEKLY_DECAY(), 9_900);
        assertEq(minter.WEEKLY_GROWTH(), 10_300);
        assertEq(minter.TAIL_START(), 8_969_150 * 1e18);
        assertEq(minter.weekly(), 10_000_000 * 1e18);
        assertEq(minter.tailEmissionRate(), 67); // .67%
        assertEq(minter.activePeriod(), 604800);
        assertEq(minter.team(), address(owner));
        assertEq(minter.teamRate(), 500); // 5%
        assertEq(minter.MAXIMUM_TEAM_RATE(), 500); // 5%
        assertEq(minter.pendingTeam(), address(0));
        assertEq(minter.epochCount(), 0);
        assertFalse(minter.initialized());
    }

    function testWeeklyEmissionGrowsFirst14WeeksThenFlipsAndDecays() public {
        minter.updatePeriod();
        assertEq(minter.weekly(), 10 * TOKEN_1M); // 10M
        assertEq(minter.epochCount(), 0);

        //epoch 1
        skipToNextEpoch(1);
        minter.updatePeriod();
        assertApproxEqAbs(minter.weekly(), 10_300_000 * TOKEN_1, TOKEN_1);
        assertEq(minter.epochCount(), 1);

        //epoch 2
        skipToNextEpoch(1);
        minter.updatePeriod();
        assertApproxEqAbs(minter.weekly(), 10_609_000 * TOKEN_1, TOKEN_1);
        assertEq(minter.epochCount(), 2);

        for (uint256 i = 0; i < 10; i++) {
            skipToNextEpoch(1);
            minter.updatePeriod();
        }

        //epoch 13
        skipToNextEpoch(1);
        minter.updatePeriod();
        assertApproxEqAbs(minter.weekly(), 14_685_337 * TOKEN_1, TOKEN_1);
        assertEq(minter.epochCount(), 13);

        //epoch 14
        skipToNextEpoch(1);
        minter.updatePeriod();
        assertApproxEqAbs(minter.weekly(), 15_125_897 * TOKEN_1, TOKEN_1);
        assertEq(minter.epochCount(), 14);

        //emissions grow for 14 weeks
        //in week 15, weekly emission flips and decays

        //epoch 15
        skipToNextEpoch(1);
        minter.updatePeriod();
        assertApproxEqAbs(minter.weekly(), 14_974_638 * TOKEN_1, TOKEN_1);
        assertEq(minter.epochCount(), 15);

        //epoch 16
        skipToNextEpoch(1);
        minter.updatePeriod();
        assertApproxEqAbs(minter.weekly(), 14_824_892 * TOKEN_1, TOKEN_1);
        assertEq(minter.epochCount(), 16);

        //epoch 17
        skipToNextEpoch(1);
        minter.updatePeriod();
        assertApproxEqAbs(minter.weekly(), 14_676_643 * TOKEN_1, TOKEN_1);
        assertEq(minter.epochCount(), 17);
    }

    function testTailEmissionWhenWeeklyEmissionDecaysBelowTailStart() public {
        skipToNextEpoch(1);
        assertEq(AERO.balanceOf(address(voter)), 0);

        // 9_059_747 * 1e18 ~= approximate weekly value after 67 epochs
        // (last epoch prior to tail emissions kicking in)
        uint256 weekly = 9_059_747 * 1e18;
        stdstore.target(address(minter)).sig("weekly()").checked_write(weekly);
        stdstore.target(address(minter)).sig("epochCount()").checked_write(67);

        skipToNextEpoch(1);
        minter.updatePeriod();
        // epoch threshold for tail start
        assertApproxEqAbs(minter.weekly(), 8_969_149 * TOKEN_1, TOKEN_1);
        assertApproxEqRel(AERO.balanceOf(address(voter)), 9_059_747 * TOKEN_1, 1e12);
        voter.distribute(0, voter.length());

        skipToNextEpoch(1);
        // totalSupply ~= 65_429_708 * 1e18
        // expected mint = totalSupply * .67% ~= 8_969_149
        minter.updatePeriod();
        assertApproxEqAbs(AERO.balanceOf(address(voter)), 430_810 * 1e18, TOKEN_1);
        assertLt(minter.weekly(), minter.TAIL_START());
    }

    function testCannotNudgeIfNotInTailEmissionsYet() public {
        vm.prank(address(epochGovernor));
        vm.expectRevert(IMinter.TailEmissionsInactive.selector);
        minter.nudge();
    }

    function testCannotNudgeIfNotEpochGovernor() public {
        /// put in tail emission schedule
        stdstore.target(address(minter)).sig("weekly()").checked_write(8_969_149 * 1e18);

        vm.prank(address(owner2));
        vm.expectRevert(IMinter.NotEpochGovernor.selector);
        minter.nudge();
    }

    function testCannotNudgeIfAlreadyNudged() public {
        /// put in tail emission schedule
        stdstore.target(address(minter)).sig("weekly()").checked_write(8_969_148 * 1e18);
        assertFalse(minter.proposals(604800));

        vm.prank(address(epochGovernor));
        minter.nudge();
        assertTrue(minter.proposals(604800));
        skip(1);

        vm.expectRevert(IMinter.AlreadyNudged.selector);
        vm.prank(address(epochGovernor));
        minter.nudge();
    }

    function testNudgeWhenAtUpperBoundary() public {
        stdstore.target(address(minter)).sig("weekly()").checked_write(8_969_149 * 1e18);
        stdstore.target(address(minter)).sig("tailEmissionRate()").checked_write(100);
        /// note: see IGovernor.ProposalState for enum numbering
        stdstore.target(address(epochGovernor)).sig("result()").checked_write(4); // nudge up
        assertEq(minter.tailEmissionRate(), 100);

        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 100); // nudge above at maximum does nothing

        skipToNextEpoch(1);
        minter.updatePeriod();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(3); // nudge down

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1209600, 100, 99);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 99);
        assertTrue(minter.proposals(1209600));

        skipToNextEpoch(1);
        minter.updatePeriod();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(6); // no nudge

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1814400, 99, 99);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 99);
        assertTrue(minter.proposals(1814400));
    }

    function testNudgeWhenAtLowerBoundary() public {
        stdstore.target(address(minter)).sig("weekly()").checked_write(8_969_149 * 1e18);
        stdstore.target(address(minter)).sig("tailEmissionRate()").checked_write(1);
        /// note: see IGovernor.ProposalState for enum numbering
        stdstore.target(address(epochGovernor)).sig("result()").checked_write(3); // nudge down
        assertEq(minter.tailEmissionRate(), 1);

        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 1); // nudge below at minimum does nothing

        skipToNextEpoch(1);
        minter.updatePeriod();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(4); // nudge up

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1209600, 1, 2);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 2);
        assertTrue(minter.proposals(1209600));

        skipToNextEpoch(1);
        minter.updatePeriod();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(6); // no nudge

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1814400, 2, 2);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 2);
        assertTrue(minter.proposals(1814400));
    }

    function testNudge() public {
        stdstore.target(address(minter)).sig("weekly()").checked_write(8_969_149 * 1e18);
        /// note: see IGovernor.ProposalState for enum numbering
        stdstore.target(address(epochGovernor)).sig("result()").checked_write(4); // nudge up
        assertEq(minter.tailEmissionRate(), 67);

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(604800, 67, 68);
        vm.prank(address(epochGovernor));
        minter.nudge();
        assertEq(minter.tailEmissionRate(), 68);
        assertTrue(minter.proposals(604800));

        skipToNextEpoch(1);
        minter.updatePeriod();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(3); // nudge down

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1209600, 68, 67);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 67);
        assertTrue(minter.proposals(1209600));

        skipToNextEpoch(1);
        minter.updatePeriod();

        stdstore.target(address(epochGovernor)).sig("result()").checked_write(6); // no nudge

        vm.expectEmit(true, false, false, true, address(minter));
        emit Nudge(1814400, 67, 67);
        vm.prank(address(epochGovernor));
        minter.nudge();

        assertEq(minter.tailEmissionRate(), 67);
        assertTrue(minter.proposals(1814400));
    }

    function testMinterWeeklyDistribute() public {
        minter.updatePeriod();
        assertEq(minter.weekly(), 10 * TOKEN_1M); // 10M

        uint256 pre = AERO.balanceOf(address(voter));
        skipToNextEpoch(1);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 4999991534325080005726385);
        // emissions decay by 1% after one epoch
        uint256 post = AERO.balanceOf(address(voter));
        assertEq(post - pre, (10 * TOKEN_1M));
        assertEq(minter.weekly(), ((10 * TOKEN_1M) * 103) / 100);

        pre = post;
        skipToNextEpoch(1);
        vm.roll(block.number + 1);
        minter.updatePeriod();
        post = AERO.balanceOf(address(voter));

        // check rebase accumulated
        assertEq(distributor.claimable(1), 10149991131702758598187944);
        distributor.claim(1);
        assertEq(distributor.claimable(1), 0);

        assertEq(post - pre, (10 * TOKEN_1M * 103) / 100);
        assertEq(minter.weekly(), (10 * TOKEN_1M * 103 * 103) / 100 / 100);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.updatePeriod();

        distributor.claim(1);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.updatePeriod();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        distributor.claimMany(tokenIds);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.updatePeriod();
        distributor.claim(1);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.updatePeriod();
        distributor.claimMany(tokenIds);

        skip(1 weeks);
        vm.roll(block.number + 1);
        minter.updatePeriod();
        distributor.claim(1);
    }

    function testSetTeam() public {
        address team = minter.team();
        address newTeam = address(owner2);

        assertEq(minter.pendingTeam(), address(0));
        vm.prank(team);
        minter.setTeam(newTeam);
        assertEq(minter.team(), team);
        assertEq(minter.pendingTeam(), newTeam);
    }

    function testAcceptTeam() public {
        address newTeam = address(owner2);
        stdstore.target(address(minter)).sig("pendingTeam()").checked_write(newTeam);

        vm.prank(newTeam);
        vm.expectEmit(true, false, false, false, address(minter));
        emit AcceptTeam(newTeam);
        minter.acceptTeam();
        assertEq(minter.pendingTeam(), address(0));
        assertEq(minter.team(), newTeam);
    }

    function testSetRate() public {
        uint256 oldRate = 500;
        uint256 newRate = 400;
        assertEq(minter.teamRate(), oldRate);

        vm.prank(minter.team());
        minter.setTeamRate(newRate);
        assertEq(minter.teamRate(), newRate);
    }

    function testCannotSetTeamIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(IMinter.NotTeam.selector);
        minter.setTeam(address(owner2));
    }

    function testCannotSetTeamIfZeroAddress() public {
        vm.prank(address(owner));
        vm.expectRevert(IMinter.ZeroAddress.selector);
        minter.setTeam(address(0));
    }

    function testCannotAcceptTeamIfNotPending() public {
        vm.prank(address(owner));
        minter.setTeam(address(owner2));

        vm.prank(address(owner3));
        vm.expectRevert(IMinter.NotPendingTeam.selector);
        minter.acceptTeam();
    }

    function testCannotSetRateIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(IMinter.NotTeam.selector);
        minter.setTeamRate(400);
    }

    function testCannotSetRateTooHigh() public {
        uint256 maxRate = minter.MAXIMUM_TEAM_RATE();
        vm.prank(address(owner));
        vm.expectRevert(IMinter.RateTooHigh.selector);
        minter.setTeamRate(maxRate + 1);
    }
}
