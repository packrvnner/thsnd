//
//  DashboardView.swift
//  Thousand
//
//  Price, FDV, liquidity, supply, burned, locked, epoch countdown.
//

import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var stats: TokenStats?
    @Published var error: String?
    @Published var lastRefreshMs: Int?

    func refresh() async {
        let start = Date()
        do {
            stats = try await ChainService.shared.fetchTokenStats()
            lastRefreshMs = Int(Date().timeIntervalSince(start) * 1000)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let s = vm.stats {
                    Card {
                        HeroNumber(
                            label: "$THSND / USDC",
                            value: s.priceUSD > 0 ? String(format: "$%.6f", s.priceUSD) : "—",
                            sub: s.priceUSD > 0 ? String(format: "FDV $%@ · LIQ $%@",
                                                         Self.compact(s.fdvUSD), Self.compact(s.liquidityUSD)) : "pool not seeded"
                        )
                    }

                    Card {
                        SectionLabel("Supply")
                        StatRow(label: "Genesis", value: Config.genesisSupply.formatted(decimals: 18, maxFraction: 0))
                        StatRow(label: "Current", value: s.totalSupply.formatted(decimals: 18, maxFraction: 0))
                        StatRow(label: "Burned", value: s.burned.formatted(decimals: 18, maxFraction: 2))
                        StatRow(label: "Burned %", value: String(format: "%.4f%%",
                            s.burned.toDouble(scale: 18) / 1_000_000_000 * 100))
                        Divider().background(Theme.hairline)
                        SysLine(text: "supply only goes down. no mint function exists.")
                    }

                    Card {
                        SectionLabel("Vault")
                        StatRow(label: "THSND locked", value: s.totalLocked.formatted(decimals: 18, maxFraction: 0))
                        StatRow(label: "Total vTHSND", value: s.totalPower.formatted(decimals: 18, maxFraction: 0))
                    }

                    Card {
                        SectionLabel("Next fee epoch")
                        Text(countdown)
                            .font(Theme.display(28))
                            .foregroundStyle(Theme.text)
                        Text("Thursday 00:00 UTC — WETH fees stream to vTHSND lockers.")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondary)
                    }

                    Link(destination: Config.aerodromeSwapURL) {
                        HStack {
                            Text("TRADE ON AERODROME ↗")
                                .font(Theme.mono(13, weight: .bold))
                                .tracking(1.0)
                            Spacer()
                        }
                        .padding(14)
                        .overlay(Rectangle().stroke(Theme.text, lineWidth: 1))
                        .foregroundStyle(Theme.text)
                    }

                    if let ms = vm.lastRefreshMs {
                        SysLine(text: "refresh took \(ms)ms. we counted.")
                    }
                } else if let err = vm.error {
                    Card {
                        SectionLabel("RPC")
                        Text(err).font(Theme.mono(12)).foregroundStyle(Theme.secondary)
                        ActionButton(title: "Retry", style: .secondary) {
                            Task { await vm.refresh() }
                        }
                    }
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 120)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
        .onReceive(clock) { now = $0 }
    }

    private var countdown: String {
        let target = Config.nextEpoch(after: now)
        let s = max(0, Int(target.timeIntervalSince(now)))
        return String(format: "%dd %02dh %02dm %02ds", s / 86400, (s % 86400) / 3600, (s % 3600) / 60, s % 60)
    }

    private static func compact(_ v: Double) -> String {
        switch v {
        case 1_000_000...: return String(format: "%.2fM", v / 1_000_000)
        case 1_000...: return String(format: "%.1fK", v / 1_000)
        default: return String(format: "%.0f", v)
        }
    }
}
