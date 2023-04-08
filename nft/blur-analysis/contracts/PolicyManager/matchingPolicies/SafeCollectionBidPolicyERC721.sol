// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Order, AssetType} from "../lib/OrderStructs.sol";
import {IMatchingPolicy} from "../interfaces/IMatchingPolicy.sol";

/**
 * @title SafeCollectionBidPolicyERC721
 * @dev Policy for matching orders where buyer will purchase any NON-SUSPICIOUS token from a collection
 */
contract SafeCollectionBidPolicyERC721 is IMatchingPolicy {
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
        revert("Cannot be matched");
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
            (makerBid.extraParams.length > 0 && makerBid.extraParams[0] == "\x01") &&
            (takerAsk.extraParams.length > 0 && takerAsk.extraParams[0] == "\x01") &&
            (makerBid.amount == 1) &&
            (takerAsk.amount == 1) &&
            (makerBid.matchingPolicy == takerAsk.matchingPolicy) &&
            (makerBid.price == takerAsk.price),
            makerBid.price,
            takerAsk.tokenId,
            1,
            AssetType.ERC721
        );
    }
}
