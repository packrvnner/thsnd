# MILLI_RUNBOOK — running the shadow agent

## Zero-touch mode (default — already set up)

A Claude scheduled task (**milli-hourly-tick**) runs every hour while the Claude app is open on this Mac: it reads the real Chainlink ETH/USD price, runs one tick of the agent, and republishes thsnd.xyz/#milli automatically whenever a trade happens (or at least once a day). Click **Run now** on it once in the Scheduled sidebar to pre-approve its tools so unattended runs never stall. If the app is closed, ticks pause and resume on next launch — the record just has a gap, which is honest.

## Manual operation (backup / if you prefer cron)

```bash
cd keeper && node milli-agent.mjs tick   # one tick: reads real ETH/USD from Chainlink on Base
```
Then redeploy the `website` folder (drag `thsnd-site-v2.zip` rebuilt, or the folder itself, onto the Netlify project) — that publishes the updated `milli-feed.json` to thsnd.xyz/#milli.

Automate ticks hourly on your Mac:
```bash
crontab -e
# add:
0 * * * * cd /Users/willmartin/Claude/Projects/$MUY/keeper && /usr/local/bin/node milli-agent.mjs tick >> milli.log 2>&1
```
(One-time: `cd keeper && npm init -y && npm install viem`.)
Publishing cadence is yours — ticks accumulate locally either way; each site deploy publishes everything since the last one. Once daily is plenty during warmup.

## What the agent does (v1 — the strategy is the disclosure)

12/48-tick SMA momentum on ETH/USD. Above the slow average → target 50% WETH; below → 0%. Moves in ≤10%-of-NAV steps (mirrors the real vault's per-trade cap), 0.30% simulated cost per side, minimum trade = max($5, 0.5% of NAV) — $50 on the $10k paper book, smaller on small live seeds (changed 2026-07-03, disclosed here).

**v2 (added 2026-07-03, during warmup):** a second sleeve keeps 30% of NAV in a simulated
WETH/USDC 50/50 LP — impermanent loss computed exactly from the constant-product formula,
fee+emission income estimated at a disclosed 10% APR, ±25% drift rebalancing with costs.
SHADOW-ONLY: the live vault has no LP path until an LP adapter contract is written and
audited (goes in the audit bundle). The feed labels the strategy string accordingly. First 48 ticks are warmup — it refuses to trade until it has data. Every trade carries its reason string into the public tape.

Tuning = editing the constants at the top of `keeper/milli-agent.mjs`. If you change them mid-run, say so publicly — the point of shadow mode is an untampered record.

## Honesty rails

- Never edit `milli-state.json` / `milli-feed.json` by hand. A doctored paper record is worse than a losing one — losing weeks are content ("MILLI sat out the chop, -0.4% on costs"), doctored records are project-enders.
- The page banner says PAPER everywhere. Keep it that way until the audited vault opens.
- If you restart the record, disclose it on the page (new `started` date does this automatically).

## Mode A go-live — operator funds only, vault sealed (allowed today)

This puts real (your own) money behind the public tape without opening deposits to
anyone. No offering, no exemption needed — see docs/LEGAL_MEMO.md for why this is the
only configuration permitted before audit + counsel.

1. Generate a fresh executor key **locally** (`cast wallet new`, or any wallet you trust).
   Nothing else ever lives on this key. Never paste the private key into chat or cloud.
2. Fund the Safe with your seed USDC on Base (it held ~$0.73 as of 2026-07-03).
3. `node tools/make-golive-batch.mjs --executor 0xYOURKEY --seed 500`
   → writes `milli-golive.json`: setRoles → seal caps at seed → approve → deposit.
4. app.safe.global → Transaction Builder → drag `milli-golive.json` → **simulate** → execute.
5. Send ~0.003 ETH to the executor key for trade gas.
6. Switch the keeper to live mode (executor key signs real `vault.trade()` calls —
   ask Claude for this wiring; not written yet) and set `"mode":"live-sealed"` in the
   feed. The site banner flips to LIVE — CLOSED TO DEPOSITS automatically.
7. Disclose the mode switch on the page/tape, same honesty rails as shadow mode.

Raising the caps later = opening deposits = the full checklist below first. No shortcuts.

## Go-live checklist (later, after audit — see AGENT_VAULT_SPEC.md)

- [ ] 4–8 weeks of continuous shadow record published
- [ ] Audit of AgentVault/AeroAdapter/FeeSink complete + published
- [ ] Deploy contracts from Safe; wire: `lattice.setFeeNotifier(feeSink)`, `engine.setRoute(WETH, adapter)`, vault caps/whitelists (WETH + Chainlink feed), executor = dedicated hot key with nothing else on it
- [ ] Legal consult on the pooled-vault structure (spec's legal section in hand)
- [ ] Launch caps: $25k vault / $2k per wallet; MILLI page switches from PAPER to LIVE with the same tape
