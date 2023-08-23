// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

/// @notice Script to distribute all the provided Airdrops
contract DistributeAirdrops is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public airdropFilename = vm.envString("AIRDROPS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");
    uint256 public WALLET_BATCH_SIZE = 50;
    string public jsonConstants;
    string public basePath;
    string public path;

    AirdropDistributor public airdrop;
    Aero public AERO;

    struct AirdropInfo {
        uint256 amount;
        address wallet;
    }

    constructor() {
        string memory root = vm.projectRoot();
        basePath = string.concat(root, "/script/constants/");
        path = string.concat(basePath, "output/DeployCore-");
        path = string.concat(path, outputFilename);
        jsonConstants = vm.readFile(path);

        AERO = Aero(abi.decode(jsonConstants.parseRaw(".AERO"), (address)));
        airdrop = AirdropDistributor(abi.decode(jsonConstants.parseRaw(".AirdropDistributor"), (address)));

        path = string.concat(basePath, airdropFilename);
        jsonConstants = vm.readFile(path);
    }

    function run() public {
        AirdropInfo[] memory infos = abi.decode(jsonConstants.parseRaw(".airdrop"), (AirdropInfo[]));

        (address[] memory wallets, uint256[] memory amounts) = getArraysFromInfo(infos);
        uint256 walletsLength = wallets.length;
        require(walletsLength == amounts.length, "Invalid parameters");
        uint256 sum;
        for (uint256 i = 0; i < walletsLength; i++) {
            sum += amounts[i];
        }
        require(AERO.balanceOf(address(airdrop)) >= sum, "Not enough balance to proceed with airdrops");

        path = string.concat(basePath, "output/AirdropDistribution-");
        path = string.concat(path, outputFilename);

        uint256 lastBatchSize = walletsLength % WALLET_BATCH_SIZE;
        uint256 nBatches = walletsLength / WALLET_BATCH_SIZE;

        uint256 batchLen;
        address[] memory batchWallets;
        uint256[] memory batchAmounts;
        vm.startBroadcast(deployerAddress);
        for (uint256 i = 0; i <= nBatches; i++) {
            if (i != nBatches) {
                // Not last batch
                batchWallets = new address[](WALLET_BATCH_SIZE);
                batchAmounts = new uint256[](WALLET_BATCH_SIZE);
                batchLen = WALLET_BATCH_SIZE;
            } else {
                if (lastBatchSize == 0) continue;
                batchWallets = new address[](lastBatchSize);
                batchAmounts = new uint256[](lastBatchSize);
                batchLen = lastBatchSize;
            }

            // Fetches the wallets from current batch
            uint256 firstIndex = i * WALLET_BATCH_SIZE;
            for (uint256 j = 0; j < batchLen; j++) {
                batchWallets[j] = wallets[j + firstIndex];
                batchAmounts[j] = amounts[j + firstIndex];
            }

            // Distribute batch
            airdrop.distributeTokens(batchWallets, batchAmounts);
            // Write batch to file
            for (uint256 j = 0; j < batchLen; j++) {
                vm.writeJson(vm.serializeUint("airdrop", vm.toString(batchWallets[j]), batchAmounts[j]), path);
            }
        }
        airdrop.renounceOwnership();
        vm.stopBroadcast();
    }

    function getArraysFromInfo(
        AirdropInfo[] memory infos
    ) public pure returns (address[] memory _wallets, uint256[] memory _amounts) {
        uint256 len = infos.length;
        _wallets = new address[](len);
        _amounts = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            AirdropInfo memory drop = infos[i];
            _wallets[i] = drop.wallet;
            _amounts[i] = drop.amount;
        }
    }
}
