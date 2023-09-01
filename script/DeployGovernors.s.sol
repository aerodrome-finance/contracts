// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

contract DeployGovernors is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployAddress = vm.rememberKey(deployPrivateKey);
    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");
    string public jsonConstants;
    string public jsonOutput;

    address team;

    VotingEscrow public escrow;
    Forwarder public forwarder;
    Minter public minter;
    ProtocolGovernor public governor;
    EpochGovernor public epochGovernor;

    constructor() {}

    function run() public {
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, "/script/constants/");

        string memory path = string.concat(basePath, constantsFilename);
        jsonConstants = vm.readFile(path);
        team = abi.decode(vm.parseJson(jsonConstants, ".team"), (address));

        path = string.concat(basePath, "output/DeployCore-");
        path = string.concat(path, outputFilename);
        jsonOutput = vm.readFile(path);
        escrow = VotingEscrow(abi.decode(vm.parseJson(jsonOutput, ".VotingEscrow"), (address)));
        forwarder = Forwarder(abi.decode(vm.parseJson(jsonOutput, ".Forwarder"), (address)));
        minter = Minter(abi.decode(vm.parseJson(jsonOutput, ".Minter"), (address)));

        vm.startBroadcast(deployAddress);

        governor = new ProtocolGovernor(escrow);
        epochGovernor = new EpochGovernor(address(forwarder), escrow, address(minter));

        governor.setVetoer(escrow.team());

        vm.stopBroadcast();

        // write to file
        path = string.concat(basePath, "output/DeployGovernors-");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("v2", "Governor", address(governor)), path);
        vm.writeJson(vm.serializeAddress("v2", "EpochGovernor", address(epochGovernor)), path);
    }
}
