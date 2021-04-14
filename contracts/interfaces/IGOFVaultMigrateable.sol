// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGOFVaultMigrateable {
    function depositBehalf(address account, uint _amount) external;
    function setMigrateDist(IGOFVaultMigrateable vault) external ;
    function migrate() external;
}