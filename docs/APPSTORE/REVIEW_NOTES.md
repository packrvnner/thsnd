# App Review Notes — paste verbatim into App Review Information

---

Thousand is a native, non-custodial interface for the THSND protocol, a set of verified smart contracts on Base (an Ethereum layer-2 operated by Coinbase's ecosystem). This note explains how to review every feature without any crypto setup.

WHAT THE APP IS
- Read-only by default: it displays public blockchain data (token supply, burn history, staking positions, fee tiers) fetched from public RPC endpoints and the Blockscout block explorer API.
- Optional wallet connection via the WalletConnect open protocol. The app NEVER holds, stores, or transmits private keys or funds, and has no accounts, no purchases, and no in-app payments of any kind. Transactions are prepared locally and signed inside the user's own separate wallet app; nothing is exchanged for fiat within our app.

HOW TO REVIEW WITHOUT A WALLET (no demo account needed)
1. Open the app — Markets, Burn, and Company tabs are fully live immediately.
2. Company tab → "Or watch any address" → paste this public address (an active protocol participant): 0x9324605c9c707b2f805ccf2ac099fca5d561dc37 → WATCH. The Vault tab now shows a real live position (locked amount, vTHSND, unlock date, claimable fees) exactly as a user sees their own.
3. To see the top fee tier, watch the protocol treasury instead: 0x539DE6F65dECEB2F491237e3DC030494E517877C → Tiers tab shows T1000.
4. All write actions remain disabled in watch mode and are labeled as such.

GUIDELINE 3.1.5(b)
We are enrolled as an organization. The app facilitates DeFi staking ("locking") and claiming on the user's own wallet via WalletConnect; it is not an exchange, does not custody assets, and does not offer fiat on/off-ramps.

TRANSPARENCY
- All transaction functionality is compiled in and visible; nothing is remotely toggled (guideline 2.3.1).
- The Company tab contains plain-language risk disclosures, including that the protocol is pre-launch and not yet externally audited. The app and store listing make no earnings claims.
- Contract source code is publicly verified; every address in the app deep-links to the public block explorer.

CONTACT
Will Martin — willm82207@gmail.com — responds within 24h.

---

## Internal pre-submit checklist (do not paste)

- [ ] Org enrollment ACTIVE before first submission (individual account = guaranteed 3.1.5(b) rejection)
- [ ] `Config.reownProjectID` set; wallet connect round-trip tested on a real device with Coinbase Wallet AND one WC-relay wallet (Rainbow/Zerion)
- [ ] privacy.html live at thsnd.xyz/privacy.html (200, not a redirect)
- [ ] Treasury Safe address in the notes still correct
- [ ] Screenshots match the shipping build pixel-for-pixel (4.0 rejection bait otherwise)
- [ ] Description contains zero profit/APY language (re-read before every resubmission)
