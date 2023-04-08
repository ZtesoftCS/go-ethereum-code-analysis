// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IPolicyManager} from "./interfaces/IPolicyManager.sol";

/**
 * @title PolicyManager
 * @dev Manages the policy whitelist for the Blur exchange
 */
contract PolicyManager is IPolicyManager, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _whitelistedPolicies;

    event PolicyRemoved(address indexed policy);
    event PolicyWhitelisted(address indexed policy);

    /**
     * @notice Add matching policy
     * @param policy address of policy to add
     */
    function addPolicy(address policy) external override onlyOwner {
        require(!_whitelistedPolicies.contains(policy), "Already whitelisted");
        _whitelistedPolicies.add(policy);

        emit PolicyWhitelisted(policy);
    }

    /**
     * @notice Remove matching policy
     * @param policy address of policy to remove
     */
    function removePolicy(address policy) external override onlyOwner {
        require(_whitelistedPolicies.contains(policy), "Not whitelisted");
        _whitelistedPolicies.remove(policy);

        emit PolicyRemoved(policy);
    }

    /**
     * @notice Returns if a policy has been added
     * @param policy address of the policy to check
     */
    function isPolicyWhitelisted(address policy) external view override returns (bool) {
        return _whitelistedPolicies.contains(policy);
    }

    /**
     * @notice View number of whitelisted policies
     */
    function viewCountWhitelistedPolicies() external view override returns (uint256) {
        return _whitelistedPolicies.length();
    }

    /**
     * @notice See whitelisted policies
     * @param cursor cursor
     * @param size size
     */
    function viewWhitelistedPolicies(uint256 cursor, uint256 size)
        external
        view
        override
        returns (address[] memory, uint256)
    {
        uint256 length = size;

        if (length > _whitelistedPolicies.length() - cursor) {
            length = _whitelistedPolicies.length() - cursor;
        }

        address[] memory whitelistedPolicies = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            whitelistedPolicies[i] = _whitelistedPolicies.at(cursor + i);
        }

        return (whitelistedPolicies, cursor + length);
    }
}
