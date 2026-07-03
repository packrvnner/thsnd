// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {THSND} from "../src/THSND.sol";
import {LatticeLock} from "../src/LatticeLock.sol";
import {BurnEngine} from "../src/BurnEngine.sol";
import {TierRegistry} from "../src/TierRegistry.sol";

/// Deploy order: MUY -> LatticeLock -> BurnEngine -> TierRegistry
///
/// Required env:
///   TREASURY      - multisig receiving genesis supply
///   REWARD_TOKEN  - fee-share asset (WETH on Base: 0x4200000000000000000000000000000000000006)
///
/// Usage (Base Sepolia dry run):
///   forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC --account deployer --broadcast --verify
contract Deploy is Script {
    function run() external {
        address treasury = vm.envAddress("TREASURY");
        address rewardToken = vm.envAddress("REWARD_TOKEN");

        vm.startBroadcast();

        THSND muy = new THSND(treasury);
        LatticeLock latticeLock = new LatticeLock(address(muy), rewardToken);
        BurnEngine burnEngine = new BurnEngine(address(muy));
        TierRegistry tierRegistry = new TierRegistry(address(muy), address(latticeLock));

        vm.stopBroadcast();

        console.log("[ 1000 ] THOUSAND deployment matrix:");
        console.log("  THSND:        ", address(muy));
        console.log("  LatticeLock:  ", address(latticeLock));
        console.log("  BurnEngine:   ", address(burnEngine));
        console.log("  TierRegistry: ", address(tierRegistry));
        console.log("  Treasury:     ", treasury);
    }
}
