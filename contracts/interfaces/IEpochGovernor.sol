// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEpochGovernor {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /// @dev Stores most recent voting result. Will be either Defeated, Succeeded or Expired.
    ///      Any contracts that wish to use this governor must read from this to determine results.
    function result() external returns (ProposalState);
}
