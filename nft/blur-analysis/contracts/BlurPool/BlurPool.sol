// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IBlurPool.sol";

/**
 * @title BlurPool
 * @dev ETH pool; funds can only be transferred by Exchange or Swap
 */
contract BlurPool is IBlurPool, OwnableUpgradeable, UUPSUpgradeable {
    address private constant EXCHANGE = 0x000000000000Ad05Ccc4F10045630fb830B95127;
    address private constant SWAP = 0x39da41747a83aeE658334415666f3EF92DD0D541;

    mapping(address => uint256) private _balances;

    string public constant name = 'Blur Pool';
    string constant symbol = '';

    // required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    constructor() {
      _disableInitializers();
    }

    /* Constructor (for ERC1967) */
    function initialize() external initializer {
        __Ownable_init();
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return address(this).balance;
    }

    function balanceOf(address user) external view returns (uint256) {
        return _balances[user];
    }

    /**
     * @dev receive deposit function
     */
    receive() external payable {
        deposit();
    }

    /**
     * @dev deposit ETH into pool
     */
    function deposit() public payable {
        _balances[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    /**
     * @dev withdraw ETH from pool
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external {
        require(_balances[msg.sender] >= amount, "Insufficient funds");
        _balances[msg.sender] -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        emit Transfer(msg.sender, address(0), amount);
    }

    /**
     * @dev transferFrom Transfer balances within pool; only callable by Swap and Exchange
     * @param from Pool fund sender
     * @param to Pool fund recipient
     * @param amount Amount to transfer
     */
    function transferFrom(address from, address to, uint256 amount)
        external
        returns (bool)
    {
        if (msg.sender != EXCHANGE && msg.sender != SWAP) {
            revert('Unauthorized transfer');
        }
        _transfer(from, to, amount);

        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(to != address(0), "Cannot transfer to 0 address");
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

}
