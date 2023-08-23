// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";
import "./utils/ERC2771Helper.sol";

contract ForwarderTest is BaseTest {
    using ECDSA for bytes32;

    // first public/private key provided by anvil
    address sender = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 senderPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    ERC2771Helper erc2771Helper;

    function _setUp() public override {
        erc2771Helper = new ERC2771Helper();

        // fund forwarder with ETH for txs and fund from with AERO
        vm.deal(address(forwarder), 1e18);
        deal(address(AERO), sender, TOKEN_100K, true);

        // Approve owner and sender transfers of AERO
        AERO.approve(address(escrow), type(uint256).max);
        vm.prank(sender);
        AERO.approve(address(escrow), type(uint256).max);
    }

    function testForwarderCreateLock() public {
        bytes memory payload = abi.encodeWithSelector(escrow.createLock.selector, TOKEN_1, MAXTIME);
        bytes32 requestType = erc2771Helper.registerRequestType(
            forwarder,
            "createLock",
            "uint256 _value,uint256 _lockDuration"
        );

        handleRequest(address(escrow), payload, requestType);
        assertEq(escrow.ownerOf(1), sender);
    }

    function testForwarderVote() public {
        skip(1 hours + 1);
        escrow.createLockFor(TOKEN_1, MAXTIME, sender);
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        // build request
        bytes memory payload = abi.encodeWithSelector(voter.vote.selector, 1, pools, weights);
        bytes32 requestType = erc2771Helper.registerRequestType(
            forwarder,
            "vote",
            "uint256 _tokenId,address[] _poolVote,uint256[] _weights"
        );

        handleRequest(address(voter), payload, requestType);
        assertTrue(escrow.voted(1));
    }

    function handleRequest(address _to, bytes memory payload, bytes32 requestType) internal {
        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: sender,
            to: _to,
            value: 0,
            gas: 5_000_000,
            nonce: forwarder.getNonce(sender),
            data: payload,
            validUntil: 0
        });

        // TODO: move this to Base.sol once working
        bytes32 domainSeparator = erc2771Helper.registerDomain(
            forwarder,
            Strings.toHexString(uint256(uint160(_to)), 20),
            "1"
        );

        bytes memory suffixData = "0";
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(forwarder._getEncoded(request, requestType, suffixData))
            )
        );

        // sign request
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        require(digest.recover(signature) == request.from, "FWD: signature mismatch");

        forwarder.execute(request, domainSeparator, requestType, suffixData, signature);
    }
}
