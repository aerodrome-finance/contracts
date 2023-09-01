## Deploy Protocol

The Protocol deployment is a multi-step process.  Unlike testing, we cannot impersonate governance to submit transactions and must wait on the necessary protocol actions to complete setup.  This README goes through the necessary instructions to deploy the protocol.

### Environment setup
1. Copy-pasta `.env.sample` into a new `.env` and set the environment variables. `PRIVATE_KEY_DEPLOY` is the private key to deploy all scripts.
2. Copy-pasta `script/constants/TEMPLATE.json` into a new file `script/constants/{CONSTANTS_FILENAME}`. For example, "Base.json" in the .env would be a file of `script/constants/Base.json`.  Set the variables in the new file.
3. Copy-pasta `script/constants/AirdropTEMPLATE.json` into a new file `script/constants/{AIRDROPS_FILENAME}`. For example, "Airdrop.json" in the .env would be a file of `script/constants/Airdrop.json`.  Set the addresses and amounts in this file to setup the Airdrops to be distributed.

4. Run tests to ensure deployment state is configured correctly:
```ml
forge init
forge build
forge test
```

*Note that this will create a `script/constants/output/{OUTPUT_FILENAME}` file with the contract addresses created in testing.  If you are using the same constants for multiple deployments (for example, deploying in a local fork and then in prod), you can rename `OUTPUT_FILENAME` to store the new contract addresses while using the same constants.

5. Ensure all deployments are set properly. In project directory terminal:
```
source .env
```

### Deployment
- Note that if deploying to a chain other than Base/Base Goerli, if you have a different .env variable name used for `RPC_URL`, `SCAN_API_KEY` and `ETHERSCAN_VERIFIER_URL`, you will need to use the corresponding chain name by also updating `foundry.toml`.  For this example we're deploying onto Base.

1. Deploy the Protocol Core
```
forge script script/DeployCore.s.sol:DeployCore --broadcast --slow --rpc-url base --verify -vvvv
```
2. Accept pending team as team. This needs to be done by the `minter.pendingTeam()` address. Within the deployed `Minter` contract call `acceptTeam()`.

3. Deploy gauges and pools.  These gauges are built on the Protocol using the newly created pools.
```
forge script script/DeployGaugesAndPools.s.sol:DeployGaugesAndPools --broadcast --slow --rpc-url base --verify -vvvv
```

4. Distribute locked NFTs using the AirdropDistributor. This needs to be done by the `airdrop.owner()` address.
```
forge script script/DistributeAirdrops.s.sol:DistributeAirdrops --broadcast --slow --gas-estimate-multiplier 200 --legacy --rpc-url base --verify -vvvv
```

5. Deploy governor contracts
```
forge script script/DeployGovernors.s.sol:DeployGovernors --broadcast --slow --rpc-url base --verify -vvvv
```
6.  Update the governor addresses.  This needs to be done by the `escrow.team()` address.  Within `voter`:
 - call `setEpochGovernor()` using the `EpochGovernor` address located in `script/constants/output/{OUTPUT_FILENAME}`
 - call `setGovernor()` using the `Governor` address located in the same file.

7. Accept governor vetoer status.  This also needs to be done by the `escrow.team()` address.  Within the deployed `Governor` contract call `acceptVetoer()`.
