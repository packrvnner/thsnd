# Liquidity Seed Pack — MUY/WETH on Aerodrome (via your Safe)

This is the transaction that makes MUY buyable and sellable — the real version of "launching on a platform." **Recommended timing: after audit reports publish** (see GROWTH.md); the mechanics are identical whenever you run it.

## Why not pump.fun / Bankr / launchpads — read once

- **pump.fun is Solana.** Your token lives on Base. Launching there mints a brand-new, unrelated SPL token that merely shares the name. Your actual contract cannot exist there.
- **Bankr / Clanker deploy their own contracts.** Same issue on Base: you'd get a second MUY address competing with the real one. Two contracts, one ticker = the exact pattern scam-scanners and communities treat as a rug signal — it would damage the real token permanently.
- **Launchpads are for tokens that don't exist yet.** Yours exists, is verified, and has infrastructure. The equivalent "launch moment" for a deployed token IS the pool seeding below + the DexScreener page it auto-creates.

## What you decide first

1. **How much to seed.** Both sides come from the Safe: X MUY + Y WETH. The starting price = Y/X. Example: 50,000,000 MUY + 5 WETH ≈ $18k depth at $1,800/ETH, implying ~$0.00036/MUY and ~$360k FDV. Thin pools (<$10k) chart badly and get flagged as dust — decide what you're comfortable committing.
2. **Fee tier / pool type.** On Aerodrome: volatile (vAMM) pool for a new token. Concentrated (Slipstream) later, once price discovery settles.

## Execution (all from app.safe.global, ~20 min)

1. Safe → **Apps → WalletConnect** → connect to aerodrome.finance
2. Aerodrome → **Liquidity → Create Pool** (if MUY/WETH doesn't exist) → select:
   - Token A: paste `0xC665637C9d25efaccee5F1beEe5520Ec707a9ce1` (verify symbol shows MUY)
   - Token B: WETH `0x4200000000000000000000000000000000000006`
   - Type: Volatile
3. Enter amounts (step 1 numbers) → Approve MUY (Safe tx 1) → Approve WETH (Safe tx 2) → Add Liquidity (Safe tx 3)
4. The LP position lands in the Safe. **Leave it there and say so publicly**, or lock it via a locker for a stronger signal.
5. Within ~30 min: DexScreener + GeckoTerminal auto-index the pool → your site's MARKET page goes live automatically (price, chart, buy/sell) → claim the DexScreener page, add logo/socials.
6. Post the Stage 2 announcement from LAUNCH_KIT.md — every line in it becomes true at that moment.

## Same-day checklist after seeding

- [ ] Claim DexScreener + GeckoTerminal listings
- [ ] Submit CoinGecko + CMC applications (SETUP_CHECKLIST.md §8)
- [ ] First `notifyReward` fee push + ceremonial burn (on-chain proof the machine works)
- [ ] Watch for imposter pools/contracts using the ticker and report them — they will appear if the launch works
