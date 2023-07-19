# Velodrome

V2 contracts for Velodrome Finance, an AMM on Optimism inspired by Solidly.

See `SPECIFICATION.md` for more detail.

## Protocol Overview

### AMM contracts

| Filename | Description |
| --- | --- |
| `Pool.sol` | AMM constant-product implementation similar to Uniswap V2 liquidity pools |
| `Router.sol` | Handles multi-pool swaps, deposit/withdrawal, similar to Uniswap V2 Router interface |
| `PoolFees.sol` | Stores the liquidity pool trading fees, these are kept separate from the reserves |
| `VelodromeLibrary.sol` | Provides router-related helpers, eg. for price-impact calculations |
| `FactoryRegistry.sol` | Registry of factories approved for creation of pools, gauges, bribes and managed rewards. |

### Tokenomy contracts

| Filename | Description |
| --- | --- |
| `Velo.sol` | Protocol ERC20 token |
| `VotingEscrow.sol` | Protocol ERC-721 (ve)NFT representing the protocol vote-escrow lock. Beyond standard ve-type functions, there is also the ability to merge, split and create managed nfts. |
| `Minter.sol` | Protocol token minter. Distributes emissions to `Voter.sol` and rebases to `RewardsDistributor.sol`. |
| `RewardsDistributor.sol` | Is used to handle the rebases distribution for (ve)NFTs/lockers. |
| `VeArtProxy.sol` | (ve)NFT art proxy contract, exists for upgradability purposes |

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
| `LockedManagedReward.sol` | Handles "locked" rewards (i.e. Velo rewards / rebases that are compounded) for managed NFTs. Rewards are not distributed and only returned to `VotingEscrow.sol` when the user withdraws from the managed NFT. | 
| `FreeManagedReward.sol` | Handles "free" (i.e. unlocked) rewards for managed NFTs. Any rewards earned by a managed NFT that a manager passes on will be distributed to the users that deposited into the managed NFT. | 

### Governance contracts

| Filename | Description |
| --- | --- |
| `VeloGovernor.sol` | OpenZeppelin's Governor contracts used in protocol-wide access control to whitelist tokens for trade  within Velodrome, update minting emissions, and create managed veNFTs. |
| `EpochGovernor.sol` | A simple epoch-based governance contract used exclusively for adjusting emissions. |


## Testing

This repository uses Foundry for testing and deployment. 

Foundry Setup

```
forge install
forge build
forge test
```

## Optimism Mainnet Fork Tests

In order to run mainnet fork tests against optimism, inherit `BaseTest` in `BaseTest.sol` in your new class and set the `deploymentType` variable to `Deployment.FORK`. The `OPTIMISM_RPC_URL` field must be set in `.env`. Optionally, `BLOCK_NUMBER` can be set in the `.env` file or in the test file if you wish to test against a consistent fork state (this will make tests faster).


## Lint

`yarn format` to run prettier.

`yarn lint` to run solhint (currently disabled in CI).

## Deployment

See `script/README.md` for more detail.

## Security

For general information about security include audits, bug bounty and deployed contracts, go [here](https://velodrome.finance/security).

### Access Control
See `PERMISSIONS.md` for more detail.
### Bug Bounty
Velodrome has a live bug bounty hosted on ([Immunefi](https://immunefi.com/bounty/velodromefinance/)).

## Deployment

| Name               | Address                                                                                                                               |
| :----------------- | :------------------------------------------------------------------------------------------------------------------------------------ |
| ArtProxy               | [0x4A9eA0dd5649eC4B6745c60d1769e2184C1782DD](https://optimistic.etherscan.io/address/0x4A9eA0dd5649eC4B6745c60d1769e2184C1782DD#code) |
| RewardsDistributor               | [0x9D4736EC60715e71aFe72973f7885DCBC21EA99b](https://optimistic.etherscan.io/address/0x9D4736EC60715e71aFe72973f7885DCBC21EA99b#code) |
| FactoryRegistry               | [0xF4c67CdEAaB8360370F41514d06e32CcD8aA1d7B](https://optimistic.etherscan.io/address/0xF4c67CdEAaB8360370F41514d06e32CcD8aA1d7B#code) |
| Forwarder               | [0x06824df38D1D77eADEB6baFCB03904E27429Ab74](https://optimistic.etherscan.io/address/0x06824df38D1D77eADEB6baFCB03904E27429Ab74#code) |
| GaugeFactory               | [0x8391fE399640E7228A059f8Fa104b8a7B4835071](https://optimistic.etherscan.io/address/0x8391fE399640E7228A059f8Fa104b8a7B4835071#code) |
| ManagedRewardsFactory               | [0xcDd9585005095ac7447d1fDbC990C5CFB805cff0](https://optimistic.etherscan.io/address/0xcDd9585005095ac7447d1fDbC990C5CFB805cff0#code) |
| Minter               | [0x6dc9E1C04eE59ed3531d73a72256C0da46D10982](https://optimistic.etherscan.io/address/0x6dc9E1C04eE59ed3531d73a72256C0da46D10982#code) |
| PoolFactory               | [0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a](https://optimistic.etherscan.io/address/0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a#code) |
| Router               | [0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858](https://optimistic.etherscan.io/address/0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858#code) |
| VELO               | [0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db](https://optimistic.etherscan.io/address/0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db#code) |
| Voter               | [0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C](https://optimistic.etherscan.io/address/0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C#code) |
| VotingEscrow               | [0xFAf8FD17D9840595845582fCB047DF13f006787d](https://optimistic.etherscan.io/address/0xFAf8FD17D9840595845582fCB047DF13f006787d#code) |
| VotingRewardsFactory               | [0x756E7C245C69d351FfFBfb88bA234aa395AdA8ec](https://optimistic.etherscan.io/address/0x756E7C245C69d351FfFBfb88bA234aa395AdA8ec#code) |
| Pool               | [0x95885af5492195f0754be71ad1545fe81364e531](https://optimistic.etherscan.io/address/0x95885af5492195f0754be71ad1545fe81364e531#code) |

