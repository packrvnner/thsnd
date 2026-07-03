#!/usr/bin/env node
// make-golive-batch.mjs — MILLI "Mode A" go-live: operator funds only, vault sealed.
//
// Generates milli-golive.json for the Safe Transaction Builder
// (app.safe.global → New transaction → Transaction Builder → drag the file in).
//
// Usage:
//   node tools/make-golive-batch.mjs --executor 0xYOUR_FRESH_HOT_KEY --seed 500
//
//   --executor  fresh EOA that will run trades. Generate it LOCALLY (e.g.
//               `cast wallet new` or a fresh wallet). Nothing else on this key.
//               Never paste its PRIVATE key anywhere, including chat/cloud.
//   --seed      operator seed in USDC (e.g. 500 = $500). Vault cap is set to
//               exactly this, so third-party deposits become impossible.
//
// The batch executes, in order, all from the Safe:
//   1. vault.setRoles(SAFE, executor, FEESINK)   — arm the agent key
//   2. vault.setDepositCaps(seed, seed)          — seal the vault at your seed
//   3. usdc.approve(vault, seed)
//   4. vault.deposit(seed, SAFE)                 — Safe owns 100% of mTHSND
//
// Preflight (the script checks none of this — do it yourself):
//   • Safe must hold ≥ seed USDC on Base (it held ~$0.73 on 2026-07-03 — fund it first)
//   • Your signer EOA needs a little ETH on Base for gas
//   • Executor EOA needs ~0.003 ETH for trade gas (send after batch executes)

const VAULT   = "0xF925b09790035E0ef60Cd115eba7E8bDD10981d0"; // AgentVault (Base)
const SAFE    = "0x539DE6F65dECEB2F491237e3DC030494E517877C"; // guardian/treasury
const FEESINK = "0x650d2837BF2d5ff7DbD216cf9aFD0C47c726fdEF";
const USDC    = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"; // native USDC (Base), 6 decimals
                                                              // = vault.usdc(), verified on-chain

// selectors (keccak-256 of the signature, first 4 bytes — computed with viem):
const SEL = {
  setRoles:       "0x54841e94", // setRoles(address,address,address)
  setDepositCaps: "0x0bfedc8c", // setDepositCaps(uint256,uint256)
  approve:        "0x095ea7b3", // approve(address,uint256)
  deposit:        "0x6e553f65", // deposit(uint256,address)
};

const NOT_EXECUTOR = new Set([SAFE, VAULT, FEESINK, USDC,
  "0x24a8D50b4A723614E3b0F4FAA6AeFa5b0D2C504b", // AeroAdapter
  "0x56AD0fe454694F7dF4c4B3E32c8A59133f567fA8", // discarded deployer
].map(a => a.toLowerCase()));

// ---- args ----
const args = process.argv.slice(2);
const get = f => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : undefined; };
const executor = get("--executor");
const seedStr  = get("--seed");

const die = m => { console.error("✗ " + m); process.exit(1); };

if (!executor || !/^0x[0-9a-fA-F]{40}$/.test(executor)) die("--executor must be a 0x address (40 hex chars)");
if (NOT_EXECUTOR.has(executor.toLowerCase())) die("--executor must be a FRESH key, not a protocol/treasury address");
if (executor.toLowerCase() === executor || executor.toUpperCase() === executor)
  console.warn("⚠ executor has no mixed-case checksum — triple-check you typed it correctly");
if (!seedStr) die("--seed required (USDC, e.g. 500)");
if (!/^\d+(\.\d{1,6})?$/.test(seedStr)) die("--seed must be a positive USDC amount with ≤6 decimals");
const [w, f = ""] = seedStr.split(".");
const seed = BigInt(w) * 1000000n + BigInt((f + "000000").slice(0, 6));
if (seed <= 0n) die("--seed must be > 0");
if (seed > 25000n * 1000000n) console.warn("⚠ seed exceeds the $25k launch cap in the spec — deliberate?");

// ---- encode ----
const pad = h => h.replace(/^0x/, "").toLowerCase().padStart(64, "0");
const addr = a => pad(a);
const u256 = n => n.toString(16).padStart(64, "0");
const tx = (to, data) => ({ to, value: "0", data, contractMethod: null, contractInputsValues: null });

const batch = {
  version: "1.0",
  chainId: "8453",
  createdAt: Date.now(),
  meta: {
    name: "MILLI go-live (Mode A: operator funds only, sealed)",
    description: `setRoles(executor=${executor}) → seal caps at ${seedStr} USDC → approve → deposit from Safe. No third-party deposit path exists after this batch.`,
    txBuilderVersion: "1.16.0",
  },
  transactions: [
    tx(VAULT, SEL.setRoles + addr(SAFE) + addr(executor) + addr(FEESINK)),
    tx(VAULT, SEL.setDepositCaps + u256(seed) + u256(seed)),
    tx(USDC,  SEL.approve + addr(VAULT) + u256(seed)),
    tx(VAULT, SEL.deposit + u256(seed) + addr(SAFE)),
  ],
};

const out = new URL("../milli-golive.json", import.meta.url).pathname;
const fs = await import("node:fs");
fs.writeFileSync(out, JSON.stringify(batch, null, 2));

console.log(`✓ wrote ${out}
  1. setRoles        guardian=Safe  executor=${executor}  feeSink=${FEESINK}
  2. setDepositCaps  vaultCap=${seedStr} USDC  perWalletCap=${seedStr} USDC  (sealed)
  3. approve         USDC → vault, ${seedStr}
  4. deposit         ${seedStr} USDC → mTHSND minted to the Safe

Next: fund the Safe with ${seedStr} USDC on Base → app.safe.global → Transaction Builder → drag milli-golive.json → simulate → execute.
Then send ~0.003 ETH to the executor key and switch the keeper to live mode (see MILLI_RUNBOOK.md).`);
