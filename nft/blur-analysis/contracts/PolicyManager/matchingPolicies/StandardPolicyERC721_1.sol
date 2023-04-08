// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Order, AssetType} from "../lib/OrderStructs.sol";
import {IMatchingPolicy} from "../interfaces/IMatchingPolicy.sol";

/**
 * @title StandardPolicyERC721
 * @dev Policy for matching orders at a fixed price for a specific ERC721 tokenId (requires oracle authorization on both orders)
 */
contract StandardPolicyERC721 is IMatchingPolicy {
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
            (makerAsk.extraParams.length > 0 && makerAsk.extraParams[0] == "\x01") &&
            (takerBid.extraParams.length > 0 && takerBid.extraParams[0] == "\x01") &&
            (makerAsk.amount == 1) &&
            (takerBid.amount == 1) &&
            (makerAsk.matchingPolicy == takerBid.matchingPolicy) &&
            (makerAsk.price == takerBid.price),
            makerAsk.price,
            makerAsk.tokenId,
            1,
            AssetType.ERC721
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
            (makerBid.extraParams.length > 0 && makerBid.extraParams[0] == "\x01") &&
            (takerAsk.extraParams.length > 0 && takerAsk.extraParams[0] == "\x01") &&
            (makerBid.amount == 1) &&
            (takerAsk.amount == 1) &&
            (makerBid.matchingPolicy == takerAsk.matchingPolicy) &&
            (makerBid.price == takerAsk.price),
            makerBid.price,
            makerBid.tokenId,
            1,
            AssetType.ERC721
        );
    }
}

