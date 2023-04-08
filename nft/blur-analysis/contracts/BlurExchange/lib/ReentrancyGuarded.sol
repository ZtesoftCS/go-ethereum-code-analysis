// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title ReentrancyGuarded
 * @dev Protections for reentrancy attacks
 */
contract ReentrancyGuarded {

    bool private reentrancyLock = false;

    /* Prevent a contract function from being reentrant-called. */
    modifier reentrancyGuard {
        require(!reentrancyLock, "Reentrancy detected");
        reentrancyLock = true;
        _;
        reentrancyLock = false;
    }

    uint256[49] private __gap;
}
