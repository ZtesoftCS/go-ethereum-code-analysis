// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Order, AssetType} from "../lib/OrderStructs.sol";
import {IMatchingPolicy} from "../interfaces/IMatchingPolicy.sol";

/**
 * @title StandardPolicyERC1155
 * @dev Policy for matching orders at a fixed price for a specific ERC1155 tokenId
 */
contract StandardPolicyERC1155 is IMatchingPolicy {
    function canMatchMakerAsk(Order calldata makerAsk, Order calldata takerBid)
        external
        pure
        override
        returns (
            bool,
            uint256,
            uint256,
            uint256,
            AssetType
        )
    {
        return (
            (makerAsk.side != takerBid.side) &&
            (makerAsk.paymentToken == takerBid.paymentToken) &&
            (makerAsk.collection == takerBid.collection) &&
            (makerAsk.tokenId == takerBid.tokenId) &&
            (makerAsk.matchingPolicy == takerBid.matchingPolicy) &&
            (makerAsk.price == takerBid.price),
            makerAsk.price,
            makerAsk.tokenId,
            1,
            AssetType.ERC1155
        );
    }

    function canMatchMakerBid(Order calldata makerBid, Order calldata takerAsk)
        external
        pure
        override
        returns (
            bool,
            uint256,
            uint256,
            uint256,
            AssetType
        )
    {
        return (
            (makerBid.side != takerAsk.side) &&
            (makerBid.paymentToken == takerAsk.paymentToken) &&
            (makerBid.collection == takerAsk.collection) &&
            (makerBid.tokenId == takerAsk.tokenId) &&
            (makerBid.matchingPolicy == takerAsk.matchingPolicy) &&
            (makerBid.price == takerAsk.price),
            makerBid.price,
            makerBid.tokenId,
            1,
            AssetType.ERC1155
        );
    }
}

