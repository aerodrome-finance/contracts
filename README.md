# Protocol

All smart contracts for the **Protocol**, an AMM (Automated Market Maker) deployed on EVM chains, inspired by **Solidly**.

For complete technical details, see [`SPECIFICATION.md`](./SPECIFICATION.md).

---

## Protocol Overview

### AMM Contracts

| Filename | Description |
| --- | --- |
| `Pool.sol` | Implements a constant-product AMM similar to Uniswap V2 liquidity pools. |
| `Router.sol` | Manages multi-pool swaps, deposits, and withdrawals. Implements Uniswap V2–style router logic. |
| `PoolFees.sol` | Tracks and stores trading fees separately from liquidity reserves. |
| `ProtocolLibrary.sol` | Utility library with router-related helpers (e.g. price-impact calculations). |
| `FactoryRegistry.sol` | Maintains a registry of approved factories for pools, gauges, bribes, and managed rewards. |

---

### Tokenomics Contracts

| Filename | Description |
| --- | --- |
| `Aero.sol` | Core ERC-20 protocol token. |
| `VotingEscrow.sol` | ERC-721 vote-escrow (ve)NFT for time-locked staking, supporting merge/split and managed NFT creation. |
| `Minter.sol` | Controls token emissions and distributes to `Voter.sol` and `RewardsDistributor.sol`. |
| `RewardsDistributor.sol` | Handles distribution of rebased rewards to veNFT holders. |
| `VeArtProxy.sol` | Proxy contract for veNFT artwork (upgradeable). |
| `AirdropDistributor.sol` | Distributes permanently locked veNFTs to specified addresses and amounts. |

---

### Protocol Mechanics Contracts

| Filename | Description |
| --- | --- |
| `Voter.sol` | Manages epoch-based voting, gauge creation, and emission distribution to `Gauge.sol`. |
| `Gauge.sol` | Links to liquidity pools; receives emissions proportional to veNFT votes. Holds LP deposits, forfeiting pool fees in exchange for emissions. |
| `Reward.sol` | Base rewards contract to be inherited for distributing staking rewards. |
| `VotingReward.sol` | Used by `FeesVotingReward.sol` and `BribeVotingReward.sol` for distributing epoch-based rewards to voters. |
| `FeesVotingReward.sol` | Stores LP fees from gauges to distribute to voters during the active epoch. |
| `BribeVotingReward.sol` | Holds externally funded rewards (“bribes”) to distribute weekly to pool voters. |
| `ManagedReward.sol` | Base staking logic for managed veNFTs, extended by `LockedManagedReward.sol` and `FreeManagedReward.sol`. |
| `LockedManagedReward.sol` | Handles “locked” rewards (e.g., Aero emissions) that compound within managed NFTs. |
| `FreeManagedReward.sol` | Handles “free” rewards that can be withdrawn by users staking within managed NFTs. |

---

### Governance Contracts

| Filename | Description |
| --- | --- |
| `ProtocolGovernor.sol` | Based on OpenZeppelin’s Governor; manages protocol-wide whitelisting, emissions updates, and managed veNFT creation. |
| `EpochGovernor.sol` | Simplified epoch-based governor, primarily for emissions adjustments. |

---

## Development and Testing

This repository uses **Foundry** for development, testing, and deployment.

### Setup

```bash
forge install
forge build
forge test


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

