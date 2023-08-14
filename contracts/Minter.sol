// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";
import {IVelo} from "./interfaces/IVelo.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IEpochGovernor} from "./interfaces/IEpochGovernor.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Minter
/// @author velodrome.finance, @figs999, @pegahcarter
/// @notice Controls minting of emissions and rebases for Velodrome
contract Minter is IMinter {
    using SafeERC20 for IVelo;
    /// @inheritdoc IMinter
    IVelo public immutable velo;
    /// @inheritdoc IMinter
    IVoter public immutable voter;
    /// @inheritdoc IMinter
    IVotingEscrow public immutable ve;
    /// @inheritdoc IMinter
    IRewardsDistributor public immutable rewardsDistributor;

    /// @inheritdoc IMinter
    uint256 public constant WEEK = 1 weeks;
    /// @inheritdoc IMinter
    uint256 public constant WEEKLY_DECAY = 9_900;
    /// @inheritdoc IMinter
    uint256 public constant MAXIMUM_TAIL_RATE = 100;
    /// @inheritdoc IMinter
    uint256 public constant MINIMUM_TAIL_RATE = 1;
    /// @inheritdoc IMinter
    uint256 public constant MAX_BPS = 10_000;
    /// @inheritdoc IMinter
    uint256 public constant NUDGE = 1;
    /// @inheritdoc IMinter
    uint256 public constant TAIL_START = 6_000_000 * 1e18;
    /// @inheritdoc IMinter
    uint256 public constant MAXIMUM_TEAM_RATE = 500;
    /// @inheritdoc IMinter
    uint256 public teamRate = 500; // team emissions start at 5%
    /// @inheritdoc IMinter
    uint256 public tailEmissionRate = 30;
    /// @inheritdoc IMinter
    uint256 public weekly = 15_000_000 * 1e18;
    /// @inheritdoc IMinter
    uint256 public activePeriod;
    /// @inheritdoc IMinter
    mapping(uint256 => bool) public proposals;
    /// @inheritdoc IMinter
    address public team;
    /// @inheritdoc IMinter
    address public pendingTeam;

    constructor(
        address _voter, // the voting & distribution system
        address _ve, // the ve(3,3) system that will be locked into
        address _rewardsDistributor // the distribution system that ensures users aren't diluted
    ) {
        velo = IVelo(IVotingEscrow(_ve).token());
        voter = IVoter(_voter);
        ve = IVotingEscrow(_ve);
        team = msg.sender;
        rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
        activePeriod = ((block.timestamp) / WEEK) * WEEK; // allow emissions this coming epoch
    }

    /// @inheritdoc IMinter
    function setTeam(address _team) external {
        if (msg.sender != team) revert NotTeam();
        if (_team == address(0)) revert ZeroAddress();
        pendingTeam = _team;
    }

    /// @inheritdoc IMinter
    function acceptTeam() external {
        if (msg.sender != pendingTeam) revert NotPendingTeam();
        team = pendingTeam;
        delete pendingTeam;
        emit AcceptTeam(team);
    }

    /// @inheritdoc IMinter
    function setTeamRate(uint256 _rate) external {
        if (msg.sender != team) revert NotTeam();
        if (_rate > MAXIMUM_TEAM_RATE) revert RateTooHigh();
        teamRate = _rate;
    }

    /// @inheritdoc IMinter
    function calculateGrowth(uint256 _minted) public view returns (uint256 _growth) {
        uint256 _veTotal = ve.totalSupplyAt(activePeriod - 1);
        uint256 _veloTotal = velo.totalSupply();

        return (((_minted * (_veloTotal - _veTotal)) / _veloTotal) * (_veloTotal - _veTotal)) / _veloTotal / 2;
    }

    /// @inheritdoc IMinter
    function nudge() external {
        address _epochGovernor = voter.epochGovernor();
        if (msg.sender != _epochGovernor) revert NotEpochGovernor();
        IEpochGovernor.ProposalState _state = IEpochGovernor(_epochGovernor).result();
        if (weekly >= TAIL_START) revert TailEmissionsInactive();
        uint256 _period = activePeriod;
        if (proposals[_period]) revert AlreadyNudged();
        uint256 _newRate = tailEmissionRate;
        uint256 _oldRate = _newRate;

        if (_state != IEpochGovernor.ProposalState.Expired) {
            if (_state == IEpochGovernor.ProposalState.Succeeded) {
                _newRate = _oldRate + NUDGE > MAXIMUM_TAIL_RATE ? MAXIMUM_TAIL_RATE : _oldRate + NUDGE;
            } else {
                _newRate = _oldRate - NUDGE < MINIMUM_TAIL_RATE ? MINIMUM_TAIL_RATE : _oldRate - NUDGE;
            }
            tailEmissionRate = _newRate;
        }
        proposals[_period] = true;
        emit Nudge(_period, _oldRate, _newRate);
    }

    /// @inheritdoc IMinter
    function updatePeriod() external returns (uint256 _period) {
        _period = activePeriod;
        if (block.timestamp >= _period + WEEK) {
            _period = (block.timestamp / WEEK) * WEEK;
            activePeriod = _period;
            uint256 _weekly = weekly;
            uint256 _emission;
            uint256 _totalSupply = velo.totalSupply();
            bool _tail = _weekly < TAIL_START;

            if (_tail) {
                _emission = (_totalSupply * tailEmissionRate) / MAX_BPS;
            } else {
                _emission = _weekly;
                _weekly = (_weekly * WEEKLY_DECAY) / MAX_BPS;
                weekly = _weekly;
            }

            uint256 _growth = calculateGrowth(_emission);

            uint256 _rate = teamRate;
            uint256 _teamEmissions = (_rate * (_growth + _weekly)) / (MAX_BPS - _rate);

            uint256 _required = _growth + _emission + _teamEmissions;
            uint256 _balanceOf = velo.balanceOf(address(this));
            if (_balanceOf < _required) {
                velo.mint(address(this), _required - _balanceOf);
            }

            velo.safeTransfer(address(team), _teamEmissions);
            velo.safeTransfer(address(rewardsDistributor), _growth);
            rewardsDistributor.checkpointToken(); // checkpoint token balance that was just minted in rewards distributor

            velo.safeApprove(address(voter), _emission);
            voter.notifyRewardAmount(_emission);

            emit Mint(msg.sender, _emission, velo.totalSupply(), _tail);
        }
    }
}
