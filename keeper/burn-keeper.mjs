#!/usr/bin/env node
/**
 * [ M U Y ] burn keeper
 *
 * Watches the BurnEngine for incoming collateral (liquidation slices from
 * Strata), computes a slippage floor, and calls execute() to market-buy
 * and burn MUY.
 *
 * Setup:
 *   npm init -y && npm install viem
 *   export KEEPER_PK=0x...            # dedicated keeper wallet, small ETH balance only
 *   export BASE_RPC=https://...
 *   export BURN_ENGINE=0x...
 *   export ASSETS=0xabc...,0xdef...   # collateral tokens to watch
 *   node burn-keeper.mjs
 *
 * Slippage: this template asks the route's router for a quote and applies
 * MAX_SLIPPAGE_BPS. In production, replace quote() with a TWAP oracle read
 * so a sandwiched pool can't feed the keeper a bad floor.
 */
import { createPublicClient, createWalletClient, http, parseAbi, formatUnits } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { base } from "viem/chains";

const MAX_SLIPPAGE_BPS = 100n; // 1%
const POLL_MS = 30_000;
const MIN_VALUE_WEI = 0n; // optionally skip dust

const engineAbi = parseAbi([
  "function execute(address asset, uint256 minMuyOut) returns (uint256)",
  "function routeOf(address) view returns (address)",
  "function totalMuyBurned() view returns (uint256)",
]);
const erc20Abi = parseAbi(["function balanceOf(address) view returns (uint256)"]);
// Adapt to your router's quoter. For the template ISwapRouter, expose a view quote:
const routerAbi = parseAbi([
  "function quoteExactInput(address tokenIn, address tokenOut, uint256 amountIn) view returns (uint256)",
]);

const { KEEPER_PK, BASE_RPC, BURN_ENGINE, MUY, ASSETS } = process.env;
if (!KEEPER_PK || !BASE_RPC || !BURN_ENGINE || !MUY || !ASSETS) {
  console.error("SYS: missing env. need KEEPER_PK, BASE_RPC, BURN_ENGINE, MUY, ASSETS");
  process.exit(1);
}

const account = privateKeyToAccount(KEEPER_PK);
const pub = createPublicClient({ chain: base, transport: http(BASE_RPC) });
const wallet = createWalletClient({ account, chain: base, transport: http(BASE_RPC) });
const assets = ASSETS.split(",").map((a) => a.trim());

console.log(`SYS: burn keeper online. engine=${BURN_ENGINE} keeper=${account.address}`);

async function tick() {
  for (const asset of assets) {
    try {
      const bal = await pub.readContract({ address: asset, abi: erc20Abi, functionName: "balanceOf", args: [BURN_ENGINE] });
      if (bal <= MIN_VALUE_WEI) continue;

      const router = await pub.readContract({ address: BURN_ENGINE, abi: engineAbi, functionName: "routeOf", args: [asset] });
      if (router === "0x0000000000000000000000000000000000000000") {
        console.warn(`SYS: ${asset} has balance but no route. set one via multisig.`);
        continue;
      }

      const quoted = await pub.readContract({ address: router, abi: routerAbi, functionName: "quoteExactInput", args: [asset, MUY, bal] });
      const minOut = (quoted * (10_000n - MAX_SLIPPAGE_BPS)) / 10_000n;
      if (minOut === 0n) continue;

      const hash = await wallet.writeContract({ address: BURN_ENGINE, abi: engineAbi, functionName: "execute", args: [asset, minOut] });
      const rc = await pub.waitForTransactionReceipt({ hash });
      const total = await pub.readContract({ address: BURN_ENGINE, abi: engineAbi, functionName: "totalMuyBurned" });
      console.log(`SYS: burned. tx=${hash} status=${rc.status} cumulative=${formatUnits(total, 18)} MUY`);
    } catch (e) {
      console.error(`SYS: ${asset} tick failed:`, e.shortMessage ?? e.message);
    }
  }
}

await tick();
setInterval(tick, POLL_MS);
