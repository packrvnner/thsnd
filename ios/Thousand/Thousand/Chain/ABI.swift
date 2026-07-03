//
//  ABI.swift
//  Thousand
//
//  Minimal ABI encoding/decoding for the fixed set of THSND contract calls.
//  Selectors are precomputed keccak-256 constants (verified against the
//  in-app Keccak implementation by ChainService.selfCheck in DEBUG).
//

import Foundation

enum ABI {

    // MARK: - Selectors (keccak256(signature)[0..4])

    enum Fn: String {
        // THSND token
        case totalSupply       = "0x18160ddd" // totalSupply()
        case balanceOf         = "0x70a08231" // balanceOf(address)
        case approve           = "0x095ea7b3" // approve(address,uint256)
        case allowance         = "0xdd62ed3e" // allowance(address,address)
        case genesisSupply     = "0x99ec6765" // GENESIS_SUPPLY()
        // LatticeLock (Thousand Vault)
        case lock              = "0x1338736f" // lock(uint256,uint256)
        case withdraw          = "0x3ccfd60b" // withdraw()
        case claim             = "0x4e71d92d" // claim()
        case locks             = "0x5de9a137" // locks(address)
        case earned            = "0x008cc262" // earned(address)
        case votingPower       = "0xc07473f6" // votingPower(address)
        case totalPower        = "0xdb3ad22c" // totalPower()
        case totalLocked       = "0x56891412" // totalLocked()
        // TierRegistry
        case tierOf            = "0xc8f74bb8" // tierOf(address)
        case effectiveBalance  = "0x16a398f7" // effectiveBalance(address)
        case discountOf        = "0xbefa96ce" // discountOf(address)
        case thresholds        = "0xb6c22611" // thresholds(uint256)
        case feeDiscountBps    = "0x3e45ad9e" // feeDiscountBps(uint256)
        // BurnEngine
        case burnDirect        = "0x5e580104" // burnDirect()
        // Aerodrome pool (Solidly-style)
        case getReserves       = "0x0902f1ac" // getReserves()
        case token0            = "0x0dfe1681" // token0()

        var signature: String {
            switch self {
            case .totalSupply: return "totalSupply()"
            case .balanceOf: return "balanceOf(address)"
            case .approve: return "approve(address,uint256)"
            case .allowance: return "allowance(address,address)"
            case .genesisSupply: return "GENESIS_SUPPLY()"
            case .lock: return "lock(uint256,uint256)"
            case .withdraw: return "withdraw()"
            case .claim: return "claim()"
            case .locks: return "locks(address)"
            case .earned: return "earned(address)"
            case .votingPower: return "votingPower(address)"
            case .totalPower: return "totalPower()"
            case .totalLocked: return "totalLocked()"
            case .tierOf: return "tierOf(address)"
            case .effectiveBalance: return "effectiveBalance(address)"
            case .discountOf: return "discountOf(address)"
            case .thresholds: return "thresholds(uint256)"
            case .feeDiscountBps: return "feeDiscountBps(uint256)"
            case .burnDirect: return "burnDirect()"
            case .getReserves: return "getReserves()"
            case .token0: return "token0()"
            }
        }
    }

    // MARK: - Event topics (keccak256 of the event signature)

    enum Event: String {
        case burned         = "0x23ff0e75edf108e3d0392d92e13e8c8a868ef19001bd49f9e94876dc46dff87f" // Burned(address,uint256,uint256)
        case locked         = "0x44cebfefa4561bee5b61d675ccfd8dc9969fff9cc15e7a4eccccd62af94f9c11" // Locked(address,uint256,uint256,uint256)
        case rewardNotified = "0xf9a5da3a173eca8cd77c02ece3ff1467b8aa461ed3822201817f2d72fbc54283" // RewardNotified(uint256)
    }

    // MARK: - Encoding

    enum Value {
        case address(String)
        case uint(U256)
    }

    /// selector + 32-byte words. Returns 0x-prefixed calldata.
    static func encode(_ fn: Fn, _ args: [Value] = []) -> String {
        var data = fn.rawValue
        for arg in args {
            switch arg {
            case .address(let a):
                let clean = a.lowercased().replacingOccurrences(of: "0x", with: "")
                data += String(repeating: "0", count: 24) + clean
            case .uint(let v):
                data += v.abiWord
            }
        }
        return data
    }

    // MARK: - Decoding

    /// Split 0x-prefixed return data into 32-byte words (hex strings, no 0x).
    static func words(_ returnData: String) -> [String] {
        var s = returnData.lowercased()
        if s.hasPrefix("0x") { s = String(s.dropFirst(2)) }
        var out: [String] = []
        var idx = s.startIndex
        while let end = s.index(idx, offsetBy: 64, limitedBy: s.endIndex) {
            out.append(String(s[idx..<end]))
            idx = end
        }
        return out
    }

    static func uint(_ returnData: String, word: Int = 0) -> U256? {
        let ws = words(returnData)
        guard word < ws.count else { return nil }
        return U256(hexQuantity: ws[word])
    }

    static func address(_ returnData: String, word: Int = 0) -> String? {
        let ws = words(returnData)
        guard word < ws.count else { return nil }
        return "0x" + ws[word].suffix(40)
    }

    static func isValidAddress(_ s: String) -> Bool {
        let t = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
        return t.count == 40 && t.allSatisfy { $0.isHexDigit }
    }
}
