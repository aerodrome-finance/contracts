// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // keccak256("Delegation(uint256 delegator,uint256 delegatee,uint256 nonce,uint256 expiry)");
    bytes32 public constant DELEGATION_TYPEHASH = 0x9947d5709c1682eaa3946b2d84115c9c0d1c946b149d76e69b457458b42ea29e;

    struct Delegation {
        uint256 delegator;
        uint256 delegatee;
        uint256 nonce;
        uint256 deadline;
    }

    /// @dev Computes the hash of a permit
    function getStructHash(Delegation memory _delegation) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DELEGATION_TYPEHASH,
                    _delegation.delegator,
                    _delegation.delegatee,
                    _delegation.nonce,
                    _delegation.deadline
                )
            );
    }

    /// @dev Computes the hash of the fully encoded EIP-712 message for the domain,
    ///      which can be used to recover the signer
    function getTypedDataHash(Delegation memory _delegation) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getStructHash(_delegation)));
    }
}
