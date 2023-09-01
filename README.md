# Protocol

All contracts for the Protocol, an AMM on EVMs inspired by Solidly.

See `SPECIFICATION.md` for more detail.

## Protocol Overview

### AMM contracts

| Filename | Description |
| --- | --- |
| `Pool.sol` | AMM constant-product implementation similar to Uniswap V2 liquidity pools |
| `Router.sol` | Handles multi-pool swaps, deposit/withdrawal, similar to Uniswap V2 Router interface |
| `PoolFees.sol` | Stores the liquidity pool trading fees, these are kept separate from the reserves |
| `ProtocolLibrary.sol` | Provides router-related helpers, eg. for price-impact calculations |
| `FactoryRegistry.sol` | Registry of factories approved for creation of pools, gauges, bribes and managed rewards. |

### Tokenomy contracts

| Filename | Description |
| --- | --- |
| `Aero.sol` | Protocol ERC20 token |
| `VotingEscrow.sol` | Protocol ERC-721 (ve)NFT representing the protocol vote-escrow lock. Beyond standard ve-type functions, there is also the ability to merge, split and create managed nfts. |
| `Minter.sol` | Protocol token minter. Distributes emissions to `Voter.sol` and rebases to `RewardsDistributor.sol`. |
| `RewardsDistributor.sol` | Is used to handle the rebases distribution for (ve)NFTs/lockers. |
| `VeArtProxy.sol` | (ve)NFT art proxy contract, exists for upgradability purposes |
| `AirdropDistributor.sol` | Distributes permanently locked (ve)NFTs to the provided addresses, in the desired amounts. |

### Protocol mechanics contracts

| Filename | Description |
| --- | --- |
| `Voter.sol` | Handles votes for the current epoch, gauge and voting reward creation as well as emission distribution to `Gauge.sol` contracts. |
| `Gauge.sol` | Gauges are attached to a Pool and based on the (ve)NFT votes it receives, it distributes proportional emissions in the form of protocol tokens. Deposits to the gauge take the form of LP tokens for the Pool. In exchange for receiving protocol emissions, claims on fees from the pool are relinquished to the gauge. Standard rewards contract. |
| `rewards/` | |
| `Reward.sol` | Base reward contract to be inherited for distribution of rewards to stakers.
| `VotingReward.sol` | Rewards contracts used by `FeesVotingReward.sol` and `BribeVotingReward.sol` which inherits `Reward.sol`. Rewards are distributed in the following epoch proportionally based on the last checkpoint created by the user, and are earned through "voting" for a pool or gauge. |
| `FeesVotingReward.sol` | Stores LP fees (from the gauge via `PoolFees.sol`) to be distributed for the current voting epoch to it's voters. |
| `BribeVotingReward.sol` | Stores the users/externally provided rewards for the current voting epoch to it's voters. These are deposited externally every week. |
| `ManagedReward.sol` | Staking implementation for managed veNFTs used by `LockedManagedReward.sol` and `FreeManagedReward.sol` which inherits `Reward.sol`.  Rewards can be earned passively by veNFTs who delegate their voting power to a "managed" veNFT.
| `LockedManagedReward.sol` | Handles "locked" rewards (i.e. Aero rewards / rebases that are compounded) for managed NFTs. Rewards are not distributed and only returned to `VotingEscrow.sol` when the user withdraws from the managed NFT. | 
| `FreeManagedReward.sol` | Handles "free" (i.e. unlocked) rewards for managed NFTs. Any rewards earned by a managed NFT that a manager passes on will be distributed to the users that deposited into the managed NFT. | 

### Governance contracts

| Filename | Description |
| --- | --- |
| `ProtocolGovernor.sol` | OpenZeppelin's Governor contracts used in protocol-wide access control to whitelist tokens for trade  within the protocol, update minting emissions, and create managed veNFTs. |
| `EpochGovernor.sol` | A simple epoch-based governance contract used exclusively for adjusting emissions. |


## Testing

This repository uses Foundry for testing and deployment. 

Foundry Setup

```
forge install
forge build
forge test
```

## Base Mainnet Fork Tests

In order to run mainnet fork tests against base, inherit `BaseTest` in `BaseTest.sol` in your new class and set the `deploymentType` variable to `Deployment.FORK`. The `BASE_RPC_URL` field must be set in `.env`. Optionally, `BLOCK_NUMBER` can be set in the `.env` file or in the test file if you wish to test against a consistent fork state (this will make tests faster).


## Lint

`yarn format` to run prettier.

`yarn lint` to run solhint (currently disabled in CI).

## Deployment

See `script/README.md` for more detail.

### Access Control
See `PERMISSIONS.md` for more detail.

## Deployment

| Name               | Address                                                                                                                               |
| :----------------- | :------------------------------------------------------------------------------------------------------------------------------------ |
| ArtProxy               | [0xE9992487b2EE03b7a91241695A58E0ef3654643E](https://basescan.org/address/0xE9992487b2EE03b7a91241695A58E0ef3654643E#code) |
| RewardsDistributor               | [0x227f65131A261548b057215bB1D5Ab2997964C7d](https://basescan.org/address/0x227f65131A261548b057215bB1D5Ab2997964C7d#code) |
| FactoryRegistry               | [0x5C3F18F06CC09CA1910767A34a20F771039E37C0](https://basescan.org/address/0x5C3F18F06CC09CA1910767A34a20F771039E37C0#code) |
| Forwarder               | [0x15e62707FCA7352fbE35F51a8D6b0F8066A05DCc](https://basescan.org/address/0x15e62707FCA7352fbE35F51a8D6b0F8066A05DCc#code) |
| GaugeFactory               | [0x35f35cA5B132CaDf2916BaB57639128eAC5bbcb5](https://basescan.org/address/0x35f35cA5B132CaDf2916BaB57639128eAC5bbcb5#code) |
| ManagedRewardsFactory               | [0xFdA1fb5A2a5B23638C7017950506a36dcFD2bDC3](https://basescan.org/address/0xFdA1fb5A2a5B23638C7017950506a36dcFD2bDC3#code) |
| Minter               | [0xeB018363F0a9Af8f91F06FEe6613a751b2A33FE5](https://basescan.org/address/0xeB018363F0a9Af8f91F06FEe6613a751b2A33FE5#code) |
| PoolFactory               | [0x420DD381b31aEf6683db6B902084cB0FFECe40Da](https://basescan.org/address/0x420DD381b31aEf6683db6B902084cB0FFECe40Da#code) |
| Router               | [0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43](https://basescan.org/address/0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43#code) |
| AERO               | [0x940181a94A35A4569E4529A3CDfB74e38FD98631](https://basescan.org/address/0x940181a94A35A4569E4529A3CDfB74e38FD98631#code) |
| Voter               | [0x16613524e02ad97eDfeF371bC883F2F5d6C480A5](https://basescan.org/address/0x16613524e02ad97eDfeF371bC883F2F5d6C480A5#code) |
| VotingEscrow               | [0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4](https://basescan.org/address/0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4#code) |
| VotingRewardsFactory               | [0x45cA74858C579E717ee29A86042E0d53B252B504](https://basescan.org/address/0x45cA74858C579E717ee29A86042E0d53B252B504#code) |
| Pool               | [0xA4e46b4f701c62e14DF11B48dCe76A7d793CD6d7](https://basescan.org/address/0xA4e46b4f701c62e14DF11B48dCe76A7d793CD6d7#code) |

