# THOUSAND — Brand Identity System

**v1.0 · July 2026 · supersedes MUY brand**

---

## 1. The idea

One second contains one thousand milliseconds. Every trade you've ever lost to slippage or latency was lost inside one of them.

**Thousand** is the venue for people who count all one thousand. The name isn't decoration — it's the product spec: sub-second execution, measured and displayed in milliseconds, everywhere, always. Where OKX's grid abstracts "exchange," Thousand's mark literally *is* the number.

**Positioning line:** `One second. A thousand chances.`
**Technical line:** `Execution measured in thousandths.`

Copy rule (important): we sell **speed, precision, and tools** — never profit. "Institutional-grade execution," yes; "extreme profit," never. Profit promises are the fastest way to regulator attention and user distrust; speed claims we can prove with a latency readout. The audience hears the difference and respects the restraint — that's what "institutional" actually signals.

## 2. The mark

```
▮ □ □ □
```

The numeral **1000**, reduced to geometry: one solid bar, three hollow squares. Crisp edges, no radius, pure white on jet black. It reads as the number at billboard size and stays legible at 16px favicon size (bar + single square: `▮□`).

- Solid bar = the trade. The one.
- Three hollow squares = the milliseconds not yet spent. The zeros.
- Never rotated, never colored, never gradiented. Spacing between elements = ½ bar width, locked.

Wordmark: `THOUSAND` in tight uppercase, set right of the mark or below it. Ticker rendering: `$THSND`.

## 3. Palette — pure monochrome

| Role | Hex |
|---|---|
| Jet Black (bg) | `#000000` |
| Pure White (text, mark) | `#FFFFFF` |
| Grey 60 (secondary text) | `#8A8F98` |
| Grey 15 (hairlines, borders) | `#1F1F1F` |
| Grey 8 (raised surfaces) | `#141414` |

No accent color. Direction (up/down) is shown with `▲ ▼` glyphs and weight, not color. This is the single most OKX-like decision in the system: when everything is monochrome, the numbers become the color.

## 4. Typography

- **Display / wordmark / headings:** Inter (or Neue Haas Grotesk) — tight tracking, weights 600–700, uppercase for nav and labels.
- **All numbers, addresses, data:** JetBrains Mono. Tabular. Milliseconds always rendered as `NNNms`.
- Type scale is sparse: 11px labels / 14px body / 22px section / one huge number per screen.

## 5. Ecosystem naming (the connected system)

Parent brand prefixes everything, OKX-style; in-product the names collapse to one word:

| Layer | Full name | In-product | Replaces |
|---|---|---|---|
| Token | Thousand Token | `$THSND` | $MUY |
| DEX / AMM | Thousand Swap | `/swap` | MUY Lattice |
| Staking + fee share | Thousand Vault | `/vault` | Lattice Lock |
| Lending | Thousand Credit | `/credit` | MUY Strata |
| Cross-chain router | Thousand Bridge | `/bridge` | MUY Vector |
| Burn mechanic | Thousand Burn | `/burn` | Burn Engine |
| Governance weight | `vTHSND` | — | vMUY |
| Fee tiers | Execution Tiers: `T1 / T10 / T100 / T1000` | — | Matrix/Concentrate/Singularity |

Tier names are the brand doing math: T1000 is the top tier — all thousand milliseconds, zero protocol fee. "What tier are you?" answers itself.

## 6. Voice

- Declarative sentences. Present tense. No exclamation points, ever.
- Numbers over adjectives: "9ms median route" beats "blazing fast."
- The status-line humor survives the rebrand but goes drier:
  - `SYS: 1000ms per second. all of them in use.`
  - `SYS: your last trade took 214ms. we counted.`
  - `SYS: t1000 tier detected. fees declined to exist.`
- Never: rocket emojis, "WAGMI," profit talk, countdowns.

## 7. On-chain reality (until redeploy)

Deployed contracts still carry name "MUY Network"/symbol "MUY". Brand-only phase rules: site and materials say **Thousand / $THSND**, with one visible footnote — `on-chain symbol currently MUY · migrates at THSND deployment`. No new social handles get created under the MUY name; everything registers as Thousand (thousand.exchange, @thousandfi, etc. — check availability before attachment). When ready, the redeploy under the new name follows the same script as before (same Safe treasury, minutes of work).

## 8. Asset inventory

`website/assets/` — `thsnd-mark-{512,256,32}.png`, `thsnd-wordmark.png`, `thsnd-og.png`. All monochrome, all regenerable from `scripts` in repo.
