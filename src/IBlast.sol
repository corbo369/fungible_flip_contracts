// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBlast {
    function configureAutomaticYield() external;
    function configureClaimableGas() external;
    function claimMaxGas(address contractAddress, address recipientOfGas) external returns (uint256);
}

