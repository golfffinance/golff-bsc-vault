// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IAutoPool {
    function deposit(uint256 _pid, uint256 _wantAmt) external;
    function withdraw(uint256 _pid, uint256 _wantAmt) external;
    function withdrawAll(uint256 _pid) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
}