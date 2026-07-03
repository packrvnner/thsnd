# MUY — Code → Mainnet Deployment Guide (Base)

Assumes macOS/Linux, the `/contracts` folder in this repo, and a hardware wallet or fresh deployer key.

---

## 0. Prerequisites

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
cd contracts
forge install foundry-rs/forge-std          # test/script dependency
forge build && forge test -vvv              # everything must be green before proceeding
```

Accounts and keys — never a raw private key in `.env`:

```bash
cast wallet import deployer --interactive   # encrypted keystore; prompts for pk once
```

Get: a **Basescan API key** (verification), a **Base RPC** (Alchemy/QuickNode or https://mainnet.base.org), and a **Safe multisig** on Base for the treasury (deploy at https://app.safe.global — 2/3 minimum, 3/5 recommended).

`.env` (gitignored):

```bash
BASE_RPC=...
BASE_SEPOLIA_RPC=https://sepolia.base.org
BASESCAN_API_KEY=...
TREASURY=0x...        # the Safe, NOT an EOA
REWARD_TOKEN=0x4200000000000000000000000000000000000006   # WETH on Base + Base Sepolia
```

## 1. Testnet rehearsal (Base Sepolia)

```bash
source .env
# faucet ETH: https://docs.base.org/tools/network-faucets
forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC \
  --account deployer --broadcast --verify
```

Then exercise every path with `cast`: transfer, approve/permit, `lock()`, `notifyReward()`, `claim()`, `withdraw()` after `MIN_LOCK`, fund BurnEngine with a test token + `execute()`, `tierOf()` at each threshold. Keep the testnet deployment live for the audit team.

## 2. Audit gate (Phase 1 exit criteria — do not skip)

1. Freeze `src/` (tag `v1.0.0-audit`).
2. Internal pass: `forge coverage` (target 100% branch on the four contracts), invariant tests (supply only decreases; engine MUY balance only burns; lock principal always withdrawable at expiry), `slither .`, `forge build --sizes`.
3. **Two independent external audits** (e.g. one firm + one competitive audit platform). Budget 3–6 weeks.
4. Optional but on-brand: formal verification of MUY + LatticeLock invariants (Certora/Halmos). **The "formally verified" tagline is unusable until these reports are published.**
5. Public repo + audit reports before any liquidity exists.

## 3. Mainnet deployment (Phase 2)

```bash
# Optional vanity/deterministic address via CREATE2:
# cast create2 --starts-with 0x000000 --init-code-hash $(forge inspect src/MUY.sol:MUY initcode-hash)

forge script script/Deploy.s.sol --rpc-url $BASE_RPC \
  --account deployer --broadcast --verify --slow
```

Immediately after (same session, scripted):

```bash
# 1. Wire roles
cast send $LATTICE_LOCK "setFeeNotifier(address)" $FEE_HOOK        --account deployer --rpc-url $BASE_RPC
cast send $BURN_ENGINE  "setKeeper(address,bool)" $KEEPER true     --account deployer --rpc-url $BASE_RPC

# 2. Hand EVERYTHING to the Safe — deployer EOA retains nothing
cast send $LATTICE_LOCK  "transferOwnership(address)" $TREASURY --account deployer --rpc-url $BASE_RPC
cast send $BURN_ENGINE   "transferOwnership(address)" $TREASURY --account deployer --rpc-url $BASE_RPC
cast send $TIER_REGISTRY "transferOwnership(address)" $TREASURY --account deployer --rpc-url $BASE_RPC
```

Verify on Basescan even in stealth — unverifiable bytecode reads as rug, not mystery.

## 4. Liquidity + launch checklist

- [ ] Team/investor allocations in an onchain vesting contract (publish addresses)
- [ ] Seed MUY/WETH concentrated pool on Aerodrome Slipstream from the Safe; full-range floor + concentrated band
- [ ] LP position ownership → Safe; consider LP lock for the seed position
- [ ] BurnEngine routes set for expected Strata collaterals (`setRoute`)
- [ ] Keeper bot live (watch `Transfer` into engine → compute TWAP minOut → `execute`)
- [ ] Monitoring: Tenderly/Defender alerts on `Burned`, `RewardNotified`, ownership events, Safe txs
- [ ] Incident runbook + pause criteria documented (note: token itself is unpausable by design — that's a feature; document it)
- [ ] Legal sign-off on all public copy (see ARCHITECTURE.md §5)

## 5. Post-launch cadence (Phase 3+)

Weekly `notifyReward` fee pushes (later: automated from Lattice fee hook) · publish burn dashboard reading `totalBurned` · quarterly re-audit of any new module before it can touch existing contracts · Vector (cross-chain) ships only after its own dedicated audit cycle.
