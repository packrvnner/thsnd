# EPOCH_RUNBOOK — the weekly fee push, step by step

**Cadence: every Thursday 00:00 UTC** (Aerodrome's epoch rhythm — Base users already live on it). Same steps every week; the ritual is the product. Total time: ~10 minutes.

## What an epoch is

You push WETH into the vault via `notifyReward(amount)`. The contract splits it pro-rata across all vTHSND instantly. It cannot be taken back, and only the vault owner (the treasury Safe) or an appointed fee-notifier can call it. The site's APR / FEES stats and charts light up automatically from the on-chain event — no site changes needed, ever.

**Where the WETH comes from:** protocol fee revenue held by the Safe. If a week has no revenue, push nothing — a zero week displayed honestly beats a subsidized fake yield. (Seeding the first epoch or two with a small treasury amount to demonstrate the machine is a legitimate, disclosable choice — if you do it, say so publicly.)

## Steps (from app.safe.global, connected to the Safe `0x539D…877C`)

1. **Decide the amount.** Whatever WETH fee revenue accrued this week. Write it down before you open the Safe.
2. **Tx 1 — approve:** WETH (`0x4200000000000000000000000000000000000006`) → `approve(spender, amount)` with spender = vault `0x1141F662b0647C2776Bb6A59B0ECA3Db481e6847`.
3. **Tx 2 — push:** vault → `notifyReward(amount)`. (Use "Transaction Builder" in the Safe UI; ABI loads automatically since the contract is verified. Both txs can go in one Safe batch.)
4. **Verify:** the vault page at thsnd.xyz — FEES DISTRIBUTED and APR update within ~2 minutes; LAST FEE EPOCH shows today.
5. **Generate the recap:** `cd keeper && node epoch-recap.mjs` — copy the printed post to X/Farcaster. Every number in it comes from chain, with tx hashes.

## Guardrails

- `notifyReward` reverts if `totalPower == 0` (no lockers). Currently fine — 199 vTHSND exists.
- Don't appoint a hot-wallet fee-notifier until it holds only dust and you've tested it: `setFeeNotifier(addr)` from the Safe. Until then, epochs come from the Safe and that's fine.
- Never announce an APR target. Post what was distributed, after it's distributed. The measured APR on the site is the only yield number that should ever exist publicly.
- The Safe is 1-of-1 today (disclosed on the DOCS page). Expanding signers is Phase 1 — until then, guard that key like it's the whole project, because it is.

## First epoch checklist (one-time)

- [ ] Pick amount + write the disclosure line if treasury-seeded ("epoch 1 seeded from treasury to demonstrate the fee path")
- [ ] Run steps 2–5 above
- [ ] Screenshot the vault page APR/fees lighting up — that's the launch post
- [ ] Pin the recap; link the DOCS security section in replies
