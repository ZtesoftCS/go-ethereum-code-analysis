// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/**
 * @title ReentrancyGuarded
 * @dev Protections for reentrancy attacks
 */
contract ReentrancyGuarded {

    bool reentrancyLock = false;

    /* Prevent a contract function from being reentrant-called. */
    modifier reentrancyGuard {
        require(!reentrancyLock, "Reentrancy detected");
        reentrancyLock = true;
        _;
        reentrancyLock = false;
    }

}
