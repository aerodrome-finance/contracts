// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {SafeCastLibrary} from "./SafeCastLibrary.sol";

library BalanceLogicLibrary {
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;

    uint256 internal constant WEEK = 1 weeks;

    /// @notice Binary search to get the user point index for a token id at or prior to a given timestamp
    /// @dev If a user point does not exist prior to the timestamp, this will return 0.
    /// @param _userPointEpoch State of all user point epochs
    /// @param _userPointHistory State of all user point history
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return User point index
    function getPastUserPointIndex(
        mapping(uint256 => uint256) storage _userPointEpoch,
        mapping(uint256 => IVotingEscrow.UserPoint[1000000000]) storage _userPointHistory,
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 _userEpoch = _userPointEpoch[_tokenId];
        if (_userEpoch == 0) return 0;
        // First check most recent balance
        if (_userPointHistory[_tokenId][_userEpoch].ts <= _timestamp) return (_userEpoch);
        // Next check implicit zero balance
        if (_userPointHistory[_tokenId][1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _userEpoch;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IVotingEscrow.UserPoint storage userPoint = _userPointHistory[_tokenId][center];
            if (userPoint.ts == _timestamp) {
                return center;
            } else if (userPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Binary search to get the global point index at or prior to a given timestamp
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    /// @param _epoch Current global point epoch
    /// @param _pointHistory State of all global point history
    /// @param _timestamp .
    /// @return Global point index
    function getPastGlobalPointIndex(
        uint256 _epoch,
        mapping(uint256 => IVotingEscrow.GlobalPoint) storage _pointHistory,
        uint256 _timestamp
    ) internal view returns (uint256) {
        if (_epoch == 0) return 0;
        // First check most recent balance
        if (_pointHistory[_epoch].ts <= _timestamp) return (_epoch);
        // Next check implicit zero balance
        if (_pointHistory[1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _epoch;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IVotingEscrow.GlobalPoint storage globalPoint = _pointHistory[center];
            if (globalPoint.ts == _timestamp) {
                return center;
            } else if (globalPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Get the current voting power for `_tokenId`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    ///      Fetches last user point prior to a certain timestamp, then walks forward to timestamp.
    /// @param _userPointEpoch State of all user point epochs
    /// @param _userPointHistory State of all user point history
    /// @param _tokenId NFT for lock
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function balanceOfNFTAt(
        mapping(uint256 => uint256) storage _userPointEpoch,
        mapping(uint256 => IVotingEscrow.UserPoint[1000000000]) storage _userPointHistory,
        uint256 _tokenId,
        uint256 _t
    ) external view returns (uint256) {
        uint256 _epoch = getPastUserPointIndex(_userPointEpoch, _userPointHistory, _tokenId, _t);
        // epoch 0 is an empty point
        if (_epoch == 0) return 0;
        IVotingEscrow.UserPoint memory lastPoint = _userPointHistory[_tokenId][_epoch];
        if (lastPoint.permanent != 0) {
            return lastPoint.permanent;
        } else {
            lastPoint.bias -= lastPoint.slope * (_t - lastPoint.ts).toInt128();
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return lastPoint.bias.toUint256();
        }
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _slopeChanges State of all slopeChanges
    /// @param _pointHistory State of all global point history
    /// @param _epoch The epoch to start search from
    /// @param _t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function supplyAt(
        mapping(uint256 => int128) storage _slopeChanges,
        mapping(uint256 => IVotingEscrow.GlobalPoint) storage _pointHistory,
        uint256 _epoch,
        uint256 _t
    ) external view returns (uint256) {
        uint256 epoch_ = getPastGlobalPointIndex(_epoch, _pointHistory, _t);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        IVotingEscrow.GlobalPoint memory _point = _pointHistory[epoch_];
        int128 bias = _point.bias;
        int128 slope = _point.slope;
        uint256 ts = _point.ts;
        uint256 t_i = (ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            int128 dSlope = 0;
            if (t_i > _t) {
                t_i = _t;
            } else {
                dSlope = _slopeChanges[t_i];
            }
            bias -= slope * (t_i - ts).toInt128();
            if (t_i == _t) {
                break;
            }
            slope += dSlope;
            ts = t_i;
        }

        if (bias < 0) {
            bias = 0;
        }
        return bias.toUint256() + _point.permanentLockBalance;
    }
}
