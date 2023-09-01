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
 Multisig at [0xE6A41fE61E7a1996B59d508661e3f524d6A32075](https://basescan.org/address/0xe6a41fe61e7a1996b59d508661e3f524d6a32075)

#### EmergencyCouncil
Multisig at [0x99249b10593fCa1Ae9DAE6D4819F1A6dae5C013D](https://basescan.org/address/0x99249b10593fCa1Ae9DAE6D4819F1A6dae5C013D)
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

#### [PoolFactory](https://basescan.org/address/0x420DD381b31aEf6683db6B902084cB0FFECe40Da#code)
- Pauser
    - Controls pause state of swaps on UniswapV2 pools created by this factory.  Users are still freely able to add/remove liquidity
    - Can set Pauser role
- FeeManager
    - Controls default and custom fees for stable / volatile pools.

#### [FactoryRegistry](https://basescan.org/address/0x5C3F18F06CC09CA1910767A34a20F771039E37C0#code)
- Owner
    - Can approve / unapprove new pool / gauge / reward factory combinations.
    - This is used to add new pools, gauges or reward factory combinations. These new pools / gauges / rewards factories may have different code to existing implementations.

#### [Minter](https://basescan.org/address/0xeB018363F0a9Af8f91F06FEe6613a751b2A33FE5#code)
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

#### [Voter](https://basescan.org/address/0x16613524e02ad97eDfeF371bC883F2F5d6C480A5#code)
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

#### [VotingEscrow](https://basescan.org/address/0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4#code)
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

#### [Minter](https://basescan.org/address/0xeB018363F0a9Af8f91F06FEe6613a751b2A33FE5#code)
- Can mint AERO and distribute to Voter for gauge emissions and RewardsDistributor for claimable rebases
    - `Minter.updatePeriod()`

#### [Voter](https://basescan.org/address/0x16613524e02ad97eDfeF371bC883F2F5d6C480A5#code)
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

#### [VotingEscrow](https://basescan.org/address/0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4#code)
- Can deposit balances into `LockedManagedReward`
    - `VotingEscrow.depositManaged()`
- Can deposit balances into `FreeManagedReward`
    - `VotingEscrow.depositManaged()`
- Can withdraw balances from `LockedManagedReward` and `FreeManagedReward`, and rewards earned from `LockedManagedReward`
    - `VotingEscrow.withdrawManaged()`
- Can notify rewards to `LockedManagedReward`. These rewards are always in AERO.
    - `VotingEscrow.increaseAmount()`
    - `VotingEscrow.depositFor()`

#### [Pool](https://basescan.org/address/0xA4e46b4f701c62e14DF11B48dCe76A7d793CD6d7#code)
- Can claim the fees accrued from trades
    - `Pool.claimFees()`