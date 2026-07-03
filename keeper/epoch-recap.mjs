#!/usr/bin/env node
/**
 * THOUSAND — weekly epoch recap generator (read-only, no keys needed)
 *
 * Run AFTER pushing the weekly WETH fee epoch (see docs/EPOCH_RUNBOOK.md).
 * Reads the chain and prints a ready-to-post recap (X / Farcaster) plus JSON.
 *
 * Setup:
 *   npm install viem            # once, in this folder
 *   node epoch-recap.mjs        # defaults: last 7 days, public Base RPC
 *
 * Options (env):
 *   BASE_RPC=https://...        # custom RPC
 *   LOOKBACK_DAYS=7             # recap window
 */
import { createPublicClient, http, parseAbi, formatEther, formatUnits } from "viem";
import { base } from "viem/chains";

const ADDR = {
  token: "0xF7aa829ed31fE30834E56348e9CD3fBb4687CFdb",
  vault: "0x1141F662b0647C2776Bb6A59B0ECA3Db481e6847",
  pool:  "0xcacf70ae3ba1fa1dc16bea05e57ea90fef0657c0",
  usdc:  "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
};
const DEPLOY_BLOCK = 48117150n;
const LOOKBACK_DAYS = Number(process.env.LOOKBACK_DAYS || 7);

const client = createPublicClient({ chain: base, transport: http(process.env.BASE_RPC || "https://mainnet.base.org") });

const erc20 = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function totalBurned() view returns (uint256)",
]);
const vaultAbi = parseAbi([
  "function totalLocked() view returns (uint256)",
  "function totalPower() view returns (uint256)",
  "event RewardNotified(uint256 amount)",
  "event Locked(address indexed user, uint256 amount, uint256 power, uint256 end)",
]);

const fmt = (n, d = 2) => Number(n).toLocaleString("en-US", { maximumFractionDigits: d });

async function main() {
  const latest = await client.getBlock();
  // Base ≈ 2s blocks
  const lookbackBlocks = BigInt(Math.floor((LOOKBACK_DAYS * 86400) / 2));
  const fromBlock = latest.number > lookbackBlocks ? latest.number - lookbackBlocks : DEPLOY_BLOCK;

  const [locked, power, supply, burned, poolT, poolQ] = await Promise.all([
    client.readContract({ address: ADDR.vault, abi: vaultAbi, functionName: "totalLocked" }),
    client.readContract({ address: ADDR.vault, abi: vaultAbi, functionName: "totalPower" }),
    client.readContract({ address: ADDR.token, abi: erc20, functionName: "totalSupply" }),
    client.readContract({ address: ADDR.token, abi: erc20, functionName: "totalBurned" }),
    client.readContract({ address: ADDR.token, abi: erc20, functionName: "balanceOf", args: [ADDR.pool] }),
    client.readContract({ address: ADDR.usdc,  abi: erc20, functionName: "balanceOf", args: [ADDR.pool] }),
  ]);

  const [feeEvents, lockEvents] = await Promise.all([
    client.getContractEvents({ address: ADDR.vault, abi: vaultAbi, eventName: "RewardNotified", fromBlock, toBlock: latest.number }),
    client.getContractEvents({ address: ADDR.vault, abi: vaultAbi, eventName: "Locked", fromBlock, toBlock: latest.number }),
  ]);

  const wethPushed = feeEvents.reduce((s, e) => s + e.args.amount, 0n);
  const newLocked = lockEvents.reduce((s, e) => s + e.args.amount, 0n);
  const tvl = Number(formatEther(locked));
  const priceUsd = Number(formatUnits(poolQ, 6)) / Number(formatEther(poolT) || 1);

  const stats = {
    window_days: LOOKBACK_DAYS,
    epochs: feeEvents.length,
    weth_distributed: formatEther(wethPushed),
    fee_txs: feeEvents.map(e => e.transactionHash),
    new_locks: lockEvents.length,
    thsnd_newly_locked: formatEther(newLocked),
    tvl_thsnd: formatEther(locked),
    total_vthsnd: formatEther(power),
    total_burned: formatEther(burned),
    supply: formatEther(supply),
    price_usd: priceUsd,
    tvl_usd: tvl * priceUsd,
    block: String(latest.number),
    date: new Date().toISOString().slice(0, 10),
  };

  const post = [
    `THOUSAND — epoch recap · ${stats.date}`,
    ``,
    `▮ fees distributed: ${fmt(stats.weth_distributed, 6)} WETH across ${stats.epochs} epoch${stats.epochs === 1 ? "" : "s"}`,
    `▮ vault TVL: ${fmt(stats.tvl_thsnd, 0)} THSND (${fmt(stats.tvl_usd, 2)} USD)`,
    `▮ total vTHSND: ${fmt(stats.total_vthsnd, 0)}`,
    `▮ new locks this week: ${stats.new_locks} (+${fmt(stats.thsnd_newly_locked, 0)} THSND)`,
    `▮ burned to date: ${fmt(stats.total_burned, 0)} THSND — supply only goes down`,
    ``,
    stats.epochs > 0 ? `every number verifiable on-chain: ${stats.fee_txs.map(h => `basescan.org/tx/${h.slice(0, 10)}…`).join(" · ")}` : `no fee epoch this window — pushes resume when protocol fees accrue. no epoch, no post-processing, no pretending.`,
    ``,
    `rewards are fees, not inflation. thsnd.xyz`,
  ].join("\n");

  console.log("──────────────── RECAP POST ────────────────\n");
  console.log(post);
  console.log("\n──────────────── JSON ────────────────\n");
  console.log(JSON.stringify(stats, null, 2));
}

main().catch(e => { console.error("recap failed:", e.shortMessage || e.message); process.exit(1); });
