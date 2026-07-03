//
//  Keccak.swift
//  Thousand
//
//  Pure-Swift Keccak-256 (the pre-NIST padding variant used by Ethereum).
//  Used for Reown AppKit's CryptoProvider. ABI selectors in this app are
//  precomputed constants; `selfTest()` cross-checks this implementation
//  against known-answer vectors at startup in debug builds.
//

import Foundation

enum Keccak256 {

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]

    /// Rotation offsets indexed by x + 5y.
    private static let rho: [Int] = [
         0,  1, 62, 28, 27,
        36, 44,  6, 55, 20,
         3, 10, 43, 25, 39,
        41, 45, 15, 21,  8,
        18,  2, 61, 56, 14,
    ]

    static func hash(_ input: Data) -> Data {
        let rate = 136 // 1088-bit rate for 256-bit output
        var state = [UInt64](repeating: 0, count: 25)

        // Padding: 0x01 ... 0x80 (Keccak, not SHA-3's 0x06).
        // Data(input) re-bases indices in case a slice was passed in.
        var padded = Data(input)
        let padLen = rate - (padded.count % rate)
        let messageLen = padded.count
        padded.append(contentsOf: [UInt8](repeating: 0, count: padLen))
        padded[messageLen] = 0x01
        padded[padded.count - 1] |= 0x80

        padded.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < padded.count {
                for i in 0..<(rate / 8) {
                    state[i] ^= raw.loadUnaligned(fromByteOffset: offset + i * 8, as: UInt64.self).littleEndian
                }
                keccakF(&state)
                offset += rate
            }
        }

        var out = Data(capacity: 32)
        for i in 0..<4 {
            var lane = state[i].littleEndian
            withUnsafeBytes(of: &lane) { out.append(contentsOf: $0) }
        }
        return out
    }

    static func hash(_ string: String) -> Data { hash(Data(string.utf8)) }

    private static func rotl(_ v: UInt64, _ n: Int) -> UInt64 {
        n == 0 ? v : (v << n) | (v >> (64 - n))
    }

    private static func keccakF(_ a: inout [UInt64]) {
        for round in 0..<24 {
            // θ
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)
                for y in 0..<5 { a[x + 5 * y] ^= d }
            }
            // ρ and π
            var b = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[x + 5 * y], rho[x + 5 * y])
                }
            }
            // χ
            for x in 0..<5 {
                for y in 0..<5 {
                    a[x + 5 * y] = b[x + 5 * y] ^ (~b[(x + 1) % 5 + 5 * y] & b[(x + 2) % 5 + 5 * y])
                }
            }
            // ι
            a[0] ^= roundConstants[round]
        }
    }

    /// Known-answer self test; call from app start in DEBUG.
    @discardableResult
    static func selfTest() -> Bool {
        let empty = hash(Data()).map { String(format: "%02x", $0) }.joined()
        let abc = hash("abc").map { String(format: "%02x", $0) }.joined()
        let transfer = hash("transfer(address,uint256)").prefix(4).map { String(format: "%02x", $0) }.joined()
        let ok = empty == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
            && abc == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
            && transfer == "a9059cbb"
        assert(ok, "Keccak256 self-test failed")
        return ok
    }
}
