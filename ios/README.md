# Thousand iOS

Native SwiftUI client for the Thousand protocol on Base. Everything the site does: live price/FDV from the Aerodrome pool, supply + burn tracking, the vTHSND Vault (lock / top-up / claim / withdraw), Execution Tiers, the permissionless burn trigger, and the Milli agent-vault feed. Transactions sign in the user's own wallet via WalletConnect — the app never touches keys or funds.

## Requirements

- Xcode 16 or newer (the project uses filesystem-synchronized groups)
- iOS 16.0+ deployment target
- A [Reown Cloud](https://cloud.reown.com) project ID (free) for wallet connectivity

## First build

1. `open ios/Thousand/Thousand.xcodeproj`
2. Xcode resolves the single SPM dependency (`reown-swift`). First resolve takes a minute — it pulls a prebuilt binary (yttrium).
3. Target **Thousand → Signing & Capabilities**: pick your team. The **App Groups** capability (`group.xyz.thsnd.thousand`) is already in the entitlements — with automatic signing Xcode registers it for your team. If you change the bundle id, rename the group to match and update `WalletService.configureIfPossible()`.
4. Paste your Reown project ID into `Config.reownProjectID` (`Thousand/App/Config.swift`).
5. Run. With an empty project ID the app still builds and runs fully **read-only** (watch-an-address mode) — useful immediately and for App Review demos.

## Where things live

| Path | What |
|---|---|
| `App/Config.swift` | All addresses, RPCs, flags. The only file you should need to edit. |
| `Chain/` | Zero-dependency chain layer: keccak, 256-bit ints, ABI, JSON-RPC, typed reads. |
| `Wallet/WalletService.swift` + `Wallet/SocketFactory.swift` | The **only two files** that import the Reown SDK. If a Reown release shifts its API, compiler errors land here and nowhere else. |
| `Features/` | One folder per tab: Dashboard, Vault, Burn, Tiers, Company. |

## Design decisions

- **SPM pin** is `1.0.0 ..< 2.0.0`. After your first successful resolve, File → Packages → note the resolved version in this README and consider pinning exactly.
- **No web3 library.** Reads are hand-rolled `eth_call` against the same public RPCs the site uses (no batching — Base public endpoints reject batches), plus Blockscout for historical logs from deploy block `48117150`. Selectors are precomputed and cross-checked against the in-app keccak at startup in debug builds.
- **Debug self-tests**: keccak known-answer vectors + every ABI selector assert on launch (DEBUG only).
- **Brand**: pure monochrome per `docs/BRAND_THOUSAND.md` — no accent color, no corner radius, ▲▼ glyphs for direction, monospaced numerals, `SYS:` status lines.

## Known integration notes

- `Networking.configure(groupIdentifier:projectId:socketFactory:)` and `AppKit.configure(projectId:metadata:crypto:)` match the current reown-swift API. If your resolved version differs, the fix is confined to `WalletService.swift`.
- The WebSocket factory is URLSession-based (no Starscream). If `WebSocketConnecting` gains requirements, add them in `SocketFactory.swift`.
- SIWE/auth flows are intentionally unsupported (`recoverPubKey` throws) — the app never asks users to sign auth messages.

## Ship it

See `docs/APPSTORE/` at the repo root: submission runbook (Apple org account → D-U-N-S → certificates → TestFlight → review), complete metadata pack, review notes addressing guideline 3.1.5(b), and the privacy policy that must be live at `thsnd.xyz/privacy.html` before submission.
