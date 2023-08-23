// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";
import {IGovernor as OZGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IGovernor} from "contracts/governance/IGovernor.sol";

contract EpochGovernorTest is BaseTest {
    using stdStorage for StdStorage;

    function _setUp() public override {
        AERO.approve(address(escrow), 2 * TOKEN_1);
        escrow.createLock(2 * TOKEN_1, MAXTIME); // 1
        vm.roll(block.number + 1);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        vm.roll(block.number + 1);

        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 3
        vm.stopPrank();
        vm.roll(block.number + 1);

        vm.startPrank(address(owner4));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 4
        vm.stopPrank();
        vm.roll(block.number + 1);

        stdstore.target(address(minter)).sig("weekly()").checked_write(4_999_999 * 1e18);
    }

    function testSupportInterfacesExcludesCancel() public {
        assertTrue(
            epochGovernor.supportsInterface(
                type(IGovernor).interfaceId ^
                    type(IERC6372).interfaceId ^
                    IGovernor.castVoteWithReasonAndParams.selector ^
                    IGovernor.castVoteWithReasonAndParamsBySig.selector ^
                    IGovernor.getVotesWithParams.selector
            )
        );
        assertTrue(epochGovernor.supportsInterface(type(IGovernor).interfaceId ^ type(IERC6372).interfaceId));
        assertTrue(epochGovernor.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertFalse(
            epochGovernor.supportsInterface(
                type(IGovernor).interfaceId ^ type(IERC6372).interfaceId ^ OZGovernor.cancel.selector
            )
        );
        assertFalse(
            epochGovernor.supportsInterface(
                type(IGovernor).interfaceId ^
                    type(IERC6372).interfaceId ^
                    OZGovernor.cancel.selector ^
                    IGovernor.castVoteWithReasonAndParams.selector ^
                    IGovernor.castVoteWithReasonAndParamsBySig.selector ^
                    IGovernor.getVotesWithParams.selector
            )
        );
    }

    function testCannotProposeWithOtherTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        vm.expectRevert("GovernorSimple: only minter allowed");
        epochGovernor.propose(1, targets, values, calldatas, description);
    }

    function testCannotProposeWithOtherCalldata() public {
        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.updatePeriod.selector);
        string memory description = "";

        vm.expectRevert("GovernorSimple: only nudge allowed");
        epochGovernor.propose(1, targets, values, calldatas, description);
    }

    function testEpochGovernorCanExecuteSucceeded() public {
        assertEq(minter.tailEmissionRate(), 67);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        assertEq(escrow.balanceOfNFT(1), 1994506262572926509); // voting power at proposal start
        assertEq(escrow.balanceOfNFT(2), 997253131223564505); // voting power at proposal start
        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        epochGovernor.castVote(pid, 1, 1); // for: 2
        assertEq(epochGovernor.hasVoted(pid, 1), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 0);
        assertEq(forVotes, 1994506262572926509);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 0); // against: 1
        assertEq(epochGovernor.hasVoted(pid, 2), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997253131223564505);
        assertEq(forVotes, 1994506262572926509);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 3, 2); // abstain: 1
        assertEq(epochGovernor.hasVoted(pid, 3), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997253131223564505);
        assertEq(forVotes, 1994506262572926509);
        assertEq(abstainVotes, 997253131223564505);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));
        assertEq(epochGovernor.hasVoted(pid, 4), false);

        skipAndRoll(1 weeks);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Succeeded));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Succeeded));

        assertEq(minter.tailEmissionRate(), 68);
    }

    function testEpochGovernorCanExecuteDefeated() public {
        assertEq(minter.tailEmissionRate(), 67);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        assertEq(escrow.balanceOfNFT(1), 1994506262572926509); // voting power at proposal start
        assertEq(escrow.balanceOfNFT(2), 997253131223564505); // voting power at proposal start
        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        epochGovernor.castVote(pid, 1, 0); // against: 2
        assertEq(epochGovernor.hasVoted(pid, 1), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 1994506262572926509);
        assertEq(forVotes, 0);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 1); // for: 1
        assertEq(epochGovernor.hasVoted(pid, 2), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 1994506262572926509);
        assertEq(forVotes, 997253131223564505);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 3, 2); // abstain: 1
        assertEq(epochGovernor.hasVoted(pid, 3), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 1994506262572926509);
        assertEq(forVotes, 997253131223564505);
        assertEq(abstainVotes, 997253131223564505);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));
        assertEq(epochGovernor.hasVoted(pid, 4), false);

        skipAndRoll(1 weeks);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Defeated));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Defeated));

        assertEq(minter.tailEmissionRate(), 66);
    }

    function testEpochGovernorCanExecuteExpired() public {
        assertEq(minter.tailEmissionRate(), 67);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        assertEq(escrow.balanceOfNFT(2), 997253131223564505); // voting power at proposal start
        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 0); // against: 1
        assertEq(epochGovernor.hasVoted(pid, 2), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997253131223564505);
        assertEq(forVotes, 0);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 3, 1); // for: 1
        assertEq(epochGovernor.hasVoted(pid, 3), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997253131223564505);
        assertEq(forVotes, 997253131223564505);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner4));
        epochGovernor.castVote(pid, 4, 2); // abstain: 1
        assertEq(epochGovernor.hasVoted(pid, 4), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997253131223564505);
        assertEq(forVotes, 997253131223564505);
        assertEq(abstainVotes, 997253131223564505);
        // tie: should still expire
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));
        assertEq(epochGovernor.hasVoted(pid, 1), false);

        skipAndRoll(1 weeks);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Expired));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Expired));

        assertEq(minter.tailEmissionRate(), 67);
    }

    function testEpochGovernorCanExecuteSucceededWithDelegation() public {
        assertEq(minter.tailEmissionRate(), 67);

        vm.startPrank(address(owner4));
        escrow.lockPermanent(4);
        escrow.delegate(4, 1);
        vm.stopPrank();

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        uint256 pid = epochGovernor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        assertEq(escrow.balanceOfNFT(1), 1994506262572926509); // voting power at proposal start
        assertEq(escrow.getPastVotes(address(owner), 1, block.timestamp), TOKEN_1 + 1994506262572926509);
        assertEq(escrow.balanceOfNFT(4), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner4), 4, block.timestamp), 0);
        assertEq(escrow.balanceOfNFT(2), 997253131223564505); // voting power at proposal start
        vm.expectRevert("GovernorSimple: vote not currently active");
        epochGovernor.castVote(pid, 1, 1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));

        // vote
        epochGovernor.castVote(pid, 1, 1); // for: 2
        assertEq(epochGovernor.hasVoted(pid, 1), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 0);
        assertEq(forVotes, TOKEN_1 + 1994506262572926509);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner2));
        epochGovernor.castVote(pid, 2, 0); // against: 1
        assertEq(epochGovernor.hasVoted(pid, 2), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997253131223564505);
        assertEq(forVotes, TOKEN_1 + 1994506262572926509);
        assertEq(abstainVotes, 0);
        vm.prank(address(owner3));
        epochGovernor.castVote(pid, 3, 2); // abstain: 1
        assertEq(epochGovernor.hasVoted(pid, 3), true);
        (againstVotes, forVotes, abstainVotes) = epochGovernor.proposalVotes(pid);
        assertEq(againstVotes, 997253131223564505);
        assertEq(forVotes, TOKEN_1 + 1994506262572926509);
        assertEq(abstainVotes, 997253131223564505);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Active));
        assertEq(epochGovernor.hasVoted(pid, 4), false);

        skipAndRoll(1 weeks);
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Succeeded));

        // execute
        epochGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint256(epochGovernor.state(pid)), uint256(IGovernor.ProposalState.Executed));
        assertEq(uint256(epochGovernor.result()), uint256(IGovernor.ProposalState.Succeeded));

        assertEq(minter.tailEmissionRate(), 68);
    }

    function testCannotProposeWithAnExistingProposal() public {
        assertEq(minter.tailEmissionRate(), 67);

        address[] memory targets = new address[](1);
        targets[0] = address(minter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(minter.nudge.selector);
        string memory description = "";

        // propose
        epochGovernor.propose(1, targets, values, calldatas, description);

        vm.prank(address(owner2));
        vm.expectRevert("GovernorSimple: proposal already exists");
        epochGovernor.propose(2, targets, values, calldatas, description);
    }
}
