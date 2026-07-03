//
//  RPCClient.swift
//  Thousand
//
//  Plain JSON-RPC over HTTPS with endpoint rotation. Base's public endpoints
//  reject JSON-RPC batches, so calls are sent individually and parallelized
//  with structured concurrency (same strategy as the website).
//

import Foundation

actor RPCClient {

    struct RPCError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var endpointIndex = 0
    private var consecutiveFailures = 0
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    // MARK: - Core

    private struct Request: Encodable {
        let jsonrpc = "2.0"
        let id = 1
        let method: String
        let params: [AnyEncodable]
    }

    private struct AnyEncodable: Encodable {
        let encodeFn: (Encoder) throws -> Void
        init<T: Encodable>(_ value: T) { encodeFn = { try value.encode(to: $0) } }
        func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
    }

    private func send(method: String, params: [AnyEncodable]) async throws -> Data {
        var lastError: Error = RPCError(message: "no endpoints")
        for attempt in 0..<Config.rpcEndpoints.count {
            let endpoint = Config.rpcEndpoints[(endpointIndex + attempt) % Config.rpcEndpoints.count]
            do {
                var req = URLRequest(url: URL(string: endpoint)!)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONEncoder().encode(Request(method: method, params: params))
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    throw RPCError(message: "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                if attempt > 0 { endpointIndex = (endpointIndex + attempt) % Config.rpcEndpoints.count }
                consecutiveFailures = 0
                return data
            } catch {
                lastError = error
                continue
            }
        }
        consecutiveFailures += 1
        throw lastError
    }

    private struct CallResult: Decodable {
        struct Err: Decodable { let message: String }
        let result: String?
        let error: Err?
    }

    /// eth_call → 0x-prefixed return data.
    func call(to: String, data: String) async throws -> String {
        struct CallObj: Encodable { let to: String; let data: String }
        let raw = try await send(method: "eth_call",
                                 params: [AnyEncodable(CallObj(to: to, data: data)), AnyEncodable("latest")])
        let decoded = try JSONDecoder().decode(CallResult.self, from: raw)
        if let err = decoded.error { throw RPCError(message: err.message) }
        guard let result = decoded.result else { throw RPCError(message: "empty result") }
        return result
    }

    func blockNumber() async throws -> Int {
        let raw = try await send(method: "eth_blockNumber", params: [])
        let decoded = try JSONDecoder().decode(CallResult.self, from: raw)
        guard let hex = decoded.result, let v = Int(hex.dropFirst(2), radix: 16) else {
            throw RPCError(message: "bad block number")
        }
        return v
    }

    // MARK: - Typed helpers

    func callUint(to: String, fn: ABI.Fn, args: [ABI.Value] = []) async throws -> U256 {
        let ret = try await call(to: to, data: ABI.encode(fn, args))
        guard let v = ABI.uint(ret) else { throw RPCError(message: "decode failed: \(fn.signature)") }
        return v
    }

    func callWords(to: String, fn: ABI.Fn, args: [ABI.Value] = []) async throws -> [String] {
        let ret = try await call(to: to, data: ABI.encode(fn, args))
        return ABI.words(ret)
    }
}

// MARK: - Blockscout log fetch (historical events without getLogs range limits)

struct LogEntry: Decodable {
    let data: String
    let topics: [String]
    let timeStamp: String   // hex
    let blockNumber: String // hex

    var timestamp: Date? {
        guard let t = UInt64(timeStamp.dropFirst(2), radix: 16) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
}

enum Blockscout {
    struct Response: Decodable {
        let status: String
        let result: [LogEntry]?
    }

    static func logs(address: String, topic0: String) async throws -> [LogEntry] {
        var comps = URLComponents(string: Config.blockscoutAPI)!
        comps.queryItems = [
            .init(name: "module", value: "logs"),
            .init(name: "action", value: "getLogs"),
            .init(name: "fromBlock", value: String(Config.deployBlock)),
            .init(name: "toBlock", value: "latest"),
            .init(name: "address", value: address),
            .init(name: "topic0", value: topic0),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.result ?? []
    }
}
