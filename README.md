# ⚙️ Protocol

All contracts for **Protocol**, an AMM on EVMs inspired by **Solidly**.

See `SPECIFICATION.md` for detailed specifications.

---

## 🧩 Protocol Overview

### 🔄 AMM Contracts

| Filename | Description |
|-----------|-------------|
| `Pool.sol` | Constant-product AMM implementation similar to Uniswap V2 liquidity pools. |
| `Router.sol` | Handles multi-pool swaps, deposits, and withdrawals (similar to Uniswap V2 Router). |
| `PoolFees.sol` | Stores liquidity pool trading fees separately from reserves. |
| `ProtocolLibrary.sol` | Provides router helper functions for price-impact calculations. |
| `FactoryRegistry.sol` | Registry for approved factories that can create pools, gauges, bribes, and managed rewards. |

---

### 💰 Tokenomy Contracts

| Filename | Description |
|-----------|-------------|
| `Aero.sol` | Protocol ERC-20 token. |
| `VotingEscrow.sol` | ERC-721 (ve)NFT representing the vote-escrow lock. Supports merging, splitting, and creating managed NFTs. |
| `Minter.sol` | Distributes emissions to `Voter.sol` and rebases to `RewardsDistributor.sol`. |
| `RewardsDistributor.sol` | Handles rebases distribution for (ve)NFTs/lockers. |
| `VeArtProxy.sol` | Proxy contract for upgradable (ve)NFT art rendering. |
| `AirdropDistributor.sol` | Distributes permanently locked (ve)NFTs to specified addresses in fixed amounts. |

---

### 🧠 Protocol Mechanics Contracts

| Filename | Description |
|-----------|-------------|
| `Voter.sol` | Handles epoch voting, gauge/reward creation, and emission distribution to `Gauge.sol`. |
| `Gauge.sol` | Attaches to a pool and distributes emissions based on (ve)NFT votes. Accepts LP tokens and manages reward distribution. |
| `rewards/` | Directory containing reward-related contracts. |
| `Reward.sol` | Base reward contract for distribution logic inheritance. |
| `VotingReward.sol` | Used by `FeesVotingReward.sol` and `BribeVotingReward.sol` for distributing rewards based on previous epoch checkpoints. |
| `FeesVotingReward.sol` | Stores LP fees (from `PoolFees.sol`) for distribution in the next epoch. |
| `BribeVotingReward.sol` | Stores externally provided bribes for distribution each week to pool voters. |
| `ManagedReward.sol` | Staking implementation for managed (ve)NFTs, inherited by `LockedManagedReward.sol` and `FreeManagedReward.sol`. |
| `LockedManagedReward.sol` | Handles **locked** rewards (compounded AERO rewards) for managed NFTs. Rewards are returned only upon withdrawal. |
| `FreeManagedReward.sol` | Handles **free** (unlocked) rewards for managed NFTs, distributing them to depositors. |

---

### 🏛️ Governance Contracts

| Filename | Description |
|-----------|-------------|
| `ProtocolGovernor.sol` | OpenZeppelin-based governor contract managing protocol-wide access control, emission updates, and managed veNFT creation. |
| `EpochGovernor.sol` | Simple epoch-based governor contract for emission adjustments. |

---

## 🧪 Testing

This repository uses **Foundry** for testing and deployment.

### 🧰 Foundry Setup

```bash
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

## Licensing

This project follows the [Apache Foundation](https://infra.apache.org/licensing-howto.html)
guideline for licensing. See LICENSE and NOTICE files.

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

