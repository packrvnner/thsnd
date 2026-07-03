# MUY Network — Chain Decision & System Architecture

**MUY Labs · Internal · v0.1 · July 2026**

---

## 1. Chain Recommendation: BASE (ERC-20, Foundry)

**Definitive call: deploy on Base.** Solana is the better chain for a pure meme velocity play. MUY is not that — it's a three-pillar DeFi protocol wearing a meme layer. That changes the math.

### Why Base wins for this specific project

**1. The product suite maps onto audited EVM prior art.**
- MUY Lattice (concentrated liquidity AMM) → fork/extend Uniswap v4 hooks or Aerodrome Slipstream. Battle-tested concentrated-liquidity math already exists in Solidity. On Solana you rebuild CLMM math from scratch in Anchor (Orca Whirlpools is the only serious reference, and it's not designed to be forked with custom fee-share hooks).
- MUY Strata (lending) → Aave v3 / Morpho Blue patterns. The 1.5% liquidation-slice → BurnEngine is a ~30-line hook on an EVM liquidation path. On Solana it's a custom CPI flow through token accounts with far more surface area.
- MUY Vector (cross-chain routing) → LayerZero / Chainlink CCIP have first-class EVM support; Base is a hub chain for both.
- Lattice Lock (vMUY) → ve-token + Synthetix-style fee distributor is the single most audited staking pattern in existence.

**2. The brand IS the Base meta.** The dual-identity hook ("clean mathematical variable" to institutions, ironic premium meme to degens) is exactly Base's cultural position in 2026: Coinbase distribution and institutional adjacency on top, Clanker/Zora meme culture underneath. Aerodrome now ranks among the highest-volume DEXs in all of crypto, and Flashblocks give ~200ms confirmations — "institutional facade, degen engine" is native to this chain.

**3. Tooling and verification.** Foundry gives fuzz/invariant testing and one-command Basescan verification. The "formally verified" positioning is only achievable in practice on EVM (Certora, Halmos, SMTChecker). Solana has no comparable formal-verification toolchain.

**4. Liquidity path.** Seed MUY/WETH on Aerodrome → bribe/vote flywheel for emissions → graduate to your own Lattice pools. Solana's equivalent (Raydium LaunchLab) optimizes for 48-hour meme cycles, not protocol TVL retention.

**Where Solana would win:** raw retail launch velocity, lower absolute fees, pump.fun-style virality. If the plan were *only* Phase 2–3 (meme launch + volume), Solana. Because Phases 1 and 4 (real protocol + institutional rails) are load-bearing, Base.

Sources: [DefiLlama — Solana](https://defillama.com/chain/solana), [Yellow — ETH vs SOL DeFi liquidity 2026](https://yellow.com/learn/ethereum-vs-solana-defi-liquidity-2026), [CoinGecko — Base native projects](https://www.coingecko.com/learn/ethereum-layer2-base-top-crypto-projects), [Xangle — Clanker & Base growth](https://xangle.io/en/research/detail/2144), [Base docs — Launch a Token](https://docs.base.org/get-started/launch-token)

---

## 2. System Architecture — The Three Pillars

Deployment sequence is strictly ordered: token layer first, then each pillar activates a tokenomic mechanic.

```
                    ┌─────────────────────────────┐
                    │   $MUY (ERC-20, fixed cap)   │
                    └──────┬───────────┬──────────┘
                           │           │
              ┌────────────▼──┐   ┌────▼────────────┐
              │  LatticeLock  │   │  TierRegistry    │
              │  (vMUY + fee  │   │  (slippage       │
              │   share)      │   │   insurance)     │
              └──────▲────────┘   └────▲────────────┘
                     │ fees            │ reads balance/lock
   ┌─────────────────┴─────┐          │
   │ Pillar 1: MUY LATTICE │──────────┘
   │ CL-AMM (Uni v4 hooks) │
   └─────────▲─────────────┘
             │ market-buy route
   ┌─────────┴─────────────┐   ┌──────────────────────┐
   │     BurnEngine        │◄──│ Pillar 2: MUY STRATA │
   │  (buyback + burn)     │1.5%│ Lending (Morpho-    │
   └───────────────────────┘   │ style, liq. hook)    │
                               └──────────────────────┘
   ┌───────────────────────────────────────────────────┐
   │ Pillar 3: MUY VECTOR — cross-chain yield router   │
   │ (LayerZero OApp; routes via Lattice pools)        │
   └───────────────────────────────────────────────────┘
```

### Pillar 1 — MUY Lattice (CL-AMM)
- Uniswap v4-style singleton + hooks architecture. Custom hook: `MuyFeeHook` splits swap fees → X% to LPs, Y% to LatticeLock fee distributor, Z% to treasury.
- Tier-aware routing: frontend router quotes check `TierRegistry.tierOf(user)` and apply reduced protocol fee for higher tiers.
- Near-zero slippage claim = concentrated ticks + JIT liquidity vaults, not magic. Market that honestly.

### Pillar 2 — MUY Strata (lending)
- Morpho Blue-style isolated markets (oracle-agnostic, immutable market params) — safest way to "cross-collateralize yield-bearing assets" without one bad oracle nuking the protocol.
- Liquidation hook: on each liquidation, 1.5% of seized collateral transfers to `BurnEngine`, which market-buys MUY via a whitelisted Lattice route and burns it.

### Pillar 3 — MUY Vector (cross-chain yield router)
- LayerZero v2 OApp. One click = deposit → bridge → deploy into whitelisted destination vaults. Strict vault allowlist governed by vMUY.
- Ship last. Cross-chain messaging is the highest-severity exploit class in DeFi; this pillar gets its own audit cycle.

---

## 3. Tokenomics Implementation (contracts in `/contracts`)

| Mechanic | Contract | Pattern |
|---|---|---|
| Fixed 1B supply, burn-only | `MUY.sol` | ERC-20 + EIP-2612 permit, no mint after genesis, `totalBurned` tracker |
| Lattice Lock (vMUY + fee share) | `LatticeLock.sol` | Time-lock 1wk–4yr, linear voting weight, Synthetix-style reward accumulator paying WETH/USDC fees |
| Slippage Insurance Matrix | `TierRegistry.sol` | View-layer tiers from spot balance + locked balance (lock counts 2×); frontend + Lattice hook read it |
| Burn Engine | `BurnEngine.sol` | Receives liquidation slices, keeper-executed buyback via whitelisted route with `minOut`, burns and emits `Burned` |

Suggested allocation (adjust with counsel): 40% community/LP incentives · 20% treasury (vMUY-governed) · 15% team (12mo cliff + 24mo linear vest, onchain) · 15% liquidity seed · 10% ecosystem/partners. **No allocation without an onchain vesting contract — the "premium" positioning dies the first time a team wallet moves early.**

---

## 4. Roadmap → Engineering Mapping

- **Phase 1 (Incubation):** contracts frozen, 100% branch coverage, fuzz + invariant suites, external audit ×2, Certora/Halmos rules for MUY + LatticeLock. *Only after this may the word "verified" appear in any material — see §5.*
- **Phase 2 (Concentration):** deploy token + LatticeLock + TierRegistry via CREATE2 (vanity address, e.g. leading `0x...muy`). Easter eggs belong in contract comments/event names, never in logic. Verify on Basescan immediately — stealth means unannounced, not unverifiable.
- **Phase 3 (Saturation):** Lattice + Strata mainnet, BurnEngine live, volume dashboards public. UI volatility humor is a frontend concern only.
- **Phase 4 (Expansion):** Vector cross-chain, CCIP/institutional rails, CEX market-maker integrations.

---

## 5. Compliance Notes (read before any public material ships)

Not legal advice — retain crypto-specialized counsel before launch. Three hard lines from the engineering side:

1. **"Formally verified" is a falsifiable technical claim.** Publishing it before verification reports exist exposes MUY Labs to fraud/misrepresentation liability. Same for "insurance" — regulated term in most jurisdictions; consider "execution tiers" in legal copy.
2. **Ironic branding ≠ misleading marketing.** The dual-identity hook works when the joke is legible to everyone (cf. successful ironic-premium tokens). Materials designed so institutional buyers *actually believe* something the team knows is false crosses from irony into misrepresentation. Keep one set of true facts; vary tone, not substance.
3. **Stealth launch hygiene:** unannounced timing is fine; team/insider wallets buying pre-announcement with material non-public launch info is not. Publish team wallet addresses and lock them pre-launch.

Token launches may constitute securities offerings depending on jurisdiction and facts (fee-share staking in particular is a Howey magnet — vMUY fee distribution needs specific legal review).
