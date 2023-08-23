// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/StdJson.sol";
import "../test/Base.sol";

contract DeployCore is Base {
    using stdJson for string;
    string public basePath;
    string public path;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public outputFilename = vm.envString("OUTPUT_FILENAME");
    string public jsonConstants;
    string public jsonOutput;

    uint256 public constant AIRDROPPER_BALANCE = 200_000_000 * 1e18;

    // Vars to be set in each deploy script
    address feeManager;
    address team;
    address emergencyCouncil;

    struct AirdropInfo {
        uint256 amount;
        address wallet;
    }

    constructor() {
        string memory root = vm.projectRoot();
        basePath = string.concat(root, "/script/constants/");

        // load constants
        path = string.concat(basePath, constantsFilename);
        jsonConstants = vm.readFile(path);
        WETH = IWETH(abi.decode(vm.parseJson(jsonConstants, ".WETH"), (address)));
        allowedManager = abi.decode(vm.parseJson(jsonConstants, ".allowedManager"), (address));
        team = abi.decode(vm.parseJson(jsonConstants, ".team"), (address));
        feeManager = abi.decode(vm.parseJson(jsonConstants, ".feeManager"), (address));
        emergencyCouncil = abi.decode(vm.parseJson(jsonConstants, ".emergencyCouncil"), (address));
    }

    function run() public {
        _deploySetupBefore();
        _coreSetup();
        _deploySetupAfter();
    }

    function _deploySetupBefore() public {
        // more constants loading - this needs to be done in-memory and not storage
        address[] memory _tokens = abi.decode(vm.parseJson(jsonConstants, ".whitelistTokens"), (address[]));
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokens.push(_tokens[i]);
        }

        // Loading output and use output path to later save deployed contracts
        path = string.concat(basePath, "output/DeployCore-");
        path = string.concat(path, outputFilename);

        // start broadcasting transactions
        vm.startBroadcast(deployerAddress);

        // deploy AERO
        AERO = new Aero();

        tokens.push(address(AERO));
    }

    function _deploySetupAfter() public {
        // Initializes the Minter
        _initializeMinter();

        // Set protocol state to team
        escrow.setTeam(team);
        minter.setTeam(team);
        factory.setPauser(team);
        voter.setEmergencyCouncil(emergencyCouncil);
        voter.setEpochGovernor(team);
        voter.setGovernor(team);
        factoryRegistry.transferOwnership(team);

        // Set contract vars
        factory.setFeeManager(feeManager);
        factory.setVoter(address(voter));

        // finish broadcasting transactions
        vm.stopBroadcast();

        // write to file
        vm.writeJson(vm.serializeAddress("v2", "AERO", address(AERO)), path);
        vm.writeJson(vm.serializeAddress("v2", "VotingEscrow", address(escrow)), path);
        vm.writeJson(vm.serializeAddress("v2", "Forwarder", address(forwarder)), path);
        vm.writeJson(vm.serializeAddress("v2", "ArtProxy", address(artProxy)), path);
        vm.writeJson(vm.serializeAddress("v2", "Distributor", address(distributor)), path);
        vm.writeJson(vm.serializeAddress("v2", "Voter", address(voter)), path);
        vm.writeJson(vm.serializeAddress("v2", "Router", address(router)), path);
        vm.writeJson(vm.serializeAddress("v2", "Minter", address(minter)), path);
        vm.writeJson(vm.serializeAddress("v2", "PoolFactory", address(factory)), path);
        vm.writeJson(vm.serializeAddress("v2", "VotingRewardsFactory", address(votingRewardsFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "GaugeFactory", address(gaugeFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "ManagedRewardsFactory", address(managedRewardsFactory)), path);
        vm.writeJson(vm.serializeAddress("v2", "FactoryRegistry", address(factoryRegistry)), path);
        vm.writeJson(vm.serializeAddress("v2", "AirdropDistributor", address(airdrop)), path);
    }

    function _initializeMinter() public {
        // Fetching Liquid Token Airdrop info, including the address of the recently deployed AirdropDistributor
        AirdropInfo[] memory infos = abi.decode(jsonConstants.parseRaw(".minter.liquid"), (AirdropInfo[]));
        (address[] memory liquidWallets, uint256[] memory liquidAmounts) = _getLiquidAirdropInfo(
            address(airdrop),
            AIRDROPPER_BALANCE,
            infos
        );

        // Fetching Locked NFTs Airdrop info
        infos = abi.decode(jsonConstants.parseRaw(".minter.locked"), (AirdropInfo[]));
        (address[] memory lockedWallets, uint256[] memory lockedAmounts) = _getLockedAirdropInfo(infos);
        // Airdrops All Tokens
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: liquidWallets,
                liquidAmounts: liquidAmounts,
                lockedWallets: lockedWallets,
                lockedAmounts: lockedAmounts
            })
        );
    }

    function _getLiquidAirdropInfo(
        address airdropDistributor,
        uint256 distributorAmount,
        AirdropInfo[] memory infos
    ) public pure returns (address[] memory wallets, uint256[] memory amounts) {
        uint256 len = infos.length + 1;
        wallets = new address[](len);
        amounts = new uint256[](len);
        wallets[0] = airdropDistributor;
        amounts[0] = distributorAmount;

        for (uint256 i = 1; i < len; i++) {
            AirdropInfo memory drop = infos[i - 1];
            wallets[i] = drop.wallet;
            amounts[i] = drop.amount;
        }
    }

    function _getLockedAirdropInfo(
        AirdropInfo[] memory infos
    ) public pure returns (address[] memory wallets, uint256[] memory amounts) {
        uint256 len = infos.length;
        wallets = new address[](len);
        amounts = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            AirdropInfo memory drop = infos[i];
            wallets[i] = drop.wallet;
            amounts[i] = drop.amount;
        }
    }
}
