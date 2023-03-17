pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MockERC1155 is ERC1155("") {

    function mint(address to, uint256 tokenId, uint256 amount)
        external
        returns (bool)
    {
        _mint(to, tokenId, amount, "");
        return true;
    }
}
