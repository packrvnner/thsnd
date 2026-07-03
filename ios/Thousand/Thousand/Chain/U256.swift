//
//  U256.swift
//  Thousand
//
//  Minimal fixed-width 256-bit unsigned integer — just enough for ERC-20
//  amounts: decimal/hex parsing, exact wei arithmetic, display scaling.
//  Little-endian limbs (4 × UInt64). No external dependencies.
//

import Foundation

struct U256: Equatable, Comparable, Hashable {
    /// limbs[0] = least significant 64 bits
    private(set) var limbs: [UInt64] // always exactly 4

    static let zero = U256()

    init() { limbs = [0, 0, 0, 0] }

    init(_ v: UInt64) { limbs = [v, 0, 0, 0] }

    // MARK: - Parsing

    /// Parse an 0x-prefixed (or bare) hex quantity, e.g. RPC return data.
    /// Values wider than 256 bits are rejected (returns nil).
    init?(hexQuantity: String) {
        var s = hexQuantity.lowercased()
        if s.hasPrefix("0x") { s = String(s.dropFirst(2)) }
        if s.isEmpty { s = "0" }
        guard s.count <= 64, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        self.init()
        for c in s {
            let d = UInt64(String(c), radix: 16)!
            mulSmall(16)
            addSmall(d)
        }
    }

    /// Parse a human decimal amount ("1234.5") into base units with `decimals`
    /// places, exactly. Rejects more fractional digits than `decimals`.
    init?(decimal: String, decimals: Int) {
        let parts = decimal.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !decimal.isEmpty else { return nil }
        let intPart = parts.count >= 1 ? String(parts[0]) : "0"
        var fracPart = parts.count == 2 ? String(parts[1]) : ""
        guard intPart.allSatisfy({ $0.isNumber }) || intPart.isEmpty,
              fracPart.allSatisfy({ $0.isNumber }),
              fracPart.count <= decimals else { return nil }
        while fracPart.count < decimals { fracPart += "0" }
        let digits = (intPart.isEmpty ? "0" : intPart) + fracPart
        self.init()
        for c in digits {
            mulSmall(10)
            addSmall(UInt64(String(c))!)
        }
    }

    // MARK: - Formatting

    /// 0x-prefixed minimal hex quantity (for RPC params).
    var hexQuantity: String {
        var s = ""
        for limb in limbs.reversed() {
            if s.isEmpty {
                if limb != 0 { s = String(limb, radix: 16) }
            } else {
                s += String(format: "%016llx", limb)
            }
        }
        return "0x" + (s.isEmpty ? "0" : s)
    }

    /// 64-hex-char word without 0x (for ABI encoding).
    var abiWord: String {
        limbs.reversed().map { String(format: "%016llx", $0) }.joined()
    }

    /// Full decimal string.
    var decimalString: String {
        var digits: [Character] = []
        var v = self
        repeat {
            let r = v.divmodSmall(10)
            digits.append(Character(String(r)))
        } while v != .zero
        return String(digits.reversed())
    }

    /// Approximate Double after dividing by 10^scale (display only).
    func toDouble(scale: Int) -> Double {
        var d = 0.0
        for limb in limbs.reversed() {
            d = d * 18_446_744_073_709_551_616.0 + Double(limb)
        }
        return d / pow(10.0, Double(scale))
    }

    /// "1,234,567.89" style display with `maxFraction` fractional digits.
    func formatted(decimals: Int, maxFraction: Int = 2) -> String {
        let s = decimalString
        let padded = String(repeating: "0", count: max(0, decimals + 1 - s.count)) + s
        let intPart = String(padded.dropLast(decimals))
        var frac = String(padded.suffix(decimals).prefix(maxFraction))
        while frac.hasSuffix("0") { frac = String(frac.dropLast()) }
        var grouped = ""
        for (i, c) in intPart.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(",") }
            grouped.append(c)
        }
        let head = String(grouped.reversed())
        return frac.isEmpty ? head : head + "." + frac
    }

    // MARK: - Arithmetic

    static func < (a: U256, b: U256) -> Bool {
        for i in (0..<4).reversed() {
            if a.limbs[i] != b.limbs[i] { return a.limbs[i] < b.limbs[i] }
        }
        return false
    }

    /// Saturating subtraction (clamps at zero; token math never underflows
    /// when the chain is the source of truth, but never trap in UI code).
    func subtractingSaturating(_ other: U256) -> U256 {
        guard other <= self else { return .zero }
        var out = U256()
        var borrow: UInt64 = 0
        for i in 0..<4 {
            let (d1, o1) = limbs[i].subtractingReportingOverflow(other.limbs[i])
            let (d2, o2) = d1.subtractingReportingOverflow(borrow)
            out.limbs[i] = d2
            borrow = (o1 ? 1 : 0) + (o2 ? 1 : 0)
        }
        return out
    }

    func adding(_ other: U256) -> U256 {
        var out = U256()
        var carry: UInt64 = 0
        for i in 0..<4 {
            let (s1, o1) = limbs[i].addingReportingOverflow(other.limbs[i])
            let (s2, o2) = s1.addingReportingOverflow(carry)
            out.limbs[i] = s2
            carry = (o1 ? 1 : 0) + (o2 ? 1 : 0)
        }
        return out
    }

    private mutating func mulSmall(_ m: UInt64) {
        var carry: UInt64 = 0
        for i in 0..<4 {
            let (hi, lo) = limbs[i].multipliedFullWidth(by: m)
            let (sum, o) = lo.addingReportingOverflow(carry)
            limbs[i] = sum
            carry = hi &+ (o ? 1 : 0)
        }
        // overflow beyond 256 bits is silently truncated; inputs are validated upstream
    }

    private mutating func addSmall(_ a: UInt64) {
        var carry = a
        for i in 0..<4 where carry != 0 {
            let (sum, o) = limbs[i].addingReportingOverflow(carry)
            limbs[i] = sum
            carry = o ? 1 : 0
        }
    }

    /// Divide in place by a small divisor, returning the remainder.
    private mutating func divmodSmall(_ d: UInt64) -> UInt64 {
        var rem: UInt64 = 0
        for i in (0..<4).reversed() {
            let (q, r) = d.dividingFullWidth((high: rem, low: limbs[i]))
            limbs[i] = q
            rem = r
        }
        return rem
    }

    // MARK: - Convenience

    /// multiplier × 10^18 (exact) — for token-count constants.
    static func tenPow18(multiplier: UInt64) -> U256 {
        var v = U256(multiplier)
        for _ in 0..<18 { v.mulSmall(10) }
        return v
    }
}
