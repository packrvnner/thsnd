# App Store Submission Runbook — Thousand iOS

*Written July 3, 2026. The app is built and in `ios/Thousand/`. This is the path from "code in repo" to "live on the App Store," including the parts only a human with the Apple account can click.*

## 0. The one blocking prerequisite: an organization account

Apple's guideline **3.1.5(b)** requires apps that facilitate cryptocurrency transactions to be submitted by a developer **enrolled as an organization**, not an individual. Thousand's Vault (lock/claim/withdraw) and burn trigger are transaction features, so this applies.

An organization enrollment needs, in order:

1. **A legal entity.** "MUY Labs / Thousand" is currently a brand, not an entity. An LLC or C-corp works; this is the same entity the audit/legal track (ARCHITECTURE.md §5) already calls for, so form it once and use it for both. The entity's legal name appears as the App Store seller name.
2. **A D-U-N-S number** for that entity (free, dnb.com — allow ~5 business days; Apple has an expedited lookup at developer.apple.com/enroll/duns-lookup).
3. **Apple Developer Program enrollment** as Organization ($99/yr) at developer.apple.com — requires the D-U-N-S, a website (thsnd.xyz ✓), and someone with legal authority to bind the entity.
4. A **support email + support URL** for the app listing (e.g., support@thsnd.xyz — the domain email needs to exist).

If you want beta testers on TestFlight while the D-U-N-S paperwork grinds, note: TestFlight also runs through the same developer account, so the entity is genuinely the first domino. Total elapsed time from zero: typically 1–2 weeks.

## 1. Before touching Xcode

- [ ] **Reown project ID** — create at cloud.reown.com (free), paste into `Config.reownProjectID`. Set the project's allowed bundle id to `xyz.thsnd.thousand`.
- [ ] **Privacy policy live** — `website/privacy.html` in this repo must deploy to `https://thsnd.xyz/privacy.html` (App Store Connect requires the URL at submission).
- [ ] Confirm pool liquidity + audit posture you're comfortable defending in review (see §5 — reviewers do look at crypto apps' websites).

## 2. Build & archive (on the Mac, ~30 min)

1. `open ios/Thousand/Thousand.xcodeproj` — Xcode 16+ required.
2. Wait for SPM to resolve `reown-swift` (first time pulls a binary dependency; minutes, not seconds).
3. Signing & Capabilities → select the **organization team**. Automatic signing registers the bundle id and the `group.xyz.thsnd.thousand` App Group.
4. Product → Destination → **Any iOS Device (arm64)** → Product → **Archive**.
5. Organizer → **Distribute App** → App Store Connect → Upload. Export compliance is pre-answered (`ITSAppUsesNonExemptEncryption = false` — HTTPS/standard crypto only).

## 3. App Store Connect setup (~1 hr)

1. appstoreconnect.apple.com → My Apps → **+ New App**: platform iOS, bundle id `xyz.thsnd.thousand`, SKU `THSND-IOS-1`, name **Thousand — THSND on Base** (fallbacks in `METADATA.md` if taken).
2. Paste everything from `METADATA.md` (description, keywords, subtitle, promotional text, support URL, marketing URL, privacy policy URL).
3. **App Privacy** questionnaire: answers in `METADATA.md §Privacy` — the honest summary is *no data collected*: no accounts, no analytics, no tracking; wallet addresses stay on device (UserDefaults) and are sent only to public RPC endpoints as query parameters, which Apple's questionnaire treats as not-collected because it never reaches a developer-controlled server.
4. **Age rating** questionnaire: no restricted content categories; note there IS an unrestricted-web question — answer No (the app opens links in the system browser, not an embedded browser). Crypto apps typically land at 4+ this way; if the wizard offers a "frequent/intense simulated gambling" style question, everything is No.
5. Category: **Finance**. Secondary: none.
6. Upload screenshots (plan + caption copy in `SCREENSHOTS.md` — 6.9" and 6.5" iPhone sets required; take them in Simulator on the largest iPhone).
7. Build section → select the uploaded build.
8. **App Review Information**: paste the reviewer notes from `REVIEW_NOTES.md` verbatim, including the watch-address demo instructions (no demo account needed — that's the point of read-only mode). Contact info: you.

## 4. TestFlight first (recommended, not required)

Internal testing needs no review: TestFlight tab → add yourself + up to 100 internal testers → smoke-test lock/claim with a real wallet on Base against small amounts. External TestFlight groups DO require a lighter "beta review" — same 3.1.5(b) rules apply, so don't treat it as a way around the org account.

## 5. What App Review will probe on a DeFi app (be ready)

- **Org enrollment** (3.1.5(b)) — covered above; individual accounts get an instant rejection here.
- **No hidden functionality** (2.3.1) — `Config.transactionsEnabled` is a compile-time constant and the review notes disclose it. Never gate features server-side.
- **The app is not a thin wrapper** (4.2) — it's fully native; no WebViews exist in the codebase.
- **Financial-promotion tone** (3.2.2 / regional finance rules) — the brand rule "speed, precision, tools — never profit" is load-bearing here. The metadata contains zero APY/profit language; keep it that way in updates. The in-app Disclosures card states pre-launch/unaudited status plainly.
- **Reviewer can't reach the chain?** Read-only watch mode + the treasury Safe address in review notes give them something to look at without funds.
- Expect 1–3 review cycles for a first crypto app; typical turnaround is 24–48h per cycle. Rejections come with a specific guideline number — reply in Resolution Center, fix, resubmit.

## 6. After approval

- Release option: **Manually release** (pick the moment; coordinate with the audit/launch messaging — an App Store listing is a public announcement).
- Watch crash reports (Xcode Organizer) and the RPC endpoints' behavior under real traffic.
- Version bumps: `MARKETING_VERSION` in the target build settings; every store update re-enters review.
- When the audit lands, add the report link to the app's Disclosures card and the store description — it's the single best conversion line the listing can have.

## Realistic timeline

| Step | Time |
|---|---|
| Legal entity + D-U-N-S | 3–10 business days |
| Apple org enrollment | 1–3 days after D-U-N-S |
| Reown ID, privacy page deploy, archive, ASC setup | 1 day |
| TestFlight internal shake-out | 2–5 days |
| Review cycles | 1–7 days |
| **Total** | **~2–4 weeks, dominated by paperwork** |
