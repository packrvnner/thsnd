//
//  CompanyView.swift
//  Thousand
//
//  Milli (agent vault, shadow mode), contract addresses, links, wallet
//  management, and the risk disclosures App Review expects to find.
//

import SwiftUI
import Charts

@MainActor
final class CompanyViewModel: ObservableObject {
    @Published var milli: MilliState?
    @Published var milliError: String?

    func refresh() async {
        do {
            milli = try await ChainService.shared.fetchMilli()
            milliError = nil
        } catch {
            milliError = "milli feed unreachable"
        }
    }
}

struct CompanyView: View {
    @EnvironmentObject var wallet: WalletService
    @StateObject private var vm = CompanyViewModel()
    @State private var watchInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                walletCard
                milliCard
                addressesCard
                linksCard
                disclosureCard
                SysLine(text: "1000ms per second. all of them in use.")
            }
            .padding(16)
        }
        .background(Theme.bg)
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
    }

    // MARK: Wallet

    private var walletCard: some View {
        Card {
            SectionLabel("Wallet")
            switch wallet.mode {
            case .connected(let addr):
                StatRow(label: "Connected", value: String(addr.prefix(6)) + "…" + String(addr.suffix(4)))
                ActionButton(title: "Disconnect", style: .secondary) { wallet.disconnect() }
            case .watching(let addr):
                StatRow(label: "Watching", value: String(addr.prefix(6)) + "…" + String(addr.suffix(4)), dimValue: true)
                HStack(spacing: 10) {
                    if wallet.isConfigured {
                        ActionButton(title: "Connect wallet") { wallet.presentConnectModal() }
                    }
                    ActionButton(title: "Stop watching", style: .secondary) { wallet.stopWatching() }
                }
            case .disconnected:
                if wallet.isConfigured {
                    ActionButton(title: "Connect wallet") { wallet.presentConnectModal() }
                } else {
                    SysLine(text: "walletconnect not configured in this build. read-only mode.")
                }
                Divider().background(Theme.hairline)
                SectionLabel("Or watch any address")
                HStack(spacing: 8) {
                    TextField("0x…", text: $watchInput)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(10)
                        .background(Theme.bg)
                        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
                    Button {
                        wallet.watch(address: watchInput)
                    } label: {
                        Text("WATCH")
                            .font(Theme.mono(12, weight: .bold))
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Theme.text)
                            .foregroundStyle(.black)
                    }
                }
            }
            if let err = wallet.lastError {
                Text(err).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
            }
        }
    }

    // MARK: Milli

    private var milliCard: some View {
        Card {
            HStack {
                SectionLabel("Milli — agent vault")
                Spacer()
                Text((vm.milli?.mode ?? "offline").uppercased())
                    .font(Theme.mono(10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .overlay(Rectangle().stroke(Theme.secondary, lineWidth: 1))
                    .foregroundStyle(Theme.secondary)
            }
            if let m = vm.milli {
                let nav = m.state?.nav ?? m.navHistory.last?.nav ?? m.startNav
                HeroNumber(label: "NAV",
                           value: String(format: "$%.2f", nav),
                           sub: String(format: "start $%.0f · %@%.2f%% · %d ticks",
                                       m.startNav,
                                       nav >= m.startNav ? "▲" : "▼",
                                       abs(nav / m.startNav - 1) * 100,
                                       m.ticks ?? m.navHistory.count))
                if m.navHistory.count > 1 {
                    Chart(Array(m.navHistory.enumerated()), id: \.offset) { item in
                        LineMark(x: .value("t", Date(timeIntervalSince1970: TimeInterval(item.element.t))),
                                 y: .value("nav", item.element.nav))
                        .foregroundStyle(Theme.text)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel().foregroundStyle(Theme.secondary).font(Theme.mono(9))
                        }
                    }
                    .frame(height: 120)
                }
                Text("Shadow mode: paper NAV, no user funds. mTHSND deposits open after audit.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondary)
            } else {
                SysLine(text: vm.milliError ?? "loading…")
            }
        }
    }

    // MARK: Addresses / links / legal

    private var addressesCard: some View {
        Card {
            SectionLabel("Contracts — Base mainnet")
            addressRow("THSND", Config.thsnd)
            addressRow("VAULT (vTHSND)", Config.latticeLock)
            addressRow("BURN ENGINE", Config.burnEngine)
            addressRow("TIER REGISTRY", Config.tierRegistry)
            addressRow("TREASURY SAFE", Config.treasurySafe)
            addressRow("POOL (AERODROME)", Config.aerodromePool)
            addressRow("MILLI VAULT", Config.milliVault)
            Divider().background(Theme.hairline)
            Text("Source verified via Sourcify. All owner keys = the treasury Safe.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondary)
        }
    }

    private func addressRow(_ label: String, _ address: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.label())
                .tracking(1.0)
                .foregroundStyle(Theme.secondary)
            Spacer()
            AddressText(address: address)
        }
    }

    private var linksCard: some View {
        Card {
            SectionLabel("Links")
            Link("THSND.XYZ ↗", destination: Config.siteURL)
                .font(Theme.mono(13, weight: .medium)).foregroundStyle(Theme.text)
            Link("AERODROME POOL ↗", destination: Config.aerodromeSwapURL)
                .font(Theme.mono(13, weight: .medium)).foregroundStyle(Theme.text)
            Link("PRIVACY POLICY ↗", destination: Config.privacyPolicyURL)
                .font(Theme.mono(13, weight: .medium)).foregroundStyle(Theme.text)
        }
    }

    private var disclosureCard: some View {
        Card {
            SectionLabel("Disclosures")
            Text("""
            Pre-launch software. Contracts are deployed and source-verified but not yet externally audited. Digital assets are volatile and can lose all value. Nothing in this app is investment advice, and the app never promises profit — it reports numbers. This app never holds your keys or funds: transactions are signed in your own wallet and execute on public infrastructure. Speed and fee-tier figures are measured on-chain properties, not performance guarantees.
            """)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.secondary)
        }
    }
}
