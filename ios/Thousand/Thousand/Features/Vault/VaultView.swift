//
//  VaultView.swift
//  Thousand
//
//  Thousand Vault (LatticeLock): lock THSND 1wk–4yr for vTHSND + WETH fee
//  share. Lock / top-up, claim, withdraw at expiry. Approve-then-lock flow.
//

import SwiftUI

@MainActor
final class VaultViewModel: ObservableObject {
    @Published var position: LockPosition?
    @Published var amountText = ""
    @Published var durationWeeks: Double = 52
    @Published var busy = false
    @Published var status: String?
    @Published var error: String?

    var amount: U256? { U256(decimal: amountText, decimals: Config.thsndDecimals) }

    var durationSeconds: UInt64 {
        let clamped = min(max(durationWeeks, 1), 208)
        return UInt64(clamped * 7 * 24 * 3600)
    }

    /// vTHSND preview: amount × duration / MAX_LOCK (contract formula).
    var powerPreview: Double {
        guard let a = amount else { return 0 }
        return a.toDouble(scale: 18) * Double(durationSeconds) / Double(Config.maxLock)
    }

    var needsApproval: Bool {
        guard let a = amount, let p = position else { return false }
        return p.allowance < a
    }

    func refresh(address: String?) async {
        guard let address else { position = nil; return }
        do {
            position = try await ChainService.shared.fetchLockPosition(for: address)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func approve() async {
        guard let a = amount else { return }
        await run(label: "approval") {
            try await WalletService.shared.sendTransaction(
                to: Config.thsnd,
                data: ChainService.shared.approveCalldata(amount: a))
        }
    }

    func lock() async {
        guard let a = amount else { return }
        await run(label: "lock") {
            try await WalletService.shared.sendTransaction(
                to: Config.latticeLock,
                data: ChainService.shared.lockCalldata(amount: a, durationSeconds: durationSeconds))
        }
    }

    func claim() async {
        await run(label: "claim") {
            try await WalletService.shared.sendTransaction(
                to: Config.latticeLock, data: ChainService.shared.claimCalldata())
        }
    }

    func withdraw() async {
        await run(label: "withdraw") {
            try await WalletService.shared.sendTransaction(
                to: Config.latticeLock, data: ChainService.shared.withdrawCalldata())
        }
    }

    private func run(label: String, _ op: () async throws -> String) async {
        busy = true
        defer { busy = false }
        do {
            let hash = try await op()
            status = "\(label) submitted: \(hash.prefix(10))…"
            error = nil
            try? await Task.sleep(nanoseconds: 4_000_000_000) // let the chain settle
            await refresh(address: WalletService.shared.address)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct VaultView: View {
    @EnvironmentObject var wallet: WalletService
    @StateObject private var vm = VaultViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = vm.position, p.isActive {
                    positionCard(p)
                }
                lockForm
                if let p = vm.position {
                    claimCard(p)
                }
                Card {
                    SectionLabel("How it works")
                    Text("vTHSND = amount × duration ÷ 4 years, fixed at lock time. Protocol fees (WETH) stream pro-rata to vTHSND. Principal is non-custodial — no admin path can touch it. Expired locks lose governance weight until withdrawn.")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.secondary)
                }
                if let status = vm.status { SysLine(text: status) }
                if let error = vm.error {
                    Text(error).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .refreshable { await vm.refresh(address: wallet.address) }
        .task(id: wallet.address) { await vm.refresh(address: wallet.address) }
    }

    private func positionCard(_ p: LockPosition) -> some View {
        Card {
            SectionLabel("Your lock")
            HeroNumber(label: "vTHSND",
                       value: p.power.formatted(decimals: 18, maxFraction: 2))
            StatRow(label: "Locked", value: p.amount.formatted(decimals: 18, maxFraction: 2) + " THSND")
            StatRow(label: "Unlocks", value: p.end.formatted(date: .abbreviated, time: .shortened))
            if p.isExpired {
                SysLine(text: "lock expired. principal withdrawable. voting weight zero.")
            }
        }
    }

    private var lockForm: some View {
        Card {
            SectionLabel(vm.position?.isActive == true ? "Top up lock" : "New lock")

            if let p = vm.position {
                StatRow(label: "Wallet balance",
                        value: p.walletBalance.formatted(decimals: 18, maxFraction: 2) + " THSND",
                        dimValue: true)
            }

            TextField("0.0", text: $vm.amountText)
                .keyboardType(.decimalPad)
                .font(Theme.display(28))
                .foregroundStyle(Theme.text)
                .padding(10)
                .background(Theme.bg)
                .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))

            HStack {
                SectionLabel("Duration")
                Spacer()
                Text(durationLabel)
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            Slider(value: $vm.durationWeeks, in: 1...208, step: 1)
                .tint(Theme.text)

            StatRow(label: "You receive",
                    value: String(format: "%.2f vTHSND", vm.powerPreview))

            if wallet.canTransact {
                if vm.needsApproval {
                    ActionButton(title: "1 · Approve THSND", busy: vm.busy) {
                        Task { await vm.approve() }
                    }
                    ActionButton(title: "2 · Lock", style: .secondary, disabled: true) {}
                } else {
                    ActionButton(title: vm.position?.isActive == true ? "Top up" : "Lock",
                                 disabled: vm.amount == nil || vm.amount == .zero,
                                 busy: vm.busy) {
                        Task { await vm.lock() }
                    }
                }
            } else {
                connectHint
            }
        }
    }

    private func claimCard(_ p: LockPosition) -> some View {
        Card {
            SectionLabel("Fee share")
            HeroNumber(label: "Claimable WETH",
                       value: p.earnedWETH.formatted(decimals: 18, maxFraction: 6))
            if wallet.canTransact {
                HStack(spacing: 10) {
                    ActionButton(title: "Claim", disabled: p.earnedWETH == .zero, busy: vm.busy) {
                        Task { await vm.claim() }
                    }
                    if p.isExpired {
                        ActionButton(title: "Withdraw", style: .secondary, busy: vm.busy) {
                            Task { await vm.withdraw() }
                        }
                    }
                }
            }
        }
    }

    private var connectHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(Theme.hairline)
            SysLine(text: wallet.address == nil
                    ? "connect a wallet to lock."
                    : "watching only. connect a wallet to transact.")
        }
    }

    private var durationLabel: String {
        let w = Int(vm.durationWeeks)
        if w >= 52 && w % 52 == 0 { return "\(w / 52)y" }
        if w >= 52 { return String(format: "%.1fy", Double(w) / 52) }
        return "\(w)w"
    }
}
