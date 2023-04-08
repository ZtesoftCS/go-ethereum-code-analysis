// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ICryptoPunks {
    function punkIndexToAddress(uint index) external view returns(address owner);
    function offerPunkForSaleToAddress(uint punkIndex, uint minSalePriceInWei, address toAddress) external;
    function buyPunk(uint punkIndex) external payable;
    function transferPunk(address to, uint punkIndex) external;
}
