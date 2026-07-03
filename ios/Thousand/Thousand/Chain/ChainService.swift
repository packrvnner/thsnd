//
//  ChainService.swift
//  Thousand
//
//  Typed reads for every Thousand contract, aggregated into view models.
//

import Foundation

// MARK: - Models

struct TokenStats {
    var totalSupply: U256 = .zero
    var burned: U256 = .zero          // genesis − totalSupply (burn-only token)
    var priceUSD: Double = 0          // from Aerodrome THSND/USDC reserves
    var fdvUSD: Double = 0
    var liquidityUSD: Double = 0      // 2 × USDC reserve
    var totalLocked: U256 = .zero
    var totalPower: U256 = .zero      // Σ vTHSND
}

struct LockPosition {
    var amount: U256 = .zero
    var power: U256 = .zero
    var end: Date = .distantPast
    var earnedWETH: U256 = .zero
    var walletBalance: U256 = .zero
    var allowance: U256 = .zero

    var isActive: Bool { amount != .zero }
    var isExpired: Bool { isActive && end <= Date() }
}

struct TierInfo {
    var tier: Int = 0
    var effectiveBalance: U256 = .zero
    var discountBps: Int = 0
    var thresholds: [U256] = []
    var discountsBps: [Int] = []

    static let names = ["T1", "T10", "T100", "T1000"]
    var name: String { Self.names[min(tier, Self.names.count - 1)] }
}

struct BurnRecord: Identifiable {
    let id = UUID()
    let amount: U256
    let newTotalSupply: U256
    let date: Date
}

struct MilliState: Decodable {
    struct NavPoint: Decodable {
        let t: UInt64
        let nav: Double
    }
    struct Live: Decodable {
        let nav: Double
        let px: Double
        let updated: String
    }
    let mode: String
    let startNav: Double
    let navHistory: [NavPoint]
    let ticks: Int?
    let state: Live?
}

// MARK: - Service

final class ChainService {
    static let shared = ChainService()
    let rpc = RPCClient()

    private var poolTHSNDIsToken0: Bool?

    // MARK: Aggregate reads

    func fetchTokenStats() async throws -> TokenStats {
        async let supplyA = rpc.callUint(to: Config.thsnd, fn: .totalSupply)
        async let reservesA = rpc.callWords(to: Config.aerodromePool, fn: .getReserves)
        async let token0A = poolToken0()
        async let lockedA = rpc.callUint(to: Config.latticeLock, fn: .totalLocked)
        async let powerA = rpc.callUint(to: Config.latticeLock, fn: .totalPower)

        var s = TokenStats()
        s.totalSupply = try await supplyA
        s.burned = Config.genesisSupply.subtractingSaturating(s.totalSupply)
        s.totalLocked = try await lockedA
        s.totalPower = try await powerA

        let words = try await reservesA
        let thsndIsToken0 = try await token0A
        if words.count >= 2,
           let r0 = U256(hexQuantity: words[0]),
           let r1 = U256(hexQuantity: words[1]) {
            let thsndReserve = (thsndIsToken0 ? r0 : r1).toDouble(scale: Config.thsndDecimals)
            let usdcReserve = (thsndIsToken0 ? r1 : r0).toDouble(scale: Config.usdcDecimals)
            if thsndReserve > 0 {
                s.priceUSD = usdcReserve / thsndReserve
                s.fdvUSD = s.priceUSD * s.totalSupply.toDouble(scale: Config.thsndDecimals)
                s.liquidityUSD = usdcReserve * 2
            }
        }
        return s
    }

    private func poolToken0() async throws -> Bool {
        if let cached = poolTHSNDIsToken0 { return cached }
        let t0 = try await rpc.callWords(to: Config.aerodromePool, fn: .token0)
        let isTHSND = ("0x" + (t0.first?.suffix(40) ?? "")).lowercased() == Config.thsnd.lowercased()
        poolTHSNDIsToken0 = isTHSND
        return isTHSND
    }

    func fetchLockPosition(for address: String) async throws -> LockPosition {
        async let locksA = rpc.callWords(to: Config.latticeLock, fn: .locks, args: [.address(address)])
        async let earnedA = rpc.callUint(to: Config.latticeLock, fn: .earned, args: [.address(address)])
        async let balanceA = rpc.callUint(to: Config.thsnd, fn: .balanceOf, args: [.address(address)])
        async let allowanceA = rpc.callUint(to: Config.thsnd, fn: .allowance,
                                            args: [.address(address), .address(Config.latticeLock)])

        var p = LockPosition()
        let words = try await locksA
        if words.count >= 3,
           let amount = U256(hexQuantity: words[0]),
           let power = U256(hexQuantity: words[1]),
           let endRaw = U256(hexQuantity: words[2]) {
            p.amount = amount
            p.power = power
            p.end = Date(timeIntervalSince1970: endRaw.toDouble(scale: 0))
        }
        p.earnedWETH = try await earnedA
        p.walletBalance = try await balanceA
        p.allowance = try await allowanceA
        return p
    }

    func fetchTierInfo(for address: String) async throws -> TierInfo {
        async let tierA = rpc.callUint(to: Config.tierRegistry, fn: .tierOf, args: [.address(address)])
        async let effA = rpc.callUint(to: Config.tierRegistry, fn: .effectiveBalance, args: [.address(address)])
        async let discA = rpc.callUint(to: Config.tierRegistry, fn: .discountOf, args: [.address(address)])

        var t = TierInfo()
        t.tier = Int(try await tierA.toDouble(scale: 0))
        t.effectiveBalance = try await effA
        t.discountBps = Int(try await discA.toDouble(scale: 0))
        t.thresholds = try await fetchTierTable().0
        t.discountsBps = try await fetchTierTable().1
        return t
    }

    /// Static tier table (3 thresholds, 4 discounts) — public array getters.
    private var cachedTierTable: ([U256], [Int])?
    func fetchTierTable() async throws -> ([U256], [Int]) {
        if let c = cachedTierTable { return c }
        var thresholds: [U256] = []
        for i in 0..<3 {
            thresholds.append(try await rpc.callUint(to: Config.tierRegistry, fn: .thresholds, args: [.uint(U256(UInt64(i)))]))
        }
        var discounts: [Int] = []
        for i in 0..<4 {
            let d = try await rpc.callUint(to: Config.tierRegistry, fn: .feeDiscountBps, args: [.uint(U256(UInt64(i)))])
            discounts.append(Int(d.toDouble(scale: 0)))
        }
        let table = (thresholds, discounts)
        cachedTierTable = table
        return table
    }

    /// Burn history from the token's Burned events via Blockscout.
    func fetchBurnHistory() async throws -> [BurnRecord] {
        let logs = try await Blockscout.logs(address: Config.thsnd, topic0: ABI.Event.burned.rawValue)
        return logs.compactMap { log in
            // Burned(address indexed from, uint256 amount, uint256 newTotalSupply)
            let words = ABI.words(log.data)
            guard words.count >= 2,
                  let amount = U256(hexQuantity: words[0]),
                  let newSupply = U256(hexQuantity: words[1]),
                  let date = log.timestamp else { return nil }
            return BurnRecord(amount: amount, newTotalSupply: newSupply, date: date)
        }.sorted { $0.date < $1.date }
    }

    func fetchMilli() async throws -> MilliState {
        let (data, _) = try await URLSession.shared.data(from: Config.milliFeedURL)
        return try JSONDecoder().decode(MilliState.self, from: data)
    }

    // MARK: Transaction calldata builders (sent via WalletService)

    func approveCalldata(amount: U256) -> String {
        ABI.encode(.approve, [.address(Config.latticeLock), .uint(amount)])
    }

    func lockCalldata(amount: U256, durationSeconds: UInt64) -> String {
        ABI.encode(.lock, [.uint(amount), .uint(U256(durationSeconds))])
    }

    func claimCalldata() -> String { ABI.encode(.claim) }
    func withdrawCalldata() -> String { ABI.encode(.withdraw) }
    func burnDirectCalldata() -> String { ABI.encode(.burnDirect) }

    // MARK: Debug

    /// Cross-check precomputed selectors against the in-app keccak in DEBUG.
    func selfCheck() {
        #if DEBUG
        Keccak256.selfTest()
        let fns: [ABI.Fn] = [.totalSupply, .balanceOf, .approve, .lock, .locks, .earned, .claim,
                             .withdraw, .tierOf, .burnDirect, .getReserves, .token0]
        for fn in fns {
            let computed = "0x" + Keccak256.hash(fn.signature).prefix(4).map { String(format: "%02x", $0) }.joined()
            assert(computed == fn.rawValue, "selector mismatch for \(fn.signature): \(computed) != \(fn.rawValue)")
        }
        #endif
    }
}
