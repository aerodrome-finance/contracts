// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVelo} from "./IVelo.sol";
import {IVoter} from "./IVoter.sol";
import {IVotingEscrow} from "./IVotingEscrow.sol";
import {IRewardsDistributor} from "./IRewardsDistributor.sol";

interface IMinter {
    error NotTeam();
    error RateTooHigh();
    error ZeroAddress();
    error AlreadyNudged();
    error NotPendingTeam();
    error NotEpochGovernor();
    error TailEmissionsInactive();

    event Mint(address indexed _sender, uint256 _weekly, uint256 _circulating_supply, bool indexed _tail);
    event Nudge(uint256 indexed _period, uint256 _oldRate, uint256 _newRate);
    event AcceptTeam(address indexed _newTeam);

    /// @notice Interface of Velo.sol
    function velo() external view returns (IVelo);

    /// @notice Interface of Voter.sol
    function voter() external view returns (IVoter);

    /// @notice Interface of IVotingEscrow.sol
    function ve() external view returns (IVotingEscrow);

    /// @notice Interface of RewardsDistributor.sol
    function rewardsDistributor() external view returns (IRewardsDistributor);

    /// @notice Duration of epoch in seconds
    function WEEK() external view returns (uint256);

    /// @notice Decay rate of emissions as percentage of `MAX_BPS`
    function WEEKLY_DECAY() external view returns (uint256);

    /// @notice Maximum tail emission rate in basis points.
    function MAXIMUM_TAIL_RATE() external view returns (uint256);

    /// @notice Minimum tail emission rate in basis points.
    function MINIMUM_TAIL_RATE() external view returns (uint256);

    /// @notice Denominator for emissions calculations (as basis points)
    function MAX_BPS() external view returns (uint256);

    /// @notice Rate change per proposal
    function NUDGE() external view returns (uint256);

    /// @notice When emissions fall below this amount, begin tail emissions
    function TAIL_START() external view returns (uint256);

    /// @notice Maximum team percentage in basis points
    function MAXIMUM_TEAM_RATE() external view returns (uint256);

    /// @notice Current team percentage in basis points
    function teamRate() external view returns (uint256);

    /// @notice Tail emissions rate in basis points
    function tailEmissionRate() external view returns (uint256);

    /// @notice Starting weekly emission of 15M VELO (VELO has 18 decimals)
    function weekly() external view returns (uint256);

    /// @notice Timestamp of start of epoch that updatePeriod was last called in
    function activePeriod() external returns (uint256);

    /// @dev activePeriod => proposal existing, used to enforce one proposal per epoch
    /// @param _activePeriod Timestamp of start of epoch
    /// @return True if proposal has been executed, else false
    function proposals(uint256 _activePeriod) external view returns (bool);

    /// @notice Current team address in charge of emissions
    function team() external view returns (address);

    /// @notice Possible team address pending approval of current team
    function pendingTeam() external view returns (address);

    /// @notice Creates a request to change the current team's address
    /// @param _team Address of the new team to be chosen
    function setTeam(address _team) external;

    /// @notice Accepts the request to replace the current team's address
    ///         with the requested one, present on variable pendingTeam
    function acceptTeam() external;

    /// @notice Creates a request to change the current team's percentage
    /// @param _rate New team rate to be set in basis points
    function setTeamRate(uint256 _rate) external;

    /// @notice Allows epoch governor to modify the tail emission rate by at most 1 basis point
    ///         per epoch to a maximum of 100 basis points or to a minimum of 1 basis point.
    ///         Note: the very first nudge proposal must take place the week prior
    ///         to the tail emission schedule starting.
    /// @dev Throws if not epoch governor.
    ///      Throws if not currently in tail emission schedule.
    ///      Throws if already nudged this epoch.
    ///      Throws if nudging above maximum rate.
    ///      Throws if nudging below minimum rate.
    ///      This contract is coupled to EpochGovernor as it requires three option simple majority voting.
    function nudge() external;

    /// @notice Calculates rebases according to the formula
    ///         weekly * (ve.totalSupply / velo.totalSupply) ^ 3 / 2
    ///         Note that ve.totalSupply is the locked ve supply
    ///         velo.totalSupply is the total ve supply minted
    /// @param _minted Amount of VELO minted this epoch
    /// @return _growth Rebases
    function calculateGrowth(uint256 _minted) external view returns (uint256 _growth);

    /// @notice Processes emissions and rebases. Callable once per epoch (1 week).
    /// @return _period Start of current epoch.
    function updatePeriod() external returns (uint256 _period);
}
