# Getting the THSND logo onto the token (wallets, explorers, DEXes)

Token logos live in off-chain registries, not the contract. Three submissions, in impact order:

## 1. Basescan (biggest single win — explorer + many wallets scrape it)
- basescan.org → create account → go to the [THSND token page](https://basescan.org/token/0xF7aa829ed31fE30834E56348e9CD3fBb4687CFdb) → "Update Token Info"
- Ownership check: Basescan asks for a signed message from the contract deployer/owner address. The deployer was the session throwaway key — **if the form demands the deployer signature, ask Claude to produce it while the session key still exists**; otherwise verify via the Safe (owner path).
- Upload `THSND/logo.png`, paste description/website from `data.json`.

## 2. Superchain token list (Coinbase Wallet, Base ecosystem UIs, Aerodrome)
- Repo: github.com/ethereum-optimism/ethereum-optimism.github.io
- Fork → add folder `data/THSND/` with the `logo.png` and `data.json` from this directory (their schema matches) → open PR
- Free; review takes days. This is what makes the logo appear inside Aerodrome's UI.

## 3. Post-pool: DexScreener + GeckoTerminal
- After liquidity exists, claim the pair page (DexScreener "claim" is paid, ~$300 — optional) or link socials via their free forms; CoinGecko listing (free, slow) feeds GeckoTerminal.

Until #1 or #2 lands, wallets show a generic circle — normal for every new token.
