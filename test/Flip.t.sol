// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Utilities } from "./utils/Utilities.sol";
import { FungibleFlip } from "../src/FungibleFlipTest.sol";

contract FlipTest is Test {

    FungibleFlip internal fungibleFlip;
    Utilities internal utils;

    address payable internal owner;
    address payable internal userOne;
    address payable internal userTwo;

    // ADJUST THESE PARAMS
    bool choice = true;
    uint256 flipAmount = 0.01 ether;

    modifier prank(address from) {
        vm.startPrank(from);
        _;
        vm.stopPrank();
    }

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(3);

        owner = users[0];
        userOne = users[1];
        userTwo = users[2];
        vm.label(owner, "Owner");
        vm.label(userOne, "User One");
        vm.label(userTwo, "User Two");

        vm.startPrank(owner);

        fungibleFlip = new FungibleFlip(
            0x4300000000000000000000000000000000000002,
            owner,
            0.2 ether,
            0.0003 ether,
            [
                (uint256)(0.0025 ether),
                (uint256)(0.005 ether),
                (uint256)(0.01 ether),
                (uint256)(0.025 ether),
                (uint256)(0.05 ether),
                (uint256)(0.1 ether)
           ]
        );

        (bool success, ) = address(fungibleFlip).call{value: 0.5 ether}("");
        require(success);
        vm.stopPrank();
    }

    function testFlip() prank(owner) public {
        fungibleFlip.deposit{value: 0.01 ether}(true);
        fungibleFlip.flip(0, 0x138c3fd11d9988c9e4ec87537113fb2a38845697fed4c7457644bba34c9fee74);
    }

    /*
    function testFlip(bytes32 random) prank(userOne) public {
        uint256 balanceBefore = address(fungibleFlip).balance;

        fungibleFlip.deposit{value: flipAmount}(0x0, 0x0, choice);

        (
            uint64 _sequenceNumber,
            uint256 _flipAmount,
            bytes32 _randomNumber,
            address _requester,
            bool _choice
        ) = fungibleFlip.requests(0);

        fungibleFlip.flip(0x0, random);

        assertTrue(_sequenceNumber == 0);
        assertTrue(_flipAmount == flipAmount);
        assertTrue(_randomNumber == 0x0);
        assertTrue(_requester == userOne);
        assertTrue(_choice == choice);

        bool flipResult = uint256(random) % 2 == 0;
        uint256 balanceAfter = address(fungibleFlip).balance;

        if (flipResult == choice) {
            assertTrue(balanceAfter == balanceBefore - flipAmount);
        } else {
            assertTrue(balanceAfter == balanceBefore + flipAmount);
        }
    }

    function testCounters(bytes32 random) prank(userOne) public {
        (
            ,
            uint32 numWinsBefore,
            uint32 numLossesBefore,
            uint32 numHeadsBefore,
            uint32 numTailsBefore,

        ) = fungibleFlip.stats(userOne);

        fungibleFlip.deposit{value: flipAmount}(0x0, 0x0, choice);
        fungibleFlip.flip(0x0, random);

        (
            ,
            uint32 numWinsAfter,
            uint32 numLossesAfter,
            uint32 numHeadsAfter,
            uint32 numTailsAfter,

        ) = fungibleFlip.stats(userOne);

        bool flipResult = uint256(random) % 2 == 0;

        if (choice) {
            assertTrue(numHeadsAfter == numHeadsBefore + 1);
            assertTrue(numTailsAfter == numTailsBefore);
        } else {
            assertTrue(numTailsAfter == numTailsBefore + 1);
            assertTrue(numHeadsAfter == numHeadsBefore);
        }

        if (choice == flipResult) {
            assertTrue(numWinsAfter == numWinsBefore + 1);
            assertTrue(numLossesAfter == numLossesBefore);
        } else {
            assertTrue(numLossesAfter == numLossesBefore + 1);
            assertTrue(numWinsAfter == numWinsBefore);
        }
    }

    function flipForStreak(bytes32 random) prank(userOne) internal {
        (, , , , ,uint8 streakBefore) = fungibleFlip.stats(userOne);
        fungibleFlip.deposit{value: flipAmount}(0x0, 0x0, choice);
        fungibleFlip.flip(0x0, random);
        (, , , , ,uint8 streakAfter) = fungibleFlip.stats(userOne);
    }

    function testStreak() public {
        bytes32 random = 0x138c3fd11d9988c9e4ec87537113fb2a38845697fed4c7457644bba34c9fee74;
        flipForStreak(random);
        flipForStreak(random);
        choice = false;
        flipForStreak(random);
        flipForStreak(random);
    }
    */
}
