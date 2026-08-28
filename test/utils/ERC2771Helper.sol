// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";

// from https://github.com/corpus-io/tokenize.it-smart-contracts/blob/main/test/resources/ERC2771Helper.sol

contract ERC2771Helper is Test {
    using ECDSA for bytes32; // for verify with var.recover()

    /**
        @notice register domain separator and return the domain separator
        @dev can only be used when testing with forge, as it uses cheatcodes. For some reason, the forwarder contracts do not return the domain separator, which is fixed here.
    */
    function registerDomain(
        Forwarder forwarder,
        string calldata domainName,
        string calldata version
    ) public returns (bytes32) {
        // https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator
        // use chainId, address, name for proper implementation.
        // opengsn suggests different contents: https://docs.opengsn.org/soldoc/contracts/forwarder/iforwarder.html#registerdomainseparator-string-name-string-version
        vm.recordLogs();
        forwarder.registerDomainSeparator(domainName, version); // simply uses address string as name

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // the next line extracts the domain separator from the event emitted by the forwarder
        bytes32 domainSeparator = logs[0].topics[1]; // internally, the forwarder calls this domainHash in registerDomainSeparator. But expects is as domainSeparator in execute().
        require(forwarder.domains(domainSeparator), "Registering failed");
        return domainSeparator;
    }

    /** 
        @notice register request type, e.g. which function to call and which parameters to expect
        @dev return the request type
    */
    function registerRequestType(
        Forwarder forwarder,
        string calldata functionName,
        string calldata functionParameters
    ) public returns (bytes32) {
        vm.recordLogs();
        forwarder.registerRequestType(functionName, functionParameters);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // the next line extracts the request type from the event emitted by the forwarder
        bytes32 requestType = logs[0].topics[1];
        require(forwarder.typeHashes(requestType), "Registering failed");
        return requestType;
    }
}
