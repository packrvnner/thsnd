# Base Sepolia Deployment — July 2, 2026

Network: Base Sepolia (chain 84532) · Deployer: throwaway `0x23BC13F3D9d73DD57b4eCB0c3e92759Acbd8D68e` (discarded)
**Treasury + owner of all contracts: `0x9324605c9C707b2F805CCF2AC099fCA5d561DC37` (Will)**

| Contract | Address |
|---|---|
| MUY (token) | `0x661971eCA790ae889D2bCD414ff1fCddE85dde2d` |
| LatticeLock (vMUY) | `0x371cD167C2695BA05511e5e49932B0c3756a12a7` |
| BurnEngine | `0xa6f44455CA1a3f46Ab0E88fe4EB936fb3136E90f` |
| TierRegistry | `0xF1E1CdF7Bf56e4a43083E2F6DAef551935a5cd9D` |

Reward token (LatticeLock): WETH `0x4200000000000000000000000000000000000006`

State verified on-chain: totalSupply = 1,000,000,000 MUY, all held by treasury; owner() of LatticeLock/BurnEngine/TierRegistry = treasury. Source verified on Sourcify (all four).

Explorer: https://sepolia.basescan.org/address/0x661971eCA790ae889D2bCD414ff1fCddE85dde2d

## To interact from your wallet
Add Base Sepolia network, then import token `0x661971eCA790ae889D2bCD414ff1fCddE85dde2d` — 1B MUY will appear.

## Not yet configured (owner-only, from your address)
- `LatticeLock.setFeeNotifier(address)` — who may push fee revenue
- `BurnEngine.setKeeper(address,bool)` and `setRoute(asset,router)` — burn path
- These matter for full end-to-end testing; not needed to hold/transfer/lock tokens.
