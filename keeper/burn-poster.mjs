#!/usr/bin/env node
/**
 * [ M U Y ] burn poster
 *
 * Watches the MUY token's Burned events on Base mainnet and auto-posts
 * each burn to X (Twitter) and/or Farcaster. Runs independently of the
 * burn keeper — it reacts to on-chain truth, not to the bot that caused it.
 *
 * Setup:
 *   npm install viem
 *   # X: create app at developer.x.com (needs paid Basic tier for posting),
 *   #    generate user-context OAuth 1.0a keys:
 *   export X_APP_KEY=...  X_APP_SECRET=...  X_ACCESS_TOKEN=...  X_ACCESS_SECRET=...
 *   # Farcaster via Neynar (neynar.com, free tier works):
 *   export NEYNAR_API_KEY=...  NEYNAR_SIGNER_UUID=...
 *   export BASE_RPC=https://mainnet.base.org
 *   node burn-poster.mjs
 *
 * Leave either platform's keys unset to skip it. Every post links the tx —
 * rule #1 of the launch kit: never post a number that isn't checkable.
 */
import crypto from "node:crypto";
import { createPublicClient, http, parseAbiItem, formatUnits } from "viem";
import { base } from "viem/chains";

const MUY = "0xC665637C9d25efaccee5F1beEe5520Ec707a9ce1";
const BURNED = parseAbiItem("event Burned(address indexed from, uint256 amount, uint256 newTotalSupply)");
const GENESIS = 1_000_000_000n * 10n ** 18n;
const POLL_MS = 30_000;
const MIN_POST_AMOUNT = 10n ** 18n; // skip dust burns < 1 MUY

const pub = createPublicClient({ chain: base, transport: http(process.env.BASE_RPC ?? "https://mainnet.base.org") });

const fmt = (wei) => Number(formatUnits(wei, 18)).toLocaleString("en-US", { maximumFractionDigits: 0 });

function buildPost(log) {
  const burned = GENESIS - log.args.newTotalSupply;
  return [
    `SYS: ${fmt(log.args.amount)} MUY destroyed.`,
    `cumulative: ${fmt(burned)} MUY`,
    `supply: ${fmt(log.args.newTotalSupply)} MUY`,
    `tx: https://basescan.org/tx/${log.transactionHash}`,
  ].join("\n");
}

// ---------------- X (OAuth 1.0a user context, POST /2/tweets) ----------------
async function postToX(text) {
  const { X_APP_KEY, X_APP_SECRET, X_ACCESS_TOKEN, X_ACCESS_SECRET } = process.env;
  if (!X_APP_KEY) return;
  const url = "https://api.x.com/2/tweets";
  const oauth = {
    oauth_consumer_key: X_APP_KEY,
    oauth_nonce: crypto.randomBytes(16).toString("hex"),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
    oauth_token: X_ACCESS_TOKEN,
    oauth_version: "1.0",
  };
  const enc = encodeURIComponent;
  const paramStr = Object.keys(oauth).sort().map((k) => `${enc(k)}=${enc(oauth[k])}`).join("&");
  const baseStr = `POST&${enc(url)}&${enc(paramStr)}`;
  const signKey = `${enc(X_APP_SECRET)}&${enc(X_ACCESS_SECRET)}`;
  oauth.oauth_signature = crypto.createHmac("sha1", signKey).update(baseStr).digest("base64");
  const header = "OAuth " + Object.keys(oauth).sort().map((k) => `${enc(k)}="${enc(oauth[k])}"`).join(", ");
  const res = await fetch(url, {
    method: "POST",
    headers: { Authorization: header, "Content-Type": "application/json" },
    body: JSON.stringify({ text }),
  });
  if (!res.ok) console.error("X post failed:", res.status, await res.text());
  else console.log("posted to X");
}

// ---------------- Farcaster via Neynar ----------------
async function postToFarcaster(text) {
  const { NEYNAR_API_KEY, NEYNAR_SIGNER_UUID } = process.env;
  if (!NEYNAR_API_KEY) return;
  const res = await fetch("https://api.neynar.com/v2/farcaster/cast", {
    method: "POST",
    headers: { "x-api-key": NEYNAR_API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ signer_uuid: NEYNAR_SIGNER_UUID, text }),
  });
  if (!res.ok) console.error("Farcaster post failed:", res.status, await res.text());
  else console.log("posted to Farcaster");
}

// ---------------- watcher ----------------
let lastBlock = await pub.getBlockNumber();
console.log(`SYS: burn poster online. watching ${MUY} from block ${lastBlock}`);

setInterval(async () => {
  try {
    const now = await pub.getBlockNumber();
    if (now <= lastBlock) return;
    const logs = await pub.getLogs({ address: MUY, event: BURNED, fromBlock: lastBlock + 1n, toBlock: now });
    lastBlock = now;
    for (const log of logs) {
      if (log.args.amount < MIN_POST_AMOUNT) continue;
      const text = buildPost(log);
      console.log("---\n" + text);
      await Promise.allSettled([postToX(text), postToFarcaster(text)]);
    }
  } catch (e) {
    console.error("tick failed:", e.shortMessage ?? e.message);
  }
}, POLL_MS);
