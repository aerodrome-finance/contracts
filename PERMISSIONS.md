# Protocol Access Control
## User Roles and Abilities
### Anyone
- Can swap tokens through the Protocol DEX.
- Can provide liquidity.
- Can create a Normal veNFT.
- Can deposit AERO into an existing Normal veNFT.
- Can poke the balance of an existing veNFT to sync the balance.
- Can bribe a liquidity pool through its' linked BribeVotingRewards contract.
- Can skim a stable or volatile liquidity pool to rebalance the reserves.
- Can sync a liquidity pool to record historical price
- Can trigger the emission of AERO at the start of an epoch
- Can create a liquidity pool with two different ERC20 tokens if the pool is not already created
- Can create a gauge for the liquidity pool if the gauge is not already created and the tokens are whitelisted

### Liquidity provider (LP)
- Can deposit their LP token into the Protocol gauge linked to the liquidity pool
    - Earns AERO emissions

### veNFT Hodler
- For a detailed breakdown refer to [VOTINGESCROW.md](https://github.com/aerodrome-finance/contracts/blob/main/VOTINGESCROW.md)

#### Normal, Normal Permanent, and Managed veNFT
- Can approve/revoke an address to modify the veNFT
- Can transfer ownership of the veNFT
- Can increase amount locked
- Can vote weekly on pool(s)
    - Earns bribes and trading fees
    - Earns weekly distribution of AERO rebases
- Can vote on ProtocolGovernor proposals
- Can vote on EpochGovernor proposals

#### Normal veNFT
- Can withdraw the normal veNFT
- Can convert to/from Permanent state
- Can increase the lock time

#### Normal and Normal Permanent veNFT
- Can split the veNFT
- Can merge the veNFT

#### Normal Permanent and Managed veNFT
- Can delegate voting power 

#### Locked veNFT
- Can only withdraw their Locked veNFT from a Managed veNFT

---

## Admin Roles and Abilities
### Who

#### Protocol Team
 Multisig at [0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5](https://optimistic.etherscan.io/address/0xBA4BB89f4d1E66AA86B60696534892aE0cCf91F5)
- Threshold: 3/7
- TODO: Who owns every address?

#### EmergencyCouncil
Multisig at [0x838352F4E3992187a33a04826273dB3992Ee2b3f](https://optimistic.etherscan.io/address/0x838352F4E3992187a33a04826273dB3992Ee2b3f)
- Threshold: 5/6
- TODO: Who owns every address?

#### Vetoer
Protocol team at deployment of ProtocolGovernor. At a later date, this role will be renounced.

#### ProtocolGovernor (aka. Governor)
At first deployment, team. At a later date, this will be set to a lightly modified [Governor](https://docs.openzeppelin.com/contracts/4.x/api/governance#governor) contract from OpenZeppelin, [ProtocolGovernor](https://github.com/aerodrome-finance/contracts/blob/main/contracts/ProtocolGovernor.sol).

#### EpochGovernor
At first deployment, team. Before the tail rate of emissions is reached, this will be set to [EpochGovernor](https://github.com/aerodrome-finance/contracts/blob/main/contracts/EpochGovernor.sol).

#### Allowed Manager
At first deployment, team. This role will likely be given to a contract so that it can create managed nfts (e.g. for autocompounders etc)

#### Fee Manager
Protocol team

#### Pauser
Protocol team

#### Factory Registry Owner
Protocol team

## Permissions List
This is an exhaustive list of all admin permissions in the protocol, sorted by the contract they are stored in.

#### [PoolFactory](https://optimistic.etherscan.io/address/0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a#code)
- Pauser
    - Controls pause state of swaps on UniswapV2 pools created by this factory.  Users are still freely able to add/remove liquidity
    - Can set Pauser role
- FeeManager
    - Controls default and custom fees for stable / volatile pools.

#### [FactoryRegistry](https://optimistic.etherscan.io/address/0xF4c67CdEAaB8360370F41514d06e32CcD8aA1d7B#code)
- Owner
    - Can approve / unapprove new pool / gauge / reward factory combinations.
    - This is used to add new pools, gauges or reward factory combinations. These new pools / gauges / rewards factories may have different code to existing implementations.

#### [Minter](https://optimistic.etherscan.io/address/0x6dc9E1C04eE59ed3531d73a72256C0da46D10982#code)
- Team
    - Can set PendingTeam in Minter
    - Can accept itself as team in Minter (requires being set as pendingTeam by previous team)
    - Can set team rate in Minter
- EpochGovernor
    - Can nudge the Minter to adjust the AERO emissions rate.

#### [ProtocolGovernor](TODO: live etherscan link)
- Vetoer
    - Can set vetoer in ProtocolGovernor.
    - Can veto proposals.
    - Can renounce vetoer role.

#### [Voter](https://optimistic.etherscan.io/address/0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C#code)
- Governor
    - Can set governor in Voter.
    - Can set epochGovernor in Voter.
    - Can create a gauge for an address that is not a pool.
    - Can set the maximum number of pools that one can vote on.
    - Can whitelist a token to be used as a reward token in voting rewards or in managed free rewards.
    - Can whitelist an NFT to vote during the privileged epoch window.
    - Can create managed NFTs in VotingEscrow.
    - Can set allowedManager in VotingEscrow.
    - Can activate or deactivate managed NFTs in VotingEscrow.
- EpochGovernor
    - Can execute one proposal per epoch to adjust the AERO emission rate after the tail emission rate has been reached in Minter.
- EmergencyCouncil
    - Can set emergencyCouncil in Voter.
    - Can kill a gauge.
    - Can revive a gauge.
    - Can set a custom name or symbol for a Uniswap V2 pool.
    - Can activate or deactivate managed NFTs in VotingEscrow.

#### [VotingEscrow](https://optimistic.etherscan.io/address/0xFAf8FD17D9840595845582fCB047DF13f006787d#code)
- Team
    - Can set team in VotingEscrow
    - Can set artProxy in VotingEscrow.
    - Can enable split functionality for a single address.
    - Can enable split functionality for all addresses.
    - Can set proposalNumerator in ProtocolGovernor.
- AllowedManager
    - Can create managed NFTs in VotingEscrow.


## Contract Roles and Abilities
In addition to defined admin roles, various contracts within the protocol have unique permissions in calling other contracts.  These permissions are immutable.

#### [Minter](https://optimistic.etherscan.io/address/0x6dc9E1C04eE59ed3531d73a72256C0da46D10982#code)
- Can mint AERO and distribute to Voter for gauge emissions and RewardsDistributor for claimable rebases
    - `Minter.updatePeriod()`

#### [Voter](https://optimistic.etherscan.io/address/0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C#code)
- Can distribute AERO emissions to gauges
    - `Voter.distribute()`
- Can claim fees and rewards earned by Normal veNFTs
    - `Voter.claimFees()`
    - `Voter.claimBribes()`
- Can deposit a Normal veNFT into a Managed veNFT
    - `Voter.depositManaged()`
- Can withdraw a Locked veNFT from a Managed veNFT
    - `Voter.withdrawManaged()`
- Can set voting status of a veNFT
    - `Voter.vote()`
    - `Voter.reset()`
- Can deposit and withdraw balances from `BribeVotingReward` and `FeesVotingReward`
    - `Voter.vote()`
    - `Voter.reset()`

#### [VotingEscrow](https://optimistic.etherscan.io/address/0xFAf8FD17D9840595845582fCB047DF13f006787d#code)
- Can deposit balances into `LockedManagedReward`
    - `VotingEscrow.depositManaged()`
- Can deposit balances into `FreeManagedReward`
    - `VotingEscrow.depositManaged()`
- Can withdraw balances from `LockedManagedReward` and `FreeManagedReward`, and rewards earned from `LockedManagedReward`
    - `VotingEscrow.withdrawManaged()`
- Can notify rewards to `LockedManagedReward`. These rewards are always in AERO.
    - `VotingEscrow.increaseAmount()`
    - `VotingEscrow.depositFor()`

#### [Pool](https://optimistic.etherscan.io/address/0x95885af5492195f0754be71ad1545fe81364e531#code)
- Can claim the fees accrued from trades
    - `Pool.claimFees()`