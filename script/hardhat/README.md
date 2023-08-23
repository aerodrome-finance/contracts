# Hardhat Deployment Instructions

Hardhat support was included as a way to provide an easy way to test the contracts on Tenderly with contract verification. 

## Set Up

1. Create a new fork on Tenderly. Once you have the fork, copy the fork id number (the component after `/fork`/ in the URL) and set it as your `TENDERLY_FORK_ID` in the `.env` file. The other fields that must be set include `PRIVATE_KEY_DEPLOY`, set to a private key used for testing.
2. Install packages via `npm install` or `yarn install`.
3. Follow the instructions of the [tenderly hardhat package](https://github.com/Tenderly/hardhat-tenderly/tree/master/packages/tenderly-hardhat) to install the tenderly cli and login.

## Deployment

1. Deploy the Protocol contracts:

`npx hardhat run script/hardhat/DeployCore.ts --network tenderly`

The contracts that were deployed will be saved in `script/constants/output/ProtocolOutput.json`. 

2. Deploy pools and create gauges for them.

`npx hardhat run script/hardhat/DeployGaugesAndPools.ts --network tenderly`

3. Deploy Governors. You will need to set the governors manually in tenderly. 

`npx hardhat run script/hardhat/DeployGovernors.ts --network tenderly`
