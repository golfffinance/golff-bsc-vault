// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGOFPool {
    function stakeBehalf(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    
}