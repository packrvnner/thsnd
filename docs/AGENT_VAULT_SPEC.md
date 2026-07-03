# AGENT_VAULT_SPEC — "MILLI": the transparent 24/7 agent portfolio

*Draft v1 · July 2, 2026 · the revenue engine for THSND*

## The idea in one paragraph

A second vault, **MILLI** (one thousandth — the agent that trades the milliseconds), holds a USDC-denominated portfolio managed by an AI agent that trades 24/7 on Base DEXs. Depositors get **mTHSND** — standard ERC-4626 shares whose value tracks the portfolio NAV. Every holding and every trade is public *by construction*, because the portfolio IS an on-chain address. The protocol earns **fees on assets and activity — not on being right** — and routes them into the existing machine: WETH to vTHSND lockers via `notifyReward`, THSND buy-and-burn via the BurnEngine. This is the stable, scalable revenue source: it scales with AUM and usage, and it pays the lockers real cash flow whether markets go up or down.

## Why this is the right revenue model (evidence)

- **Virtuals Protocol** turned agent activity into ~$59M/yr protocol revenue via 1% interaction fees + revenue-funded buyback-burns of agent tokens — proof the "agent with a token" category monetizes at scale ([Virtuals whitepaper](https://whitepaper.virtuals.io/builders-hub/agent-ecosystem), [revenue analysis](https://coinstats.app/ai/a/fundamental-analysis-virtual-protocol)).
- **Bankr** charges a flat 0.8% per agent-executed transaction and routes it to $BNKR buybacks — ~$580k annualized on a modest user base ([The Defiant](https://thedefiant.io/news/defi/trading-bot-bankr-adds-solana-support), [docs](https://docs.bankr.bot/)).
- **GLP/HLP precedent**: pooled vaults with public composition (GMX's GLP, Hyperliquid's HLP) are the most successful "deposit and let the machine work" products in DeFi — and HLP's full transparency is exactly why people trust it.
- **THSND's edge vs. all three:** the fee sink already exists and is battle-designed — `notifyReward` (lockers) + BurnEngine (burn). No new tokenomics needed. The agent vault just feeds the machine.

## What we take and what we reject

| From | Take | Reject |
|---|---|---|
| Virtuals | revenue → buyback-burn loop; agent-as-character with public identity | launchpad/bonding-curve casino; a new token per agent (we have THSND) |
| Bankr | flat activity fee, dead-simple; agent posts publicly | custodial execution keys over user wallets |
| GLP/HLP | ERC-4626 pooled NAV; composition public at all times | being the counterparty to traders (we don't run a perp book) |

## Architecture (Base, 3 contracts + 1 bot)

```
depositor ──USDC──▶ [ AgentVault (ERC-4626, mTHSND shares) ]
                        │ holds: USDC + whitelisted assets only
                        │ NAV = Chainlink/TWAP-priced holdings
    agent bot ──trade()──▶ swaps ONLY via whitelisted route adapters
                        │ per-trade ≤ X% NAV · daily turnover cap · slippage cap
                        ▼
                  [ FeeModule ]
     mgmt 2%/yr streamed · perf 15% over high-water mark · exit 0.25%
                        ▼ auto-swapped to WETH each epoch
        50% → LatticeLock.notifyReward()   (vTHSND lockers get paid)
        30% → BurnEngine → market-buy THSND → burn
        20% → ops treasury (keeps the agent's lights on)
```

**AgentVault.sol** — ERC-4626, asset = USDC. Deposits/withdrawals permissionless; **withdrawals can never be paused** (circuit breaker halts *trading* only). Share price = NAV / supply.

**Executor role** (the agent's hot wallet) can call exactly one function: `trade(adapter, tokenIn, tokenOut, amountIn, minOut)` where the adapter and both tokens must be whitelisted and caps enforced on-chain. It **cannot transfer assets out, cannot touch the whitelist, cannot mint shares.** Compromise of the agent key = worst case bad trades within caps, never theft.

**Guardian** (treasury Safe) sets whitelists/caps, rotates the executor, pulls the trading circuit breaker. It **cannot withdraw depositor funds** — same design promise as LatticeLock, disclosed the same way on the DOCS page.

**The agent (off-chain brain):** a strategy loop (LLM-assisted or plain quant momentum/mean-reversion to start) signing `trade()` calls through a keeper. Every trade lands as a public swap event from the vault address. The site gets an **AGENT page**: live holdings, NAV/share chart, full trade tape from events, P&L vs USDC-hold, and the agent posting its reasoning to Farcaster/X per trade — that feed IS the marketing (this is the Bankr/Virtuals lesson: the character compounds attention).

## Revenue math (the "stable + scalable" part)

At 2% management + 0.25% exit + 15% performance-over-HWM:

| Vault AUM | Floor revenue/yr (mgmt only) | With modest activity |
|---|---|---|
| $100k | $2,000 | ~$4–6k |
| $1M | $20,000 | ~$40–60k |
| $10M | $200,000 | ~$400k+ |

The floor is AUM-linked — it accrues in flat and down markets, which is precisely what "stable" means here. Performance fees are the upside kicker, never the base case, and we never market projected returns (brand rule).

## Trust design — non-negotiables

1. Withdrawals永remain permissionless; circuit breaker ≠ exit gate.
2. Public paper-trading period BEFORE real deposits: the agent trades a $0 shadow book publicly for 4–8 weeks; the feed builds the audience and the track record honestly.
3. **Audit before deposits. Hard line.** A fee-share vault holding only your own token at $2 TVL can launch scrappy; a pooled USDC vault holding other people's money cannot. The revenue case above is the audit's funding justification (or: Base grant → audit).
4. Caps at launch: e.g. $25k vault cap, $2k per-wallet, raised only with track record.
5. DOCS page gets a MILLI section with the same can/can-never table before the first deposit.

## The legal paragraph (read it twice)

Pooled funds + a manager + expectation of profit from others' efforts is the textbook shape of an investment contract (Howey), no matter how on-chain and transparent it is. Non-custodial design, full disclosure, deposit caps, and never marketing returns all *reduce* the risk; none of them *eliminate* it. Before Phase 4 (real deposits at scale), spend the few hundred dollars on an actual crypto-savvy legal consult with this spec in hand. This section is context, not legal advice.

## Phased plan and costs

| Phase | What | Cost | Time |
|---|---|---|---|
| P0 | This spec + strategy definition + fee params | done / $0 | now |
| P1 | Contracts (AgentVault, adapters, FeeModule) + Foundry fork tests | $0 (I write them) | days |
| P2 | Agent bot + **public shadow-trading feed** + AGENT page on thsnd.xyz | $0 | 1–2 wks |
| P3 | Audit of vault suite (Sherlock/Code4rena contest or firm) | $15–40k (grant target) | 2–6 wks |
| P4 | Capped mainnet launch ($25k cap) → scale with track record | gas only | after P3 |

**Sequencing note:** P1+P2 are free and start the flywheel (attention, track record) with zero deposit risk. The shadow-trading period is the product demo, the marketing channel, and the trust builder simultaneously — start it long before the audit lands.

## Open decisions for Will

1. Strategy v1: simple public momentum/rebalance rules (auditable, boring, defensible) vs. LLM-discretionary (more character, less predictable)? Recommend: rules v1, LLM commentary layer for personality.
2. Fee split of the 100%: proposed 50/30/20 (lockers/burn/ops) — tune.
3. mTHSND locking: not needed for exposure (shares appreciate), but locked mTHSND could count 2× toward execution tiers like THSND does — nice cross-sell, adds scope. Defer to v2?
4. Agent name/character: MILLI (one-thousandth) fits the brand grid. Sign-off?

## LP extension (v2 — written 2026-07-03, UNDEPLOYED, in audit scope)

Two new contracts let the vault hold Aerodrome volatile WETH/USDC LP as a listed asset,
entered/exited through the normal `trade()` path:

- `FairLpOracle.sol` — IPriceFeed-compatible LP pricing via the fair-reserves method
  (2·√(p0·p1·r0·r1)/supply, Chainlink prices only). Flash-skewing pool reserves cannot
  move the answer (constant-k invariance); volatile pools only; surfaces the OLDER of the
  two feed timestamps so the vault's maxFeedAge covers both legs.
- `AeroLpAdapter.sol` — IRouteAdapter zap: USDC→(half swap)→addLiquidity→LP to vault,
  and the reverse. Stateless, holds nothing between calls. Router-leg mins are 0 BY
  DESIGN — the vault's minOut + oracle-value floor + per-trade cap bound sandwich loss;
  do not reuse outside the vault.

Tests: `test/AeroLpAdapter.t.sol` (11 cases: fair-price math, skew resistance, zap
round-trips, vault integration through trade() caps). Pre-deploy requirements: published
audit of both files + a Base-mainnet fork test against the real router/pool.
