//
//  Config.swift
//  Thousand
//
//  Single source of truth for chain + app configuration.
//  Addresses mirror deployments/base-mainnet-thsnd.md (July 2, 2026).
//

import Foundation

enum Config {

    // MARK: - Chain

    /// Base mainnet
    static let chainIdDecimal = 8453
    static let chainIdHex = "0x2105"
    static let caip2Chain = "eip155:8453"

    /// Public RPCs. Base public endpoints reject JSON-RPC batches — the RPC
    /// client sends plain parallel calls and rotates on failure (same strategy
    /// as the website).
    static let rpcEndpoints = [
        "https://mainnet.base.org",
        "https://base-rpc.publicnode.com",
        "https://base.llamarpc.com",
    ]

    /// Blockscout REST API — used for historical event logs (burns, locks)
    /// without eth_getLogs block-range limits.
    static let blockscoutAPI = "https://base.blockscout.com/api"

    /// First block of the THSND deployment; log scans start here.
    static let deployBlock = 48_117_150

    // MARK: - Contracts (Base mainnet — THSND deployment, July 2 2026)

    static let thsnd        = "0xF7aa829ed31fE30834E56348e9CD3fBb4687CFdb" // token, 18 dec, burn-only
    static let latticeLock  = "0x1141F662b0647C2776Bb6A59B0ECA3Db481e6847" // Thousand Vault (vTHSND)
    static let burnEngine   = "0x81929143c44a8141A1d2C40dB3774F1B262674D2"
    static let tierRegistry = "0x4056179e23E87d88f76381df54e458E529fdf7BA"
    static let treasurySafe = "0x539DE6F65dECEB2F491237e3DC030494E517877C"
    static let aerodromePool = "0xcacf70ae3ba1fa1dc16bea05e57ea90fef0657c0" // THSND/USDC
    static let usdc         = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" // 6 dec
    static let weth         = "0x4200000000000000000000000000000000000006" // 18 dec, vault reward token
    static let milliVault   = "0xF925b09790035E0ef60Cd115eba7E8bDD10981d0" // mTHSND (shadow mode)

    // MARK: - Token constants

    static let genesisSupply = U256.tenPow18(multiplier: 1_000_000_000) // 1B THSND, fixed at genesis
    static let thsndDecimals = 18
    static let usdcDecimals = 6
    static let wethDecimals = 18

    /// LatticeLock bounds (seconds)
    static let minLock: UInt64 = 7 * 24 * 3600            // 1 week
    static let maxLock: UInt64 = 4 * 365 * 24 * 3600      // 4 years

    // MARK: - Company / links

    static let siteURL = URL(string: "https://thsnd.xyz")!
    static let milliFeedURL = URL(string: "https://thsnd.xyz/milli-feed.json")!
    static let privacyPolicyURL = URL(string: "https://thsnd.xyz/privacy.html")!
    static let basescan = "https://basescan.org/address/"
    static let aerodromeSwapURL = URL(string: "https://aerodrome.finance/swap?from=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913&to=0xF7aa829ed31fE30834E56348e9CD3fBb4687CFdb")!

    // MARK: - WalletConnect (Reown AppKit)

    /// Create a project at https://cloud.reown.com (free) and paste the ID.
    /// With an empty ID the app runs in read-only mode: every screen works,
    /// transactions are disabled. This is transparent — no hidden features.
    static let reownProjectID = "" // ← REQUIRED for wallet actions

    /// Must match CFBundleURLSchemes in Info.plist.
    static let deepLinkScheme = "thousand"

    /// Feature flag: on-chain write actions (lock / claim / withdraw / burn).
    /// Compile-time, documented in App Review notes — never toggled remotely.
    static let transactionsEnabled = true

    // MARK: - Epochs (Aerodrome cadence: Thursday 00:00 UTC)

    static func nextEpoch(after date: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.weekday = 5 // Thursday
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) ?? date
    }
}
