# App Store Metadata — Thousand

Copy-paste pack for App Store Connect. Voice per BRAND_THOUSAND.md: declarative, numbers over adjectives, no exclamation points, never profit talk.

## Identity

| Field | Value |
|---|---|
| App name (30 chars max) | `Thousand — THSND on Base` (24) |
| Fallbacks if taken | `Thousand: THSND Terminal` · `THSND — Thousand` |
| Subtitle (30 chars max) | `Vault, burns, tiers. Live.` (26) |
| Bundle ID | `xyz.thsnd.thousand` |
| SKU | `THSND-IOS-1` |
| Primary category | Finance |
| Age rating | Complete questionnaire honestly — lands 4+ (no embedded browser, no gambling, no UGC) |
| Price | Free |
| Support URL | `https://thsnd.xyz` |
| Marketing URL | `https://thsnd.xyz` |
| Privacy policy URL | `https://thsnd.xyz/privacy.html` |

## Promotional text (170 chars max, editable without review)

> Live protocol data straight from Base: supply, burns, locks, tiers. Connect a wallet or just watch an address. One second. A thousand chances.

## Description (4000 chars max)

```
One second contains one thousand milliseconds. Thousand is the venue for people who count all of them.

The Thousand app is a native terminal for the THSND protocol on Base. It reads directly from public blockchain infrastructure and reports numbers — nothing else.

MARKETS
Live THSND price from the Aerodrome pool, fully-diluted value, pool depth, current supply, and the countdown to the next weekly fee epoch. Every figure is read on-chain. The refresh is measured and displayed in milliseconds, because that is the product.

VAULT
Lock THSND for 1 week to 4 years and receive vTHSND — voting power fixed at lock time, calculated exactly as the contract does: amount × duration ÷ 4 years. Protocol fees stream to lockers in WETH, pro-rata by vTHSND. Claim any time. Withdraw principal at expiry. Locks are non-custodial by construction: no admin path can touch principal, and the app shows you the verified contract that proves it.

BURN
THSND launched with a fixed 1,000,000,000 genesis supply and no mint function. Supply only goes down. The Burn tab charts every burn event since deployment and shows the burn engine's pending balance. Anyone may trigger the engine — the button is in the app.

TIERS
Execution tiers T1, T10, T100, T1000, read live from the tier registry. Effective balance counts actively locked THSND at 2×. T1000 holds all one thousand milliseconds: protocol fee zero.

COMPANY
The Milli agent-vault feed, every contract address with a one-tap link to the block explorer, and plain-language disclosures.

YOUR KEYS STAY YOURS
The app never holds funds, never stores keys, and never asks you to create an account. Transactions are composed locally and signed in your own wallet via WalletConnect. Prefer to look before you touch? Watch any address in read-only mode — no wallet required.

THE NUMBERS ARE THE COLOR
Pure monochrome interface. Direction is shown with glyphs and weight. All data renders in tabular monospace. 11px labels, one huge number per screen.

Thousand is pre-launch software. Contracts are deployed and source-verified on Base but not yet externally audited. Digital assets are volatile and can lose all value. Thousand sells speed, precision, and tools — it does not promise returns, and neither does this app.

SYS: 1000ms per second. all of them in use.
```

(~2,050 chars — room to add the audit link when it lands.)

## Keywords (100 chars max, comma-separated, no spaces)

```
base,defi,thsnd,vault,staking,burn,walletconnect,ethereum,crypto,onchain,aerodrome,token
```
(96 chars. Don't waste characters on "thousand" — the app name already matches it.)

## What's New (v1.0.0)

> Initial release. Markets, Vault, Burn, Tiers, Company — all live from Base mainnet.

## App Privacy questionnaire

| Question | Answer | Why |
|---|---|---|
| Do you collect data from this app? | **No** | No accounts, no analytics SDK, no crash reporting SDK, no server of ours receives anything. |

Notes if a reviewer asks: wallet/watched addresses persist on-device only (UserDefaults). Read queries go to public Base RPC endpoints, Blockscout, and thsnd.xyz (static feed) — standard web requests, no developer-controlled collection. WalletConnect relays end-to-end-encrypted session traffic through Reown infrastructure; Reown's privacy manifest ships inside their SDK.

## Screenshots

See `SCREENSHOTS.md`. Required sets: 6.9" (iPhone 16 Pro Max class) and 6.5". Monochrome UI on black — export device frames off, background pure black, one caption line per shot in the brand voice.
