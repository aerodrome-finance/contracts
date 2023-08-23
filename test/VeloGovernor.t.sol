// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";
import {IVetoGovernor} from "contracts/governance/IVetoGovernor.sol";

contract ProtocolGovernorTest is BaseTest {
    event ProposalVetoed(uint256 proposalId);

    function _setUp() public override {
        AERO.approve(address(escrow), 97 * TOKEN_1);
        escrow.createLock(97 * TOKEN_1, MAXTIME); // 1

        // owner2 owns less than quorum, 3%
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), 3 * TOKEN_1);
        escrow.createLock(3 * TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);
    }

    function testCannotSetVetoerToZeroAddress() public {
        vm.prank(governor.vetoer());
        vm.expectRevert(ProtocolGovernor.ZeroAddress.selector);
        governor.setVetoer(address(0));
    }

    function testCannotSetVetoerIfNotVetoer() public {
        vm.prank(address(owner2));
        vm.expectRevert(ProtocolGovernor.NotVetoer.selector);
        governor.setVetoer(address(owner2));
    }

    function testSetVetoer() public {
        governor.setVetoer(address(owner2));

        assertEq(governor.pendingVetoer(), address(owner2));
    }

    function testCannotRenounceVetoerIfNotVetoer() public {
        vm.prank(address(owner2));
        vm.expectRevert(ProtocolGovernor.NotVetoer.selector);
        governor.renounceVetoer();
    }

    function testRenounceVetoer() public {
        governor.renounceVetoer();

        assertEq(governor.vetoer(), address(0));
    }

    function testCannotAcceptVetoerIfNotPendingVetoer() public {
        governor.setVetoer(address(owner2));

        vm.prank(address(owner3));
        vm.expectRevert(ProtocolGovernor.NotPendingVetoer.selector);
        governor.acceptVetoer();
    }

    function testAcceptVetoer() public {
        governor.setVetoer(address(owner2));

        vm.prank(address(owner2));
        governor.acceptVetoer();

        assertEq(governor.vetoer(), address(owner2));
    }

    function testCannotVetoIfNotVetoer() public {
        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, address(USDC));
        string memory description = "Whitelist USDC";

        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        vm.prank(address(owner2));
        vm.expectRevert(ProtocolGovernor.NotVetoer.selector);
        governor.veto(pid);
    }

    function testVetoProposal() public {
        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, address(USDC));
        string memory description = "Whitelist USDC";

        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes + 1);

        governor.castVote(pid, 1, 1);
        uint256 proposalStart = governor.proposalSnapshot(pid);
        assertGt(governor.getVotes(address(owner), 1, proposalStart), governor.quorum(proposalStart)); // check quorum

        skipAndRoll(1 weeks / 2);

        vm.expectEmit(true, false, false, true, address(governor));
        emit ProposalVetoed(pid);
        governor.veto(pid);

        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Vetoed));

        vm.expectRevert("Governor: proposal not successful");
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
    }

    function testGovernorCanCreateGaugesForAnyAddress() public {
        vm.prank(address(governor));
        voter.createGauge(address(factory), address(1));
    }

    function testCannotSetProposalNumeratorAboveMaximum() public {
        vm.expectRevert(ProtocolGovernor.ProposalNumeratorTooHigh.selector);
        governor.setProposalNumerator(501);
    }

    function testCannotSetProposalNumeratorIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(ProtocolGovernor.NotTeam.selector);
        governor.setProposalNumerator(1);
    }

    function testSetProposalNumerator() public {
        governor.setProposalNumerator(50);
        assertEq(governor.proposalNumerator(), 50);
    }

    function testCannotProposeWithoutSufficientBalance() public {
        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, address(USDC), true);
        string memory description = "Whitelist USDC";

        vm.prank(address(owner2));
        vm.expectRevert("Governor: proposer votes below proposal threshold");
        governor.propose(1, targets, values, calldatas, description);
    }

    function testCannotExecuteWithoutQuorum() public {
        address token = address(new MockERC20("TEST", "TEST", 18));
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 1, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Pending));

        skipAndRoll(1);
        // vote
        vm.prank(address(owner2));
        governor.castVote(pid, 2, 1);

        skip(1 weeks);

        // execute
        vm.prank(address(owner));
        vm.expectRevert("Governor: proposal not successful");
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
    }

    function testProposalHasQuorum() public {
        address token = address(new MockERC20("TEST", "TEST", 18));
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        assertEq(escrow.balanceOfNFT(1), 96733552971170873788); // voting power at proposal start
        assertEq(escrow.getPastVotes(address(owner), 1, block.timestamp), 96733552971170873788);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 1, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        // vote
        governor.castVote(pid, 1, 1);
        assertEq(governor.hasVoted(pid, 1), true);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(pid);
        assertEq(againstVotes, 0);
        assertEq(forVotes, 96733552971170873788);
        assertEq(abstainVotes, 0);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        skipAndRoll(1);
        // cannot vote twice
        vm.expectRevert("GovernorVotingSimple: vote already cast");
        governor.castVote(pid, 1, 2);

        skipAndRoll(1);
        // cannot vote with voting weight that is not yours
        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, 2, 1);

        skipAndRoll(1 weeks);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Succeeded));

        // execute
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Executed));
        assertTrue(voter.isWhitelistedToken(token));
    }

    function testProposalHasQuorumWithDelegatedVotes() public {
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 3
        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), TOKEN_1 * 100);
        escrow.createLock(TOKEN_1 * 100, MAXTIME); // 4
        escrow.lockPermanent(4);
        escrow.delegate(4, 3);
        vm.stopPrank();
        skipAndRoll(1);

        address token = address(new MockERC20("TEST", "TEST", 18));
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token, true);
        string memory description = "Whitelist Token";

        // propose
        uint256 pid = governor.propose(1, targets, values, calldatas, description);

        skipAndRoll(15 minutes);
        assertEq(escrow.balanceOfNFT(3), 997253115368668515); // voting power at proposal start
        assertEq(escrow.getPastVotes(address(owner), 3, block.timestamp), 997253115368668515 + TOKEN_1 * 100);
        assertEq(escrow.balanceOfNFT(4), TOKEN_1 * 100);
        assertEq(escrow.getPastVotes(address(owner3), 4, block.timestamp), 0);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(pid, 3, 1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Pending));

        skipAndRoll(1);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        // vote
        governor.castVote(pid, 3, 1);
        assertEq(governor.hasVoted(pid, 3), true);
        assertEq(governor.hasVoted(pid, 4), false);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(pid);
        assertEq(againstVotes, 0);
        assertEq(forVotes, 997253115368668515 + TOKEN_1 * 100);
        assertEq(abstainVotes, 0);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Active));

        skipAndRoll(1);
        // cannot vote twice
        vm.expectRevert("GovernorVotingSimple: vote already cast");
        governor.castVote(pid, 3, 2);

        skipAndRoll(1);
        // cannot vote with voting weight that is not yours
        vm.expectRevert("GovernorVotingSimple: zero voting weight");
        governor.castVote(pid, 4, 1);

        skipAndRoll(1 weeks);
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Succeeded));

        // execute
        governor.execute(targets, values, calldatas, keccak256(bytes(description)), address(owner));
        assertEq(uint256(governor.state(pid)), uint256(IVetoGovernor.ProposalState.Executed));
        assertTrue(voter.isWhitelistedToken(token));
    }

    function testProposeWithUniqueProposals() public {
        address token = address(new MockERC20("TEST", "TEST", 18));
        assertFalse(voter.isWhitelistedToken(token));

        address[] memory targets = new address[](1);
        targets[0] = address(voter);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(voter.whitelistToken.selector, token);
        string memory description = "Whitelist Token";

        // a user creates a proposal
        // another user frontruns the initial proposal creation, and then cancels the proposal
        uint256 pid = governor.propose(1, targets, values, calldatas, description); // frontrun

        vm.prank(address(owner2));
        uint256 pid2 = governor.propose(2, targets, values, calldatas, description); // will revert if pids not unique

        assertFalse(pid == pid2);
    }
}
