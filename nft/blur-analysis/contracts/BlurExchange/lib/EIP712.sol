// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Order, Fee} from "./OrderStructs.sol";

/**
 * @title EIP712
 * @dev Contains all of the order hashing functions for EIP712 compliant signatures
 */
contract EIP712 {

    struct EIP712Domain {
        string  name;
        string  version;
        uint256 chainId;
        address verifyingContract;
    }

    /* Order typehash for EIP 712 compatibility. */
    bytes32 constant public FEE_TYPEHASH = keccak256(
        "Fee(uint16 rate,address recipient)"
    );
    bytes32 constant public ORDER_TYPEHASH = keccak256(
        "Order(address trader,uint8 side,address matchingPolicy,address collection,uint256 tokenId,uint256 amount,address paymentToken,uint256 price,uint256 listingTime,uint256 expirationTime,Fee[] fees,uint256 salt,bytes extraParams,uint256 nonce)Fee(uint16 rate,address recipient)"
    );
    bytes32 constant public ORACLE_ORDER_TYPEHASH = keccak256(
        "OracleOrder(Order order,uint256 blockNumber)Fee(uint16 rate,address recipient)Order(address trader,uint8 side,address matchingPolicy,address collection,uint256 tokenId,uint256 amount,address paymentToken,uint256 price,uint256 listingTime,uint256 expirationTime,Fee[] fees,uint256 salt,bytes extraParams,uint256 nonce)"
    );
    bytes32 constant public ROOT_TYPEHASH = keccak256(
        "Root(bytes32 root)"
    );

    bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 DOMAIN_SEPARATOR;

    function _hashDomain(EIP712Domain memory eip712Domain)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(bytes(eip712Domain.name)),
                keccak256(bytes(eip712Domain.version)),
                eip712Domain.chainId,
                eip712Domain.verifyingContract
            )
        );
    }

    function _hashFee(Fee calldata fee)
        internal 
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                FEE_TYPEHASH,
                fee.rate,
                fee.recipient
            )
        );
    }

    function _packFees(Fee[] calldata fees)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory feeHashes = new bytes32[](
            fees.length
        );
        for (uint256 i = 0; i < fees.length; i++) {
            feeHashes[i] = _hashFee(fees[i]);
        }
        return keccak256(abi.encodePacked(feeHashes));
    }


    function _hashOrder(Order calldata order, uint256 nonce)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            bytes.concat(
                abi.encode(
                      ORDER_TYPEHASH,
                      order.trader,
                      order.side,
                      order.matchingPolicy,
                      order.collection,
                      order.tokenId,
                      order.amount,
                      order.paymentToken,
                      order.price,
                      order.listingTime,
                      order.expirationTime,
                      _packFees(order.fees),
                      order.salt,
                      keccak256(order.extraParams)
                ),
                abi.encode(nonce)
            )
        );
    }

    function _hashToSign(bytes32 orderHash)
        internal
        view
        returns (bytes32 hash)
    {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            orderHash
        ));
    }

    function _hashToSignRoot(bytes32 root)
        internal
        view
        returns (bytes32 hash)
    {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                ROOT_TYPEHASH,
                root
            ))
        ));
    }

    function _hashToSignOracle(bytes32 orderHash, uint256 blockNumber)
        internal
        view
        returns (bytes32 hash)
    {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                ORACLE_ORDER_TYPEHASH,
                orderHash,
                blockNumber
            ))
        ));
    }

    uint256[44] private __gap;
}
