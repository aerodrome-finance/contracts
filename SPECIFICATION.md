# Protocol Specification

This Protocol is a rewrite and redesign of the Solidly architecture.

## Definitions

- AERO: The native token in the Protocol ecosystem. It is emitted by the Minter and is an ERC-20 compliant token.
- Epoch: An epoch is one week in length, beginning at Thursday midnight UTC time. After 4 years, the day of the week it resets on will shift. 
- Pool: AMM constant-product implementation similar to Uniswap V2 liquidity pools.

## Protocol Upgradability

This protocol is immutable. To allow improving the protocol, the
factories are all upgradable. This means we can release new versions of
factories for our pools and gauges, and leave it up to the users to decide if
they want to migrate their positions.

## AMM

### Pool

AMM constant-product implementation similar to Uniswap V2 liquidity pools. 

Lightly modified to allow for the following:
- Support for both stable and volatile pools. Stable pools use a different formula which assumes little to no volatility. The formula used for pricing the assets allows for low slippage even on large traded volumes. Volatile pools use the standard constant product formula. 
- Custom fees per pool.
- Modifying a pool's name and symbol (requires `emergencyCouncil` permissions).

Stable pools use the `x^3 * y + y^3 * x` curve, which may have a larger
rounding error when calculating the invariant `K` when compared to Uniswap
V2's constant product formula. The invariant `K` can temporarily decrease
when a user performs certain actions like depositing liquidity, doing
a swap and withdrawing liquidity. This means that the ratio of `K` to the
total supply of the pool is not monotonically increasing. This temporary decrease 
is negligible and the ratio will eventually increase again. In most cases, this issue
is not critical. This is mentioned as a courtesy to integrators that may depend
 on the ratio of `K` to `totalSupply`as a way of measuring the value of LP tokens.

### PoolFees

Pool helper contract that stores pool trading fees to keep them separate from the liquidity pool. 

### PoolFactory

Responsible for pool creation and management. It facilitates creating and fetching liquidity pools for pairs of tokens, specifying whether they're stable or volatile. It additionally provides pool configuration using 3 roles:
- Pauser: Switch the pool's pause state (enabling/disabling pool swaps)
- FeeManager: Can set a custom fee per pool, with a maximum fee of 3%

### Router

Standard UniswapV2-like Router interface. Supports multi-pool swaps, lp deposits 
and withdrawals. Zapping support is provided for standard
 ERC20 tokens only (i.e. there is no support for fee-on-transfer tokens etc).

In addition, the router also supports:
- Swapping and lp depositing/withdrawing of fee-on-transfer tokens.
- Zapping in and out of a pool from any token (i.e. A->(B,C) or (B,C) -> A). A can be the same as B or C.
- Zapping and staking into a pool from any token. 

### FactoryRegistry

Registry of pool, gauge, bribe and managed rewards factories. Contains a default list of factories so swaps via the router will always work.  Used within Voter to validate new gauge creation.  Reusing the same pool factory address with a new gauge or new bribe rewards factory is not permitted.


## Token

### Aero

Standard ERC20 token. Minting permissions granted to Minter.

### VotingEscrow

The VotingEscrow contracts allow users to escrow their AERO tokens in an veAERO NFT. 
The (ERC-721 compliant) NFT has a balance which represents the voting weight of the
escrowed tokens, which decays linearly over time. Tokens can be locked for a maximum
of four years. veAERO NFT vote weights can be used to vote for pools, which in turn
determines the proportion of weekly emissions that go to each pool. VotingEscrow's
clock mode is timestamps (see EIP-6372). Metadata updates (EIP-4906) are also supported. 

There are three states that veAERO NFTs can be in: `NORMAL`, `LOCKED`, `MANAGED`.
`NORMAL` NFTs are the NFTs that users are familiar with. `Managed` NFTs are a new
type of NFT (see below). When a user deposits a normal NFT into a managed NFT, it
becomes a `LOCKED` NFT. `NORMAL` NFTs are not restricted in functionality whereas
`LOCKED` NFTs have extremely restricted functionality and `MANAGED` NFTs have
limited functionality. Managed NFT deposits and withdrawals are handled by `Voter`.

Normal NFTs can also be in a new state that is known as a permanent lock. While 
permanently locked, normal NFTs will have voting power that will be equal to the
amount of veAERO that was locked to create it. The NFT's voting power will also
not decay. Permanent locks can be unlocked as long as you have not voted that epoch. 
Managed NFTs are permanent locks by default.

Standard Operations:
All of these operations require ownership of the underlying NFT or tokens being escrowed. 
- Can create a NFT by escrowing AERO tokens and "locking" them for a time period.
- Can do anything with the NFT as supported by the ERC-721 interface (requires normal or managed NFT).
- Can merge one NFT into another (requires normal NFT for `from`, but can be normal permanent for `to`).
- Can split a single NFT into two new NFTs (requires normal or normal permanent NFT).  The NFT to be split is burned.  
    - By permissioning split to an address, any normal NFTs owned by the address are able to be split.
    - Split is initially permissioned by address and can be toggled on/off (requires team).
    - In addition, there are split toggle on/off permissions protocol-wide (requires team)
- Can withdraw escrowed AERO tokens once the NFT lock expires (requires normal NFT). 
- Can add to an existing NFT position by escrowing additional AERO tokens (requires normal or normal permanent or managed NFT).
- Can increase the lock duration of an NFT (and thus increasing voting power, requires normal NFT).
- Can permanent lock a NFT to lock its voting power at the maximum and prevent decay (requires normal NFT).
- Can unlock a permanently locked NFT to allow its voting power to decay (requires normal permanent NFT).
- Can delegate votes to other `tokenId`s for use in Protocol governance to other addresses based on voting power (requires normal permanent or managed NFT). Voting power retrieved from `getVotes` and `getPastVotes` does not reveal locked amount balances and are used only for voting. 

See `VOTINGESCROW.md` for a visual respresentation.

In addition, the protocol supports "managed NFTs" (also known as an "(m)veNFT") which aggregates NFT voting power whilst perpetually locking the underlying tokens. These NFTs function as a single NFT, with rewards accrued by the NFT going to the manager, who can then distribute (net of fees) to the depositors. These NFTs are permanently locked by default.
- NFTs can exist in one of three states: normal, locked or managed. By default, they are in normal state.
- Only governance or an allowed manager can create managed NFTs, special NFTs in the managed state.
- Managed NFTs can be deactivated, a process which prevents the NFT from voting and from receiving deposits (requires emergency council).
- An NFT can deposit into one managed NFT at a time, converting it from normal state to locked state. 
- The deposited NFT can be withdrawn at any time, with its balance restored and locktime extended to the maximum (4 years). Any rebases collected by the manager will be distributed pro-rata to the user. 
- For (m)veNFT implementations, refer to the official [repository](https://github.com/aerodrome-finance/relay/AutoCompounder).

### Minter

The minting contract handles emissions for the protocol. Emissions
start at 15m per epoch, decaying at a rate of 1% per epoch. Rebases (which are
sent to `RewardsDistributor`) are added on top of the base emissions to produce
the total emission. 

The minter has a modified emissions schedule that turns on once emissions fall
below 6m per epoch (~92 epochs). After it turns on, weekly emissions will become
a percentage of circulating supply, with the initial percentage starting at 30 basis
points (i.e. 0.003). Every epoch, the emissions can be modified by one basis point
with a vote conducted by `EpochGovernor`. See `EpochGovernor` for information on the vote. 

## RewardsDistributor

Standard Curve-fee distribution contract, modified for use with rebases. Rebases 
are calculated based on the locked and unlocked AERO one second prior to epoch flip.
veNFTs will earn rebases proportionally based on their contribution to the total locked
AERO. Rebase claims against expired veNFTs will be distributed as unlocked AERO to the 
owner of the veNFT. 

## VeArtProxy

ve(NFT) art proxy contract, exists for upgradability purposes.

## AirdropDistributor
The Airdrop distribution contract handles the emissions of permanently locked veNFTs.
These distributions can only be emitted by its deployer and its parameters are in the form of
arrays of addresses and amounts, which are later paired together and used to distribute each
amount to its corresponding address.

## Protocol

### Voter

The `Voter` contract is in charge of managing votes, emission distribution
as well as gauge creation in the protocol ecosystem. Votes can be cast once 
per epoch via Voter, with the votes earning NFT owners both bribes and fees 
from the pool they voted for. Voting can take place at any time during an epoch
except during the first and last hour of that epoch. Distributions to gauges will 
take place at the beginning of every epoch. In the last hour prior to epoch flip, 
only approved NFTs can vote. 

In addition, `Voter` also provides support for depositing and withdrawing from 
managed NFTs. Voting and depositing into a managed NFT are mutually exclusive 
(i.e. you may only do one per epoch). In the same way you cannot reset your NFT 
in the same epoch that you vote, you also cannot withdraw your NFT in the same 
epoch that you deposited.

Voting power of a managed NFT syncs every time a normal NFT is deposited or withdrawn into it.  In the 
event the managed NFT has its' last remaining normal NFT withdrawn, the vote of the managed NFT will be reset.  If
the managed NFT had already voted in the epoch, the vote will reset and the managed NFT will have the ability to re-vote if
a normal veNFT is locked into the managed veNFT.

`Voter` is in charge of creating and mantaining gauge liveness states. Gauges that 
are killed will not receive emissions. Once per epoch, the corresponding gauge for 
a pool will receive emissions from `Voter` proportionate to the amount of votes they 
receive. Voter also contains several utility functions that make claiming rewards or 
distributing emissions easier. 

In the first hour of every epoch, the ability to `vote`, `poke`, `reset`, `depositManaged`
or `withdrawManaged` is disabled to allow distributions to take place. Voting is also disabled
in the last hour of every epoch. However, certain privileged NFTs will be able to vote
in this one hour window.

Standard Operations:
- Can vote with an NFT once per epoch if you did not deposit into a managed NFT that epoch. 
- Can deposit into a managed NFT once per epoch if you did not vote that epoch (requires normal NFT). Depositing into a managed NFT is disabled in the last hour prior to epoch flip.
- Can reset an NFT at any time after the epoch that you voted. Your ability to vote or deposit into a managed NFT in the week that you reset is preserved.
- Can withdraw from a managed NFT at any time after the epoch that you deposited into a managed NFT (requires locked NFT). Your ability to vote or deposit into a managed NFT is preserved. 
- Can poke an NFT. This updates the balance of that NFT in the rewards contracts. 
- Can bulk claim rewards (i.e. bribes + fees), bribes or fees. 
- Can distribute that epoch's emissions to pools.
- Can create gauge and reward contracts for a pool (must be a pool created as a part of the protocol).

### Gauge

The gauge contract is a standard rewards contract in charge of distributing emissions to LP depositors. Users that deposit LP tokens can forgo their fee reward in exchange for a proportional distribution of emissions (proportional to their share of LP deposits in the gauge). The fee rewards that the LP depositors forgo are transferred to the `FeeVotingReward` contract. 

Standard Operations:
- Can deposit LP tokens.
- Can deposit LP tokens for another receipient. 
- Can withdraw LP tokens. 
- Can get emission rewards for an account. 
- Can deposit emissions into gauge (requires `Voter`).

### Reward

The base reward contract for all reward contracts. Individual voting balance checkpoints and total supply checkpoints are created in a reward contract whenever a user votes for a pool. Checkpoints do not automatically update when voting power decays (requires `Voter.poke`). Rewards in these contracts are distributed proportionally to an NFT's voting power contribution to a pool. An NFT is distributed rewards in each epoch proportional to its voting power contribution in that epoch. 

### VotingReward

Voting rewards are rewards that accrue to users that vote for a specific pool. They can be broken down into fees and bribes.

### FeesVotingReward

The fee voting reward derives from the fees relinquished by LP depositors 
depositing their LP token in to the gauge. These fees are synchronized with bribes
and accrue in the same way. Thus, fees that accrue during epoch `n` will be 
distributed to voters of that pool in epoch `n+1`.

### BribeVotingReward

Bribe voting rewards are externally deposited rewards of whitelisted tokens (see `Voter`) used to incentivize users to vote for a given pool. 

### ManagedReward

Managed rewards are rewards that accrue to users that deposited their voting power into a managed NFT. 

### LockedManagedReward

Locked rewards are AERO token rewards that have been compounded into the managed NFT (usually rebases but can also include non-AERO rewards that have converted to AERO to be compounded into the NFT). This contract functions similar to `PoolFees`, as it separates "reward" AERO from the "locked" VotingEscrow AERO. These rewards are not distributed and are returned to `VotingEscrow` when a user withdraws their NFT from a managed NFT. 

### FreeManagedReward

Free rewards are rewards that have been distributed to users depositing into a managed NFT. Any rewards earned by a managed NFT that a manager passes on will be distributed to the users that deposited into the managed NFT.


## Governance

### ProtocolGovernor

Lightly modified from OpenZeppelin's Governor contract. Enables governance by using 
timestamp based voting power from VotingEscrow NFTs. Includes support for vetoing of 
proposals as mitigation against 51% attacks. `proposalHash` has also been modified to 
include the `proposer` to prevent griefing attacks from proposal frontrunning. Votes
are cast and counted on a per `tokenId` basis.

### EpochGovernor

An epoch based governance contract modified lightly from OpenZeppelin's Governor
contract to exclude the `cancel` function. It has been modified in such a way 
that it continues to adhere with OpenZeppelin's `IGovernor` interface. Once tail
emissions in the `Minter` are turned on, every epoch a proposal can be created
to either increase, hold or decrease the Minter's emission for the following 
epoch. The winning decision is selected via simple majority (also known as [plurality](https://en.wikipedia.org/wiki/Plurality_(voting))). Also uses timestamp based voting power 
from VotingEscrow NFTs. Note that the very first nudge proposal must be initiated in 
the epoch prior to the tail emission schedule starting. Votes are cast and counted
on a per `tokenId` basis.

Notable changes:
- No quorum.
- No proposal threshold.
- Cannot relay via the governor. 
- Can only make a single proposal per epoch, to adjust the emissions in Minter once tail emissions have turned on. 
- A proposal created in epoch `n` will be executable in epoch `n+1` once the proposal voting period has gone through.
- Has three options (similar to Governor Bravo). The winner is selected based on which option has the most absolute votes at the end of the voting period. 
- The proposer of a proposal cannot cancel the proposal.
