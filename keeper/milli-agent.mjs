#!/usr/bin/env node
/**
 * MILLI — trading agent (v2: shadow + live-sealed)
 *
 * SHADOW (default): no keys, no transactions. Paper portfolio vs real
 * Chainlink prices, public feed at thsnd.xyz/#milli.
 *
 * LIVE-SEALED: activates AUTOMATICALLY only when ALL of:
 *   1. keeper/.executor-key exists (0x-prefixed private key, chmod 600)
 *   2. vault.executor() on-chain == that key's address
 *   3. vault.totalAssets() > 0 (the Safe has seeded it)
 * Then the same strategy trades the vault's real (operator-only) funds via
 * vault.trade(). The vault itself enforces: 10% NAV per-trade cap, 50%/day
 * turnover, 1% oracle slippage floor, 20% cash buffer, whitelists. This
 * script cannot exceed them even if wrong.
 *
 * The live record is a NEW tape (fresh started date, shadow summary archived
 * in the feed). Price history carries over — it's market data, not results.
 *
 * Run:   node milli-agent.mjs tick          # one tick (shadow or live, auto)
 *        node milli-agent.mjs tick --dry    # live: simulate trades, send nothing
 *        node milli-agent.mjs tick --mock 1234  # SHADOW ONLY offline test
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// ---------------------------------------------------------------- strategy constants (the whole strategy)
const START_NAV = 10_000;        // paper USDC (shadow)
const FAST = 12;                 // fast SMA (ticks)
const SLOW = 48;                 // slow SMA (ticks) — warmup period
const TARGET_LONG = 0.50;        // 50% WETH exposure when fast > slow
const TARGET_FLAT = 0.00;        // 0% otherwise
const STEP_BPS = 1_000;          // move ≤10% NAV per tick (== vault per-trade cap)
const COST_BPS = 30;             // shadow: simulated cost per side
const MIN_TRADE_FLOOR = 5;       // ignore dust rebalances: min trade =
const MIN_TRADE_BPS = 50;        //   max($5, 0.5% of NAV) — $50 on the $10k shadow book, scales to small live seeds
const MINOUT_TOL = 0.006;        // live: accept ≤0.6% off oracle mid (vault floor is 1%)

// LP sleeve (SHADOW-ONLY until an audited LP adapter exists — the live vault
// has no LP path today; this previews the v2 strategy and is disclosed in the feed)
const LP_TARGET = 0.30;          // 30% of NAV in simulated WETH/USDC 50/50 LP
const LP_APR_EST = 0.10;         // assumed fee+emission APR (conservative, disclosed)
const LP_REBAL_DRIFT = 0.25;     // rebalance when sleeve drifts ±25% (relative) from target
const TICKS_PER_YEAR = 8760;     // hourly cadence

// ---------------------------------------------------------------- addresses (Base mainnet)
const FEED_ETHUSD = "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70"; // Chainlink ETH/USD
const VAULT   = "0xF925b09790035E0ef60Cd115eba7E8bDD10981d0";
const ADAPTER = "0x24a8D50b4A723614E3b0F4FAA6AeFa5b0D2C504b";     // AeroAdapter
const USDC    = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";     // 6d
const WETH    = "0x4200000000000000000000000000000000000006";     // 18d
const RPC     = process.env.BASE_RPC || "https://mainnet.base.org";

const __dir = dirname(fileURLToPath(import.meta.url));
const SHADOW_STATE = join(__dir, "milli-state.json");
const LIVE_STATE   = join(__dir, "milli-state-live.json");
const KEY_FILE     = join(__dir, ".executor-key");
const FEED_FILE    = join(__dir, "..", "website", "milli-feed.json");

const sma = (arr, n) => arr.slice(-n).reduce((s, x) => s + x, 0) / Math.min(arr.length, n);
const round = (x, d = 2) => Math.round(x * 10 ** d) / 10 ** d;
const nowIso = () => new Date().toISOString();

// ---------------------------------------------------------------- viem plumbing (lazy)
async function chain() {
  const { createPublicClient, createWalletClient, http, parseAbi } = await import("viem");
  const { base } = await import("viem/chains");
  const pub = createPublicClient({ chain: base, transport: http(RPC) });
  const abi = {
    feed:  parseAbi(["function latestAnswer() view returns (int256)"]),
    erc20: parseAbi(["function balanceOf(address) view returns (uint256)"]),
    vault: parseAbi([
      "function executor() view returns (address)",
      "function totalAssets() view returns (uint256)",
      "function tradingPaused() view returns (bool)",
      "function trade(address adapter, address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) returns (uint256)",
    ]),
  };
  return { pub, abi, base, createWalletClient, http };
}

async function getPrice(injected, live) {
  if (injected && !live) return Number(injected);           // mock allowed in shadow only
  const { pub, abi } = await chain();
  const ans = await pub.readContract({ address: FEED_ETHUSD, abi: abi.feed, functionName: "latestAnswer" });
  return Number(ans) / 1e8;
}

// ---------------------------------------------------------------- live detection
async function liveContext() {
  if (!existsSync(KEY_FILE)) return null;
  const pk = readFileSync(KEY_FILE, "utf8").trim();
  if (!/^0x[0-9a-fA-F]{64}$/.test(pk)) { console.error("live: .executor-key malformed — staying shadow"); return null; }
  const { privateKeyToAccount } = await import("viem/accounts");
  const account = privateKeyToAccount(pk);
  const { pub, abi, base, createWalletClient, http } = await chain();
  const [exec, ta] = await Promise.all([
    pub.readContract({ address: VAULT, abi: abi.vault, functionName: "executor" }),
    pub.readContract({ address: VAULT, abi: abi.vault, functionName: "totalAssets" }),
  ]);
  if (exec.toLowerCase() !== account.address.toLowerCase())
    return { waiting: `key ready (${account.address}) but vault executor is ${exec} — execute the Safe batch` };
  if (ta === 0n) return { waiting: "executor armed but vault unseeded — run the Safe deposit" };
  const wallet = createWalletClient({ account, chain: base, transport: http(RPC) });
  return { account, pub, abi, wallet, totalAssets: ta };
}

// ---------------------------------------------------------------- state
function loadShadow() {
  let s;
  if (existsSync(SHADOW_STATE)) s = JSON.parse(readFileSync(SHADOW_STATE, "utf8"));
  else s = { mode: "shadow", started: nowIso(), startNav: START_NAV, usdc: START_NAV, weth: 0,
             prices: [], navHistory: [], trades: [], ticks: 0 };
  if (s.costsPaid == null) { // backfill from tape: LP legs cost COST_BPS/2, spot legs COST_BPS
    s.costsPaid = (s.trades || []).reduce((c, t) =>
      c + (t.side?.startsWith("LP") ? (t.usd || 0) * (COST_BPS / 2) : (t.usdc || t.usd || 0) * COST_BPS) / 10_000, 0);
  }
  if (s.lpFeesEarned == null) s.lpFeesEarned = s.lp?.fees || 0;
  if (s.lp && s.lp.basis == null) s.lp.basis = round(s.lp.k * Math.sqrt(s.lp.entryPx) / (1 - COST_BPS / 2 / 10_000));
  if (s.wethBasisUsd == null) s.wethBasisUsd = 0;
  return s;
}

// what the book holds right now, entry vs value, per sleeve
function buildPositions(s, px) {
  const pos = [];
  if (s.lp) {
    const v = lpValue(s.lp, px);
    pos.push({ name: "WETH/USDC LP", size: "50/50 pool share", entry: `$${round(s.lp.basis)} @ ETH ${round(s.lp.entryPx)}`,
               opened: s.lp.opened, value: round(v), pnl: round(v - s.lp.basis),
               note: `incl. fees +$${round(s.lp.fees)} · IL priced exactly` });
  }
  if (s.weth > 1e-9) {
    const v = s.weth * px;
    pos.push({ name: "WETH · momentum", size: `${round(s.weth, 4)} WETH`, entry: `avg $${round(s.wethBasisUsd / s.weth)}`,
               value: round(v), pnl: round(v - s.wethBasisUsd) });
  }
  return pos;
}

function loadLive(startNavUsd) {
  if (existsSync(LIVE_STATE)) return JSON.parse(readFileSync(LIVE_STATE, "utf8"));
  const s = { mode: "live-sealed", started: nowIso(), startNav: round(startNavUsd),
              prices: [], navHistory: [], trades: [], ticks: 0, priceWindowInherited: false, shadowArchive: null };
  if (existsSync(SHADOW_STATE)) {
    const sh = JSON.parse(readFileSync(SHADOW_STATE, "utf8"));
    s.prices = sh.prices || [];
    s.priceWindowInherited = s.prices.length > 0;
    const lastNav = sh.navHistory?.length ? sh.navHistory[sh.navHistory.length - 1].nav : sh.startNav;
    s.shadowArchive = { started: sh.started, ended: nowIso(), startNav: sh.startNav,
                        finalNav: lastNav, trades: (sh.trades || []).length, ticks: sh.ticks };
  }
  return s;
}

function decide(s, px, navUsd, exposureUsd, cashUsd) {
  if (s.prices.length < SLOW) return { action: `warmup ${s.prices.length}/${SLOW} — collecting samples, no trades` };
  const fast = sma(s.prices, FAST), slow = sma(s.prices, SLOW);
  const target = fast > slow ? TARGET_LONG : TARGET_FLAT;
  let deltaUsd = navUsd * target - exposureUsd;
  const maxStep = navUsd * STEP_BPS / 10_000;
  deltaUsd = Math.max(-maxStep, Math.min(maxStep, deltaUsd));
  if (deltaUsd > 0) deltaUsd = Math.min(deltaUsd, Math.max(0, cashUsd - navUsd * 0.20)); // respect vault cash buffer
  const minTrade = Math.max(MIN_TRADE_FLOOR, navUsd * MIN_TRADE_BPS / 10_000);
  if (Math.abs(deltaUsd) < minTrade)
    return { action: `hold — fast ${round(fast)} ${fast > slow ? ">" : "≤"} slow ${round(slow)}, exposure on target` };
  const reason = deltaUsd > 0
    ? `fast SMA ${round(fast)} > slow ${round(slow)} → target ${TARGET_LONG * 100}% WETH`
    : `fast SMA ${round(fast)} ≤ slow ${round(slow)} → target ${TARGET_FLAT * 100}% WETH`;
  return { deltaUsd, reason };
}

function publish(s, extraState) {
  const { prices, ...pub } = s;
  pub.state = { ...extraState, updated: nowIso() };
  writeFileSync(FEED_FILE, JSON.stringify(pub, null, 2));
}

// ---------------------------------------------------------------- shadow LP sleeve (simulated 50/50 AMM position)
// LP USD value at price p, entered at price e with notional N: N·√(p/e) + accrued fees.
// That's the exact constant-product result — impermanent loss is priced in, not estimated.
function lpValue(lp, px) { return lp ? lp.k * Math.sqrt(px) + lp.fees : 0; }

function manageLp(s, px, navUsd, t) {
  const events = [];
  if (s.lp) {
    const acc = lpValue(s.lp, px) * LP_APR_EST / TICKS_PER_YEAR; // hourly fee accrual on current value
    s.lp.fees += acc;
    s.lpFeesEarned = (s.lpFeesEarned || 0) + acc;
  }
  const v = lpValue(s.lp, px);
  const target = navUsd * LP_TARGET;
  const drifted = s.lp && Math.abs(v - target) / target > LP_REBAL_DRIFT;
  if ((!s.lp && s.usdc >= target) || drifted) {
    if (s.lp) { s.usdc += v; events.push({ t, side: "LP-CLOSE", usd: round(v), px: round(px), reason: `sleeve drifted to ${round(100 * v / navUsd, 1)}% of NAV (target ${LP_TARGET * 100}%)`, navAfter: 0 }); s.lp = null; }
    const notional = Math.min(navUsd * LP_TARGET, s.usdc);
    if (notional >= Math.max(MIN_TRADE_FLOOR, navUsd * MIN_TRADE_BPS / 10_000)) {
      const cost = notional * (COST_BPS / 2) / 10_000;        // half the notional swaps to WETH on entry
      s.costsPaid = (s.costsPaid || 0) + cost;
      s.usdc -= notional;
      s.lp = { entryPx: px, k: (notional - cost) / Math.sqrt(px), fees: 0, opened: t, basis: notional };
      events.push({ t, side: "LP-OPEN", usd: round(notional), px: round(px), reason: `deploy ${LP_TARGET * 100}% of NAV to WETH/USDC LP — est ${LP_APR_EST * 100}% APR (simulated, disclosed), IL priced exactly`, navAfter: 0 });
    }
  }
  return events;
}

// ---------------------------------------------------------------- shadow tick (momentum sleeve + LP sleeve)
async function shadowTick(mock, note) {
  const s = loadShadow();
  const px = await getPrice(mock, false);
  const t = Math.floor(Date.now() / 1000);
  s.ticks += 1; s.prices.push(px);
  if (s.prices.length > SLOW * 4) s.prices.shift();
  const nav = () => s.usdc + s.weth * px + lpValue(s.lp, px);

  const lpEvents = manageLp(s, px, nav(), t);
  for (const ev of lpEvents) { ev.navAfter = round(nav()); s.trades.push(ev); }

  const d = decide(s, px, nav(), s.weth * px, s.usdc);
  let action = d.action;
  if (!action) {
    if (d.deltaUsd > 0) {
      const spend = Math.min(d.deltaUsd, s.usdc);
      const got = (spend / px) * (1 - COST_BPS / 10_000);
      s.usdc -= spend; s.weth += got;
      s.wethBasisUsd = (s.wethBasisUsd || 0) + spend;
      s.costsPaid = (s.costsPaid || 0) + spend * COST_BPS / 10_000;
      s.trades.push({ t, side: "BUY", usdc: round(spend), weth: round(got, 6), px: round(px), reason: d.reason, navAfter: round(nav()) });
      action = `BUY ${round(spend)} USDC → ${round(got, 6)} WETH @ ${round(px)}`;
    } else {
      const sellWeth = Math.min(-d.deltaUsd / px, s.weth);
      const got = sellWeth * px * (1 - COST_BPS / 10_000);
      s.costsPaid = (s.costsPaid || 0) + sellWeth * px * COST_BPS / 10_000;
      s.wethBasisUsd = s.weth > 0 ? (s.wethBasisUsd || 0) * (1 - sellWeth / s.weth) : 0;
      s.weth -= sellWeth; s.usdc += got;
      if (s.weth < 1e-9) { s.weth = 0; s.wethBasisUsd = 0; }
      s.trades.push({ t, side: "SELL", usdc: round(got), weth: round(sellWeth, 6), px: round(px), reason: d.reason, navAfter: round(nav()) });
      action = `SELL ${round(sellWeth, 6)} WETH → ${round(got)} USDC @ ${round(px)}`;
    }
  }
  s.navHistory.push({ t, nav: round(nav()), px: round(px) });
  if (s.navHistory.length > 5000) s.navHistory.shift();
  writeFileSync(SHADOW_STATE, JSON.stringify(s, null, 2));
  const pnl = 100 * (nav() - s.startNav) / s.startNav;
  const warm = s.prices.length < SLOW;
  const status = `${pnl >= 0 ? "up" : "down"} ${Math.abs(pnl).toFixed(2)}% since start · ` +
    `$${round(s.costsPaid)} paid in simulated costs · $${round(s.lpFeesEarned)} earned in simulated LP fees · ` +
    `momentum sleeve ${warm ? `in warmup (${s.prices.length}/${SLOW}) — not allowed to trade yet` : (s.weth > 0 ? "LONG" : "FLAT")}`;
  publish(s, { usdc: round(s.usdc), weth: round(s.weth, 6), lp: round(lpValue(s.lp, px)),
               positions: buildPositions(s, px),
               costs: round(s.costsPaid), lpFees: round(s.lpFeesEarned, 4),
               warmup: warm ? `${s.prices.length}/${SLOW}` : null, status,
               lpAprEst: LP_APR_EST, strategy: "v2: momentum + 30% LP sleeve (LP simulated, fees estimated, IL exact)",
               px: round(px), nav: round(nav()) });
  console.log(`[milli ${nowIso()}] SHADOW px=${round(px)} nav=${round(nav())} lp=${round(lpValue(s.lp, px))} | ${action}${note ? " | " + note : ""}`);
}

// ---------------------------------------------------------------- live tick
async function liveTick(ctx, dry) {
  const { pub, abi, wallet, account } = ctx;
  const px = await getPrice(null, true);
  const t = Math.floor(Date.now() / 1000);

  const [ta, wethBal, usdcBal, paused, gas] = await Promise.all([
    pub.readContract({ address: VAULT, abi: abi.vault, functionName: "totalAssets" }),
    pub.readContract({ address: WETH, abi: abi.erc20, functionName: "balanceOf", args: [VAULT] }),
    pub.readContract({ address: USDC, abi: abi.erc20, functionName: "balanceOf", args: [VAULT] }),
    pub.readContract({ address: VAULT, abi: abi.vault, functionName: "tradingPaused" }),
    pub.getBalance({ address: account.address }),
  ]);
  const navUsd = Number(ta) / 1e6;
  const exposureUsd = Number(wethBal) / 1e18 * px;
  const cashUsd = Number(usdcBal) / 1e6;

  const s = loadLive(navUsd);
  s.ticks += 1; s.prices.push(px);
  if (s.prices.length > SLOW * 4) s.prices.shift();
  const notice = gas < 500_000_000_000_000n ? "executor gas low (<0.0005 ETH) — top up" : undefined;

  let action;
  let wethNow = Number(wethBal) / 1e18;
  const d = paused ? { action: "trading paused by guardian — holding" } : decide(s, px, navUsd, exposureUsd, cashUsd);
  if (d.action) { action = d.action; }
  else {
    const buy = d.deltaUsd > 0;
    let args;
    if (buy) {
      const spend = Math.min(d.deltaUsd, cashUsd);
      const amountIn = BigInt(Math.round(spend * 1e6));                       // USDC 6d
      const minOut = BigInt(Math.round((spend / px) * (1 - MINOUT_TOL) * 1e6)) * 10n ** 12n; // WETH 18d
      args = [ADAPTER, USDC, WETH, amountIn, minOut];
    } else {
      const sellWeth = Math.min(-d.deltaUsd / px, Number(wethBal) / 1e18);
      let amountIn = BigInt(Math.round(sellWeth * 1e6)) * 10n ** 12n;         // WETH 18d
      if (amountIn > wethBal) amountIn = wethBal;
      const minOut = BigInt(Math.round(sellWeth * px * (1 - MINOUT_TOL) * 1e6)); // USDC 6d
      args = [ADAPTER, WETH, USDC, amountIn, minOut];
    }
    try {
      const sim = await pub.simulateContract({ address: VAULT, abi: abi.vault, functionName: "trade", args, account });
      if (dry) {
        action = `DRY-RUN ${buy ? "BUY" : "SELL"} ok (would send): ${d.reason}`;
      } else {
        const hash = await wallet.writeContract(sim.request);
        const rcpt = await pub.waitForTransactionReceipt({ hash, timeout: 120_000 });
        const [ta2, weth2] = await Promise.all([
          pub.readContract({ address: VAULT, abi: abi.vault, functionName: "totalAssets" }),
          pub.readContract({ address: WETH, abi: abi.erc20, functionName: "balanceOf", args: [VAULT] }),
        ]);
        const tr = { t, side: buy ? "BUY" : "SELL", usd: round(Math.abs(d.deltaUsd)), px: round(px),
                     reason: d.reason, tx: hash, status: rcpt.status, navAfter: round(Number(ta2) / 1e6),
                     wethAfter: round(Number(weth2) / 1e18, 6) };
        s.trades.push(tr);
        if (rcpt.status === "success") {
          if (buy) s.wethBasisUsd = (s.wethBasisUsd || 0) + tr.usd;
          else s.wethBasisUsd = tr.wethAfter > 1e-9 && wethNow > 0 ? (s.wethBasisUsd || 0) * (tr.wethAfter / wethNow) : 0;
          wethNow = tr.wethAfter;
        }
        action = `${tr.side} ~$${tr.usd} @ ${tr.px} → ${hash} (${rcpt.status})`;
      }
    } catch (e) {
      action = `trade blocked: ${e.shortMessage || e.message} — holding`; // vault caps/floors said no; that's the system working
    }
  }

  s.navHistory.push({ t, nav: round(navUsd), px: round(px) });
  if (s.navHistory.length > 5000) s.navHistory.shift();
  writeFileSync(LIVE_STATE, JSON.stringify(s, null, 2));
  const lPnl = 100 * (navUsd - s.startNav) / s.startNav;
  const lPos = wethNow > 1e-9
    ? [{ name: "WETH · momentum (on-chain)", size: `${round(wethNow, 4)} WETH`,
         entry: `avg $${round((s.wethBasisUsd || 0) / wethNow)}`, value: round(wethNow * px),
         pnl: round(wethNow * px - (s.wethBasisUsd || 0)) }]
    : [];
  const lStatus = `${lPnl >= 0 ? "up" : "down"} ${Math.abs(lPnl).toFixed(2)}% since live start · operator funds only, sealed · ` +
    `momentum sleeve ${s.prices.length < SLOW ? `in warmup (${s.prices.length}/${SLOW})` : (wethNow > 1e-9 ? "LONG" : "FLAT")} · every trade has a tx hash`;
  publish(s, { usdc: round(cashUsd), weth: round(wethNow, 6), positions: lPos, status: lStatus,
               px: round(px), nav: round(navUsd),
               vault: VAULT, executor: account.address, ...(notice ? { notice } : {}) });
  console.log(`[milli ${nowIso()}] LIVE-SEALED px=${round(px)} nav=${round(navUsd)} | ${action}`);
}

// ---------------------------------------------------------------- main
const [, , cmd, flag, val] = process.argv;
if (cmd !== "tick") { console.log("usage: node milli-agent.mjs tick [--dry] [--mock <price>]"); process.exit(1); }
const dry = flag === "--dry";
const mock = (flag === "--mock" || flag === "--px") ? val : null;

(async () => {
  let ctx = null;
  try { ctx = await liveContext(); } catch (e) { console.error("live check failed:", e.shortMessage || e.message, "— shadow tick"); }
  if (ctx && !ctx.waiting) await liveTick(ctx, dry);
  else await shadowTick(mock, ctx?.waiting);
})().catch(e => { console.error("tick failed:", e.shortMessage || e.message); process.exit(1); });
