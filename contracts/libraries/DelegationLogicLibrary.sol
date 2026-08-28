// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeCastLibrary} from "./SafeCastLibrary.sol";

library DelegationLogicLibrary {
    using SafeCastLibrary for int128;

    /// @notice Used by `_mint`, `_transferFrom`, `_burn` and `delegate`
    ///         to update delegator voting checkpoints.
    ///         Automatically dedelegates, then updates checkpoint.
    /// @dev This function depends on `_locked` and must be called prior to token state changes.
    ///      If you wish to dedelegate only, use `_delegate(tokenId, 0)` instead.
    /// @param _locked State of all locked balances
    /// @param _numCheckpoints State of all user checkpoint counts
    /// @param _checkpoints State of all user checkpoints
    /// @param _delegates State of all user delegatees
    /// @param _delegator The delegator to update checkpoints for
    /// @param _delegatee The new delegatee for the delegator. Cannot be equal to `_delegator` (use 0 instead).
    /// @param _owner The new (or current) owner for the delegator
    function checkpointDelegator(
        mapping(uint256 => IVotingEscrow.LockedBalance) storage _locked,
        mapping(uint256 => uint48) storage _numCheckpoints,
        mapping(uint256 => mapping(uint48 => IVotingEscrow.Checkpoint)) storage _checkpoints,
        mapping(uint256 => uint256) storage _delegates,
        uint256 _delegator,
        uint256 _delegatee,
        address _owner
    ) external {
        uint256 delegatedBalance = _locked[_delegator].amount.toUint256();
        uint48 numCheckpoint = _numCheckpoints[_delegator];
        IVotingEscrow.Checkpoint storage cpOld = numCheckpoint > 0
            ? _checkpoints[_delegator][numCheckpoint - 1]
            : _checkpoints[_delegator][0];
        // Dedelegate from delegatee if delegated
        checkpointDelegatee(_numCheckpoints, _checkpoints, cpOld.delegatee, delegatedBalance, false);
        IVotingEscrow.Checkpoint storage cp = _checkpoints[_delegator][numCheckpoint];
        cp.fromTimestamp = block.timestamp;
        cp.delegatedBalance = cpOld.delegatedBalance;
        cp.delegatee = _delegatee;
        cp.owner = _owner;

        if (_isCheckpointInNewBlock(_numCheckpoints, _checkpoints, _delegator)) {
            _numCheckpoints[_delegator]++;
        } else {
            _checkpoints[_delegator][numCheckpoint - 1] = cp;
            delete _checkpoints[_delegator][numCheckpoint];
        }

        _delegates[_delegator] = _delegatee;
    }

    /// @notice Update delegatee's `delegatedBalance` by `balance`.
    ///         Only updates if delegating to a new delegatee.
    /// @dev If used with `balance` == `_locked[_tokenId].amount`, then this is the same as
    ///      delegating or dedelegating from `_tokenId`
    ///      If used with `balance` < `_locked[_tokenId].amount`, then this is used to adjust
    ///      `delegatedBalance` when a user's balance is modified (e.g. `increaseAmount`, `merge` etc).
    ///      If `delegatee` is 0 (i.e. user is not delegating), then do nothing.
    /// @param _numCheckpoints State of all user checkpoint counts
    /// @param _checkpoints State of all user checkpoints
    /// @param _delegatee The delegatee's tokenId
    /// @param balance_ The delta in balance change
    /// @param _increase True if balance is increasing, false if decreasing
    function checkpointDelegatee(
        mapping(uint256 => uint48) storage _numCheckpoints,
        mapping(uint256 => mapping(uint48 => IVotingEscrow.Checkpoint)) storage _checkpoints,
        uint256 _delegatee,
        uint256 balance_,
        bool _increase
    ) public {
        if (_delegatee == 0) return;
        uint48 numCheckpoint = _numCheckpoints[_delegatee];
        IVotingEscrow.Checkpoint storage cpOld = numCheckpoint > 0
            ? _checkpoints[_delegatee][numCheckpoint - 1]
            : _checkpoints[_delegatee][0];
        IVotingEscrow.Checkpoint storage cp = _checkpoints[_delegatee][numCheckpoint];
        cp.fromTimestamp = block.timestamp;
        cp.owner = cpOld.owner;
        // do not expect balance_ > cpOld.delegatedBalance when decrementing but just in case
        cp.delegatedBalance = _increase
            ? cpOld.delegatedBalance + balance_
            : (balance_ < cpOld.delegatedBalance ? cpOld.delegatedBalance - balance_ : 0);
        cp.delegatee = cpOld.delegatee;

        if (_isCheckpointInNewBlock(_numCheckpoints, _checkpoints, _delegatee)) {
            _numCheckpoints[_delegatee]++;
        } else {
            _checkpoints[_delegatee][numCheckpoint - 1] = cp;
            delete _checkpoints[_delegatee][numCheckpoint];
        }
    }

    function _isCheckpointInNewBlock(
        mapping(uint256 => uint48) storage _numCheckpoints,
        mapping(uint256 => mapping(uint48 => IVotingEscrow.Checkpoint)) storage _checkpoints,
        uint256 _tokenId
    ) internal view returns (bool) {
        uint48 _nCheckPoints = _numCheckpoints[_tokenId];

        if (_nCheckPoints > 0 && _checkpoints[_tokenId][_nCheckPoints - 1].fromTimestamp == block.timestamp) {
            return false;
        } else {
            return true;
        }
    }

    /// @notice Binary search to get the voting checkpoint for a token id at or prior to a given timestamp.
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    /// @param _numCheckpoints State of all user checkpoint counts
    /// @param _checkpoints State of all user checkpoints
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return The index of the checkpoint.
    function getPastVotesIndex(
        mapping(uint256 => uint48) storage _numCheckpoints,
        mapping(uint256 => mapping(uint48 => IVotingEscrow.Checkpoint)) storage _checkpoints,
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint48) {
        uint48 nCheckpoints = _numCheckpoints[_tokenId];
        if (nCheckpoints == 0) return 0;
        // First check most recent balance
        if (_checkpoints[_tokenId][nCheckpoints - 1].fromTimestamp <= _timestamp) return (nCheckpoints - 1);
        // Next check implicit zero balance
        if (_checkpoints[_tokenId][0].fromTimestamp > _timestamp) return 0;

        uint48 lower = 0;
        uint48 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint48 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IVotingEscrow.Checkpoint storage cp = _checkpoints[_tokenId][center];
            if (cp.fromTimestamp == _timestamp) {
                return center;
            } else if (cp.fromTimestamp < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Retrieves historical voting balance for a token id at a given timestamp.
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    ///      The user must also own the token at the time in order to receive a voting balance.
    /// @param _numCheckpoints State of all user checkpoint counts
    /// @param _checkpoints State of all user checkpoints
    /// @param _account .
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return Total voting balance including delegations at a given timestamp.
    function getPastVotes(
        mapping(uint256 => uint48) storage _numCheckpoints,
        mapping(uint256 => mapping(uint48 => IVotingEscrow.Checkpoint)) storage _checkpoints,
        address _account,
        uint256 _tokenId,
        uint256 _timestamp
    ) external view returns (uint256) {
        uint48 _checkIndex = getPastVotesIndex(_numCheckpoints, _checkpoints, _tokenId, _timestamp);
        IVotingEscrow.Checkpoint memory lastCheckpoint = _checkpoints[_tokenId][_checkIndex];
        // If no point exists prior to the given timestamp, return 0
        if (lastCheckpoint.fromTimestamp > _timestamp) return 0;
        // Check ownership
        if (_account != lastCheckpoint.owner) return 0;
        uint256 votes = lastCheckpoint.delegatedBalance;
        return
            lastCheckpoint.delegatee == 0
                ? votes + IVotingEscrow(address(this)).balanceOfNFTAt(_tokenId, _timestamp)
                : votes;
    }
}
