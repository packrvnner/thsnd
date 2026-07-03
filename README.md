# [ M U Y ]

**MUY Network — autonomous liquidity matrices.**
MUY Labs · $MUY · Base (ERC-20)

**Live on Base mainnet** (source verified via Sourcify, tests public, 16/16 passing):

| Contract | Address |
|---|---|
| MUY | [`0xC665637C9d25efaccee5F1beEe5520Ec707a9ce1`](https://basescan.org/address/0xC665637C9d25efaccee5F1beEe5520Ec707a9ce1) |
| LatticeLock | [`0xfAd6Cdfffde50352E579E0b6B05f4CB4d68dE0A4`](https://basescan.org/address/0xfAd6Cdfffde50352E579E0b6B05f4CB4d68dE0A4) |
| BurnEngine | [`0x89B63D4FF4780d832C9539B02486bBFfb9D41985`](https://basescan.org/address/0x89B63D4FF4780d832C9539B02486bBFfb9D41985) |
| TierRegistry | [`0xd238c287d736088E303679b2a55bcD18a214f3C8`](https://basescan.org/address/0xd238c287d736088E303679b2a55bcD18a214f3C8) |

> **Status: pre-launch.** Contracts are deployed and source-verified but **not yet externally audited**. Do not deposit funds you cannot afford to lose. This repository is not an offer or solicitation of any kind.

## Repo map

```
docs/ARCHITECTURE.md    Chain decision (Base vs Solana), 3-pillar system design,
                        tokenomics mapping, roadmap→engineering, compliance notes
docs/DEPLOYMENT.md      Step-by-step code → Base mainnet guide
docs/FRONTEND_SPEC.md   Terminal UI spec (tokens, pages, rules)

ios/Thousand/           Native iOS app (SwiftUI + WalletConnect) — see ios/README.md
docs/APPSTORE/          App Store submission kit: runbook, metadata, review notes

contracts/src/MUY.sol           Token: fixed 1B genesis, burn-only, EIP-2612
contracts/src/LatticeLock.sol   vMUY staking + protocol fee share
contracts/src/BurnEngine.sol    Liquidation-slice buyback & burn
contracts/src/TierRegistry.sol  Execution-tier system ("slippage insurance matrix")
contracts/script/Deploy.s.sol   Foundry deploy script
contracts/test/MUY.t.sol        Unit + fuzz tests
```

## Decision summary

**Base over Solana** — the product suite (CL-AMM, lending, cross-chain router) and every token mechanic map onto audited EVM prior art; Foundry/Certora make the "verified" positioning actually achievable; the institutional-surface/degen-core brand is native to Base's 2026 meta. Full reasoning in `docs/ARCHITECTURE.md §1`.

## Quick start

```bash
cd contracts
forge install foundry-rs/forge-std
forge build && forge test -vvv
```

## Non-negotiables before launch

Two external audits · published verification reports before the word "verified" ships · team vesting onchain · treasury = multisig · legal review of token distribution and fee-share staking (see `ARCHITECTURE.md §5`).
