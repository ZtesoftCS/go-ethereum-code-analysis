pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20("test", "TST") {

    function mint(address to, uint256 value) external returns (bool) {
        _mint(to, value);
        return true;
    }
}
