//
//  WalletService.swift
//  Thousand
//
//  ── The ONLY file that talks to the Reown (WalletConnect) SDK. ──
//
//  If a Reown release changes its API surface, fixes land here and in
//  SocketFactory.swift; the rest of the app depends only on this class's
//  small interface (connect / disconnect / address / sendTransaction).
//
//  Configuration requires Config.reownProjectID (free at cloud.reown.com).
//  Without it the app runs in read-only mode: users can watch any address,
//  and all write actions are disabled with a visible explanation.
//

import Foundation
import Combine
import SwiftUI
import ReownAppKit
import WalletConnectSign        // Session, Request
import WalletConnectNetworking  // Networking.configure
import WalletConnectUtils       // Blockchain
import WalletConnectSigner      // EthereumSignature (CryptoProvider)
import Commons                  // AnyCodable

@MainActor
final class WalletService: ObservableObject {
    static let shared = WalletService()

    enum Mode: Equatable {
        case disconnected
        case watching(String)   // read-only pasted address
        case connected(String)  // WalletConnect session address
    }

    @Published private(set) var mode: Mode = .disconnected
    @Published var lastError: String?

    /// Address used for reads (either watched or connected).
    var address: String? {
        switch mode {
        case .disconnected: return nil
        case .watching(let a), .connected(let a): return a
        }
    }

    var canTransact: Bool {
        if case .connected = mode { return Config.transactionsEnabled && isConfigured }
        return false
    }

    private(set) var isConfigured = false
    private var cancellables = Set<AnyCancellable>()
    private var currentTopic: String?

    private let watchKey = "thousand.watchAddress"

    private init() {
        if let watched = UserDefaults.standard.string(forKey: watchKey), ABI.isValidAddress(watched) {
            mode = .watching(watched)
        }
    }

    // MARK: - Configure (call once at launch)

    func configureIfPossible() {
        guard !Config.reownProjectID.isEmpty, !isConfigured else { return }
        do {
            let metadata = AppMetadata(
                name: "Thousand",
                description: "$THSND — burn-only token, vTHSND vault, execution tiers on Base.",
                url: Config.siteURL.absoluteString,
                icons: [Config.siteURL.appendingPathComponent("assets/thsnd-mark-256.png").absoluteString],
                redirect: try AppMetadata.Redirect(native: "\(Config.deepLinkScheme)://", universal: nil)
            )
            // Group id must match Thousand.entitlements (App Groups capability).
            Networking.configure(
                groupIdentifier: "group.xyz.thsnd.thousand",
                projectId: Config.reownProjectID,
                socketFactory: URLSessionSocketFactory()
            )
            AppKit.configure(
                projectId: Config.reownProjectID,
                metadata: metadata,
                crypto: ThousandCryptoProvider()
            )
            observeSessions()
            isConfigured = true
        } catch {
            lastError = "Wallet init failed: \(error.localizedDescription)"
        }
    }

    private func observeSessions() {
        AppKit.instance.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (sessions: [Session]) in
                self?.adoptSession(sessions.first)
            }
            .store(in: &cancellables)
        adoptSession(AppKit.instance.getSessions().first)
    }

    private func adoptSession(_ session: Session?) {
        guard let session else {
            if case .connected = mode { mode = .disconnected }
            currentTopic = nil
            return
        }
        currentTopic = session.topic
        let account = session.namespaces["eip155"]?.accounts.first
        if let addr = account?.address, ABI.isValidAddress(addr) {
            mode = .connected(addr)
        }
    }

    // MARK: - Connect / disconnect / watch

    func presentConnectModal() {
        guard isConfigured else {
            lastError = "WalletConnect not configured — set Config.reownProjectID."
            return
        }
        AppKit.present()
    }

    func disconnect() {
        Task {
            if let topic = currentTopic {
                try? await AppKit.instance.disconnect(topic: topic)
            }
            mode = .disconnected
        }
    }

    func watch(address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ABI.isValidAddress(trimmed) else {
            lastError = "Invalid address."
            return
        }
        UserDefaults.standard.set(trimmed, forKey: watchKey)
        mode = .watching(trimmed)
    }

    func stopWatching() {
        UserDefaults.standard.removeObject(forKey: watchKey)
        if case .watching = mode { mode = .disconnected }
    }

    // MARK: - Transactions

    struct EthTransaction: Codable {
        let from: String
        let to: String
        let data: String
        let value: String
    }

    /// Send a transaction through the connected wallet. Returns the tx hash.
    func sendTransaction(to: String, data: String, value: U256 = .zero) async throws -> String {
        guard case .connected(let from) = mode, let topic = currentTopic else {
            throw RPCClient.RPCError(message: "No wallet connected.")
        }
        guard Config.transactionsEnabled else {
            throw RPCClient.RPCError(message: "Transactions are disabled in this build.")
        }
        let tx = EthTransaction(from: from, to: to, data: data, value: value.hexQuantity)
        let request = try Request(
            topic: topic,
            method: "eth_sendTransaction",
            params: AnyCodable([tx]),
            chainId: Blockchain(Config.caip2Chain)!
        )

        // Subscribe BEFORE sending so a fast wallet response can't be missed.
        return try await withCheckedThrowingContinuation { continuation in
            var settled = false
            var cancellable: AnyCancellable?
            cancellable = AppKit.instance.sessionResponsePublisher
                .receive(on: DispatchQueue.main)
                .sink { response in
                    guard !settled, response.id == request.id else { return }
                    settled = true
                    cancellable?.cancel()
                    switch response.result {
                    case .response(let value):
                        let hash = (try? value.get(String.self)) ?? String(describing: value)
                        continuation.resume(returning: hash)
                    case .error(let err):
                        continuation.resume(throwing: RPCClient.RPCError(message: err.message))
                    }
                }

            Task { @MainActor in
                do {
                    try await AppKit.instance.request(params: request)
                } catch {
                    guard !settled else { return }
                    settled = true
                    cancellable?.cancel()
                    continuation.resume(throwing: error)
                }
            }

            // Safety timeout — wallet closed, user abandoned, relay hiccup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
                guard !settled else { return }
                settled = true
                cancellable?.cancel()
                continuation.resume(throwing: RPCClient.RPCError(message: "Wallet response timed out."))
            }
        }
    }
}

// MARK: - CryptoProvider

/// Reown requires a CryptoProvider for its auth (SIWE) flows. This app does
/// not use SIWE; keccak is real (needed by the SDK), signature recovery is
/// intentionally unsupported.
struct ThousandCryptoProvider: CryptoProvider {
    func keccak256(_ data: Data) -> Data {
        Keccak256.hash(data)
    }

    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        throw RPCClient.RPCError(message: "SIWE not supported in this app.")
    }
}
