// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {VeArtProxy} from "contracts/VeArtProxy.sol";

import "forge-std/StdJson.sol";
import "../test/Base.sol";

/// @notice Script to deploy the ArtProxy contract
contract DeployArtProxy is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public outputFilename = vm.envString("OUTPUT_FILENAME");
    string public jsonOutput;
    string public basePath;
    string public path;

    address public escrow;
    VeArtProxy public artProxy;

    constructor() {
        string memory root = vm.projectRoot();
        basePath = string.concat(root, "/script/constants/");
        path = string.concat(basePath, "output/DeployCore-");
        path = string.concat(path, outputFilename);
        jsonOutput = vm.readFile(path);

        // load in var
        escrow = abi.decode(jsonOutput.parseRaw(".VotingEscrow"), (address));
    }

    function run() public {
        console.log("Using Voting Escrow: %s", address(escrow));
        vm.broadcast(deployPrivateKey);
        artProxy = new VeArtProxy(escrow);
        console.log("Deploying ArtProxy to: %s", address(artProxy));

        path = string.concat(basePath, "output/DeployArtProxy-");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "ArtProxy", address(artProxy)), path);
    }
}
