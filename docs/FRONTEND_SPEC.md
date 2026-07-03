# MUY — Frontend Specification

**Aesthetic thesis:** a Bloomberg terminal that costs $40k/yr and knows it. Static, monospace, silent. The joke is that there is no joke on the surface.

## Design tokens

```css
:root {
  --bg:        #0A0B0D;   /* Obsidian Black */
  --text:      #F9FBFD;   /* Pure Titanium */
  --accent:    #00FF66;   /* Acid Matrix Green — sparingly: live numbers, active states, burn counter */
  --text-dim:  #5A5F66;   /* derived: labels, secondary */
  --border:    #1A1C1F;   /* derived: 1px hairlines only */
  --danger:    #FF3355;   /* liquidations only */

  --font-head: "PP Neue Montreal", "Neue Haas Grotesk", "Inter", sans-serif;
  --font-mono: "JetBrains Mono", monospace;
}
```

Rules: no gradients, no shadows, no border-radius > 2px, no animation except number ticks (200ms steps) and a 1px accent underline on hover. Data is always mono; headings always sans. Accent covers <5% of any viewport.

## Header

```
[ M U Y ]                    LATTICE   STRATA   VECTOR   LOCK        ⬡ 0x4f…a2C1
```

Left: the mark, exactly `[ M U Y ]` in mono, letter-spaced. Right: text-only nav + wallet chip. 56px tall, hairline bottom border. Nothing else.

## Pages

**/ (Terminal)** — full-width stat grid, mono, right-aligned numbers: TVL · 24H VOLUME · TOTAL BURNED (accent, ticks up live from `Burned` events) · vMUY LOCKED · CURRENT EPOCH FEES. Below: sparse table of Lattice pools. No hero copy beyond the tagline in `--text-dim`.

**/lattice** — swap panel: two inputs, a rate line, and an execution readout: `TIER 2 · CONCENTRATE — protocol fee -50%` (reads `TierRegistry.discountOf`). Tier is displayed as a fact, never a promo.

**/strata** — markets table: collateral / debt / LTV / liq. threshold. Liquidation feed at the bottom in `--danger`, each row ending with `→ 1.5% ROUTED TO BURN`.

**/lock** — one input (amount), one slider (1W → 4Y, snap points), computed line: `vMUY = amount × t/4y`. Claimable fees in WETH with a single CLAIM action. Position table below.

**/burn** — the shrine. One huge mono number: cumulative `totalBurned`, accent, live. Under it a plain event log: `block · asset in · MUY burned · tx`. This page IS the marketing.

## Phase 3 "volatility humor" (footer status line only)

A single dim status line, rotating, terminal-style — the UI never jokes above the fold:

```
SYS: volatility detected. matrices unaffected.
SYS: price is a social construct. burns are not.
SYS: muy operational. muy up only remains a hypothesis.
```

Keep it out of any screen that renders numbers a user acts on, and never let humor make a performance claim.

## Stack

Next.js (static export where possible) · wagmi/viem · event indexing via a lightweight subgraph or viem log watcher for the burn counter · no client-side telemetry beyond RPC. Ship the whole dashboard read-only first (Phase 1 "facade" = a real, live, read-only terminal on testnet data — impressive AND true).
