# Base MAINNET Deployment — July 2, 2026

Network: Base (chain 8453) · Deployer: throwaway `0x56AD0fe454694F7dF4c4B3E32c8A59133f567fA8` (discarded, ~0.0089 ETH dust remains)
**Treasury + owner of all contracts: Safe `0x539DE6F65dECEB2F491237e3DC030494E517877C`**
Safe signer: `0x9324605c9C707b2F805CCF2AC099fCA5d561DC37` (currently **1-of-1 — add owners + raise threshold before launch**)

| Contract | Address | Basescan |
|---|---|---|
| MUY (token) | `0xC665637C9d25efaccee5F1beEe5520Ec707a9ce1` | https://basescan.org/address/0xC665637C9d25efaccee5F1beEe5520Ec707a9ce1 |
| LatticeLock (vMUY) | `0xfAd6Cdfffde50352E579E0b6B05f4CB4d68dE0A4` | https://basescan.org/address/0xfAd6Cdfffde50352E579E0b6B05f4CB4d68dE0A4 |
| BurnEngine | `0x89B63D4FF4780d832C9539B02486bBFfb9D41985` | https://basescan.org/address/0x89B63D4FF4780d832C9539B02486bBFfb9D41985 |
| TierRegistry | `0xd238c287d736088E303679b2a55bcD18a214f3C8` | https://basescan.org/address/0xd238c287d736088E303679b2a55bcD18a214f3C8 |

Reward token: WETH `0x4200000000000000000000000000000000000006` · Source verified via Sourcify (all four)

State confirmed on-chain: totalSupply = 1,000,000,000 MUY, 100% in the Safe; owner() of all three ownable contracts = the Safe.

## Status: DEPLOYED — NOT LAUNCHED

Contracts are live but unaudited. Hard rules until audits complete:
- ❌ No liquidity seeding, no marketing, no invitations to stake or deposit
- ❌ No "verified"/"audited" claims anywhere
- ✅ OK: hold tokens in Safe, set up vesting contracts, hand this exact deployment to audit firms

## Pre-launch checklist (in order)
1. Safe: add ≥1 more owner, threshold ≥2 (Safe app → Settings → Owners)
2. Two external audits of this deployed code
3. Legal review (fee-share staking = securities risk; see ARCHITECTURE.md §5)
4. Team vesting via MuyVesting.sol, addresses published
5. Then: seed MUY/WETH on Aerodrome from the Safe, set BurnEngine routes/keeper, launch

All owner actions now go through the Safe UI (app.safe.global → New transaction → Contract interaction).
