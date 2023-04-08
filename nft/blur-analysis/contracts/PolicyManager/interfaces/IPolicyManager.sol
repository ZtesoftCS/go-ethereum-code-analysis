// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPolicyManager {
    function addPolicy(address policy) external;

    function removePolicy(address policy) external;

    function isPolicyWhitelisted(address policy) external view returns (bool);

    function viewWhitelistedPolicies(uint256 cursor, uint256 size) external view returns (address[] memory, uint256);

    function viewCountWhitelistedPolicies() external view returns (uint256);
}
