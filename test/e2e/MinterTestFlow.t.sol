// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./ExtendedBaseTest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MinterTestFlow is ExtendedBaseTest {
    event Mint(address indexed _sender, uint256 _weekly, uint256 _circulating_supply, bool indexed _tail);

    function testMinterRebaseFlow() public {
        /// epoch 0
        minter.updatePeriod();
        assertEq(AERO.balanceOf(address(voter)), 0);

        AERO.approve(address(escrow), TOKEN_100K);
        escrow.createLock(TOKEN_100K, MAXTIME); // 1

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_100K);
        escrow.createLock(TOKEN_100K, MAXTIME); // 2
        vm.stopPrank();

        assertEq(distributor.claimable(1), 0);
        assertEq(distributor.claimable(2), 0);

        skip(1 hours + 1);

        // equal votes for both pools
        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;
        voter.vote(1, pools, weights);
        vm.prank(address(owner2));
        voter.vote(2, pools, weights);
        skipAndRoll(1);

        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);

        /// epoch 1
        skipToNextEpoch(2 days); // gauge distributions spread out over 5 days

        /// 10000000000000000000000000
        uint256 expectedMint = _expectedMintAfter(1);
        vm.expectEmit(true, true, false, false, address(minter));
        emit Mint(address(owner), expectedMint, 0, false);
        minter.updatePeriod();
        assertEq(AERO.balanceOf(address(voter)), expectedMint);

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        uint256 epochStart = _getEpochStart(block.timestamp);
        assertEq(AERO.allowance(address(voter), address(gauge)), 0);
        voter.distribute(gauges);
        assertEq(AERO.allowance(address(voter), address(gauge)), 0);
        assertApproxEqRel(AERO.balanceOf(address(gauge)), expectedMint / 2, 1e6);
        assertApproxEqRel(AERO.balanceOf(address(voter)), expectedMint / 2, 1e6);
        assertApproxEqRel(gauge.rewardRate(), expectedMint / 2 / (5 days), 1e6);
        assertApproxEqRel(gauge.rewardRateByEpoch(epochStart), expectedMint / 2 / (5 days), 1e6);
        skipAndRoll(1);

        minter.updatePeriod();
        assertApproxEqRel(AERO.balanceOf(address(voter)), expectedMint / 2, 1e6);
        skipAndRoll(1);

        gauges[0] = address(gauge2);
        voter.distribute(gauges);
        assertApproxEqRel(AERO.balanceOf(address(gauge2)), expectedMint / 2, 1e6);
        assertLt(AERO.balanceOf(address(voter)), 1e6); // dust
        skipAndRoll(1);

        skip(1 hours);
        gauges[0] = address(gauge);
        voter.distribute(gauges); // second distribute should make no difference to gauge
        assertApproxEqRel(AERO.balanceOf(address(gauge)), expectedMint / 2, 1e6);
        assertLt(AERO.balanceOf(address(voter)), 1e6); // dust
        assertApproxEqRel(gauge.rewardRate(), expectedMint / 2 / (5 days), 1e6);
        assertApproxEqRel(gauge.rewardRateByEpoch(epochStart), expectedMint / 2 / (5 days), 1e6);

        /// epoch 2
        skipToNextEpoch(1);
        uint256 balance = AERO.balanceOf(address(gauge));
        /// 10_300_000_000000000000000000 = 10_300_000e18
        expectedMint = _expectedMintAfter(2);
        balance += expectedMint / 2;

        vm.expectEmit(true, true, false, false, address(minter));
        emit Mint(address(voter), expectedMint, 0, false);
        voter.distribute(0, voter.length());
        assertLt(AERO.balanceOf(address(voter)), 1e6);
        assertApproxEqRel(AERO.balanceOf(address(gauge)), balance, 1e6);
        assertApproxEqRel(AERO.balanceOf(address(gauge)), balance, 1e6);

        /// after 67 epochs, tail emissions turn on
        for (uint256 i = 0; i < 65; i++) {
            skipToNextEpoch(1);
            minter.updatePeriod();
        }
        voter.distribute(0, voter.length());
        assertTrue(minter.weekly() < minter.TAIL_START());

        // skip to first tail distribution
        skipToNextEpoch(1);

        minter.updatePeriod();
        /// total aero supply ~1_318_923_747, tail emissions .29% of total supply
        /// 1_318_923_747 ~= 50_000_000 initial supply + emissions until now
        assertApproxEqAbs(AERO.balanceOf(address(voter)), 8_744_211 * TOKEN_1, TOKEN_1);
        voter.distribute(0, voter.length());

        assertEq(minter.tailEmissionRate(), 67);

        // 1 now has larger lock balance than 2
        escrow.increaseUnlockTime(1, MAXTIME);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = Strings.toString(block.timestamp);

        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes); // epoch + 15 minutes + 1
        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1, 1);
        skipAndRoll(1); // epoch + 15 minutes + 2

        /// expect 1 (for vote) to pass
        epochGovernor.castVote(pid, 1, 1);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 0);

        skipAndRoll(1 weeks); // epoch + 15 minutes + 2
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(minter.tailEmissionRate(), 68);

        minter.updatePeriod();
        /// total aero supply ~1_333_083_660, tail emissions .67% of total supply
        assertApproxEqAbs(AERO.balanceOf(address(voter)), 8_968_681 * TOKEN_1, TOKEN_1);
        voter.distribute(0, voter.length());

        description = Strings.toString(block.timestamp);
        pid = epochGovernor.propose(1, targets, values, calldatas, description);
        skipAndRoll(15 minutes + 1); // epoch + 30 minutes + 3

        /// expect 2 (no change vote) to pass
        epochGovernor.castVote(pid, 1, 2);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 1);

        skipToNextEpoch(0);
        // create new proposal immediately on epoch flip (i.e. two concurrent proposals)
        string memory description2 = Strings.toString(block.timestamp);
        uint256 pid2 = epochGovernor.propose(1, targets, values, calldatas, description2);

        skipAndRoll(30 minutes + 3); // epoch + 30 minutes + 3
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(minter.tailEmissionRate(), 68);

        minter.updatePeriod();
        /// total aero supply ~1_347_869_657, tail emissions .68% of total supply
        assertApproxEqAbs(AERO.balanceOf(address(voter)), 9_064_968 * TOKEN_1, TOKEN_1);
        voter.distribute(0, voter.length());

        /// expect 0 (against vote) to pass
        epochGovernor.castVote(pid2, 1, 0);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid2, 2, 2);

        skipAndRoll(1 weeks);
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description2)));
        assertEq(minter.tailEmissionRate(), 67);

        minter.updatePeriod();
        /// total aero supply ~1_361_640_291, tail emissions .67% of total supply
        assertApproxEqAbs(AERO.balanceOf(address(voter)), 9_027_516 * TOKEN_1, TOKEN_1);
        voter.distribute(0, voter.length());
    }

    /// @dev Helper to calculate expected tokens minted.
    function _expectedMintAfter(uint256 _weeks) internal pure returns (uint256) {
        uint256 amount = 10_000_000 * 1e18;
        for (uint256 i = 0; i < _weeks - 1; i++) {
            if (_weeks <= 14) {
                amount = (amount * 10_300) / 10_000;
            } else {
                amount = (amount * 9_900) / 10_000;
            }
        }
        return amount;
    }
}
