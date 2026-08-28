// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// @title SafeCast Library
/// @author velodrome.finance
/// @notice Safely convert unsigned and signed integers without overflow / underflow
library SafeCastLibrary {
    error SafeCastOverflow();
    error SafeCastUnderflow();

    /// @dev Safely convert uint256 to int128
    function toInt128(uint256 value) internal pure returns (int128) {
        if (value > uint128(type(int128).max)) revert SafeCastOverflow();
        return int128(uint128(value));
    }

    /// @dev Safely convert int128 to uint256
    function toUint256(int128 value) internal pure returns (uint256) {
        if (value < 0) revert SafeCastUnderflow();
        return uint256(int256(value));
    }
}
