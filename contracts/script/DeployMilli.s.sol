// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentVault} from "../src/milli/AgentVault.sol";
import {AeroAdapter} from "../src/milli/AeroAdapter.sol";
import {FeeSink} from "../src/milli/FeeSink.sol";

/// ---------------------------------------------------------------------
///  MILLI deployment — Base mainnet
///
///  DO NOT RUN before the audit + legal steps in AGENT_VAULT_SPEC.md.
///
///  Env:
///    SAFE=0x539DE6F65dECEB2F491237e3DC030494E517877C   # guardian/owner/treasury
///    EXECUTOR=0x...                                    # agent hot key (holds dust only)
///    KEEPER=0x...                                      # fee-sink ops key (can be EXECUTOR)
///
///  Run:
///    forge script script/DeployMilli.s.sol --rpc-url $BASE_RPC \
///      --account deployer --broadcast --verify --slow
///
///  AFTER deploy, from the Safe (app.safe.global):
///    1. lattice.setFeeNotifier(feeSink)          — lets the sink push WETH epochs
///    2. burnEngine.setRoute(WETH, aeroAdapter)   — lets the engine buy+burn THSND with WETH
///    3. burnEngine.setKeeper(KEEPER, true)
///    4. vault.setAsset(WETH, CHAINLINK_ETH_USD, true)
///    5. vault.setAdapter(aeroAdapter, true)
///    6. (launch caps) vault.setCaps stay at defaults: 10% trade / 50% day / 1% slip / 20% buffer
/// ---------------------------------------------------------------------
contract DeployMilli is Script {
    // ---- Base mainnet constants — VERIFY EACH ON BASESCAN BEFORE BROADCAST ----
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant CHAINLINK_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant LATTICE_LOCK = 0x1141F662b0647C2776Bb6A59B0ECA3Db481e6847;
    address constant BURN_ENGINE = 0x81929143c44a8141A1d2C40dB3774F1B262674D2;
    // Aerodrome (verify against aerodrome.finance docs at deploy time):
    address constant AERO_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERO_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    function run() external {
        address safe = vm.envAddress("SAFE");
        address executor = vm.envAddress("EXECUTOR");
        address keeper = vm.envAddress("KEEPER");

        vm.startBroadcast();

        AeroAdapter adapter = new AeroAdapter(AERO_ROUTER, AERO_FACTORY);
        FeeSink sink = new FeeSink(USDC, WETH, LATTICE_LOCK, BURN_ENGINE, safe);
        AgentVault vault = new AgentVault(USDC, safe, executor, address(sink));

        sink.setVault(address(vault));
        sink.setKeeper(keeper, true);

        // hand every key to the Safe — deployer retains nothing
        adapter.transferOwnership(safe);
        sink.transferOwnership(safe);
        // vault guardian is the Safe from the constructor

        vm.stopBroadcast();

        console.log("AeroAdapter :", address(adapter));
        console.log("FeeSink     :", address(sink));
        console.log("AgentVault  :", address(vault));
        console.log("NEXT: run the 6 Safe wiring steps in the header comment.");
    }
}
