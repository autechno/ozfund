// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IBEP20 {

    function decimals() external view returns (uint8);
    function allowance(address owner, address spender) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

}