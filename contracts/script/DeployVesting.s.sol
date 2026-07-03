// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MuyVesting} from "../src/MuyVesting.sol";

/// Deploy one vesting contract per team member / investor.
///
/// Required env:
///   MUY_TOKEN    - deployed MUY address
///   BENEFICIARY  - who receives the vested tokens
///   START        - unix timestamp vesting starts (usually launch time)
///   CLIFF_DAYS   - e.g. 365
///   DURATION_DAYS- e.g. 1095 (36 months)
///
/// After deploy: transfer the allocation of MUY to the printed address.
/// There is no admin and no clawback — check every value twice.
contract DeployVesting is Script {
    function run() external {
        address token = vm.envAddress("MUY_TOKEN");
        address beneficiary = vm.envAddress("BENEFICIARY");
        uint64 start = uint64(vm.envUint("START"));
        uint64 cliff = uint64(vm.envUint("CLIFF_DAYS")) * 1 days;
        uint64 duration = uint64(vm.envUint("DURATION_DAYS")) * 1 days;

        vm.startBroadcast();
        MuyVesting vesting = new MuyVesting(token, beneficiary, start, cliff, duration);
        vm.stopBroadcast();

        console.log("MuyVesting deployed:", address(vesting));
        console.log("  beneficiary:", beneficiary);
        console.log("  NOW SEND THE ALLOCATION OF MUY TO THIS ADDRESS.");
    }
}
