// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IUnitroller {
    function claimVenus(address holder, address[] calldata cTokens) external;
}