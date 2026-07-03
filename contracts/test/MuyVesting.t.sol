// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {THSND} from "../src/THSND.sol";
import {MuyVesting} from "../src/MuyVesting.sol";

contract MuyVestingTest is Test {
    THSND muy;
    MuyVesting vesting;
    address treasury = makeAddr("treasury");
    address teamMember = makeAddr("teamMember");

    uint64 start;
    uint64 constant CLIFF = 365 days;       // 12-month cliff
    uint64 constant DURATION = 3 * 365 days; // 36 months total (24 linear post-cliff)
    uint256 constant ALLOCATION = 10_000_000e18;

    function setUp() public {
        start = uint64(block.timestamp);
        muy = new THSND(treasury);
        vesting = new MuyVesting(address(muy), teamMember, start, CLIFF, DURATION);
        vm.prank(treasury);
        muy.transfer(address(vesting), ALLOCATION);
    }

    function test_nothingBeforeCliff() public {
        skip(CLIFF - 1);
        assertEq(vesting.releasable(), 0);
        vm.expectRevert("MV: nothing vested");
        vesting.release();
    }

    function test_cliffUnlocksProRata() public {
        skip(CLIFF);
        // at cliff, 12/36 of allocation is vested (linear from start)
        assertEq(vesting.releasable(), ALLOCATION / 3);
        vesting.release(); // anyone can call
        assertEq(muy.balanceOf(teamMember), ALLOCATION / 3);
    }

    function test_fullVestAtEnd() public {
        skip(DURATION + 1);
        vesting.release();
        assertEq(muy.balanceOf(teamMember), ALLOCATION);
        assertEq(vesting.releasable(), 0);
    }

    function test_onlyBeneficiaryReceives() public {
        skip(DURATION);
        vm.prank(makeAddr("attacker"));
        vesting.release(); // callable by anyone, but...
        assertEq(muy.balanceOf(teamMember), ALLOCATION); // ...funds go to beneficiary only
    }

    function testFuzz_monotonicVesting(uint64 t1, uint64 t2) public view {
        t1 = uint64(bound(t1, start, start + DURATION * 2));
        t2 = uint64(bound(t2, t1, start + DURATION * 2));
        assertLe(vesting.vestedAmount(t1), vesting.vestedAmount(t2));
    }
}
