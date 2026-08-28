// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Contains helpful functions for end to end testing
abstract contract ExtendedBaseTest is BaseTest {
    // precision used in calculating rewards
    // 1e12 relative precision implies acceptable error of 1e-6 * expected value
    // e.g. if we expect 1e18, precision of 1e12 means we will accept values of
    // 1e18 +- (1e6 * 1e12 / 1e18)
    uint256 public immutable PRECISION = 1e12;
    uint256 public immutable MAX_TIME = 4 * 365 * 86400;

    function _createBribeWithAmount(BribeVotingReward _bribeVotingReward, address _token, uint256 _amount) internal {
        IERC20(_token).approve(address(_bribeVotingReward), _amount);
        _bribeVotingReward.notifyRewardAmount(address(_token), _amount);
    }
}
