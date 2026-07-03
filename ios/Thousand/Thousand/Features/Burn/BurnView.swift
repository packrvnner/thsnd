//
//  BurnView.swift
//  Thousand
//
//  Thousand Burn: cumulative burn chart from Burned events (Blockscout),
//  plus permissionless burnDirect() to torch whatever THSND sits in the
//  BurnEngine.
//

import SwiftUI
import Charts

@MainActor
final class BurnViewModel: ObservableObject {
    @Published var records: [BurnRecord] = []
    @Published var engineBalance: U256 = .zero
    @Published var totalBurned: U256 = .zero
    @Published var loading = true
    @Published var busy = false
    @Published var status: String?
    @Published var error: String?

    struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let cumulative: Double
    }

    var chartPoints: [ChartPoint] {
        var running = 0.0
        var points: [ChartPoint] = []
        for r in records {
            running += r.amount.toDouble(scale: 18)
            points.append(ChartPoint(date: r.date, cumulative: running))
        }
        return points
    }

    func refresh() async {
        loading = records.isEmpty
        do {
            async let history = ChainService.shared.fetchBurnHistory()
            async let stats = ChainService.shared.fetchTokenStats()
            async let engine = ChainService.shared.rpc.callUint(
                to: Config.thsnd, fn: .balanceOf, args: [.address(Config.burnEngine)])
            records = try await history
            totalBurned = try await stats.burned
            engineBalance = try await engine
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func burnDirect() async {
        busy = true
        defer { busy = false }
        do {
            let hash = try await WalletService.shared.sendTransaction(
                to: Config.burnEngine, data: ChainService.shared.burnDirectCalldata())
            status = "burn submitted: \(hash.prefix(10))…"
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BurnView: View {
    @EnvironmentObject var wallet: WalletService
    @StateObject private var vm = BurnViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    HeroNumber(label: "THSND burned — forever",
                               value: vm.totalBurned.formatted(decimals: 18, maxFraction: 2),
                               sub: String(format: "%.5f%% of genesis supply",
                                           vm.totalBurned.toDouble(scale: 18) / 1_000_000_000 * 100))
                }

                Card {
                    SectionLabel("Cumulative burn")
                    if vm.loading {
                        ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 160)
                    } else if vm.chartPoints.isEmpty {
                        Text("No burns yet. The engine is waiting.")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        Chart(vm.chartPoints) { point in
                            LineMark(x: .value("Date", point.date),
                                     y: .value("Burned", point.cumulative))
                            .foregroundStyle(Theme.text)
                            .interpolationMethod(.stepEnd)
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisGridLine().foregroundStyle(Theme.hairline)
                                AxisValueLabel().foregroundStyle(Theme.secondary).font(Theme.mono(9))
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine().foregroundStyle(Theme.hairline)
                                AxisValueLabel().foregroundStyle(Theme.secondary).font(Theme.mono(9))
                            }
                        }
                        .frame(height: 180)
                    }
                }

                Card {
                    SectionLabel("Burn engine")
                    StatRow(label: "Pending in engine",
                            value: vm.engineBalance.formatted(decimals: 18, maxFraction: 2) + " THSND")
                    Text("burnDirect() is permissionless: anyone may burn the THSND held by the engine. Liquidation slices route here.")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.secondary)
                    if wallet.canTransact {
                        ActionButton(title: "Burn it",
                                     disabled: vm.engineBalance == .zero,
                                     busy: vm.busy) {
                            Task { await vm.burnDirect() }
                        }
                    } else {
                        SysLine(text: "connect a wallet to trigger a burn.")
                    }
                }

                if !vm.records.isEmpty {
                    Card {
                        SectionLabel("Recent burns")
                        ForEach(vm.records.suffix(8).reversed()) { r in
                            StatRow(label: r.date.formatted(date: .numeric, time: .shortened),
                                    value: "−" + r.amount.formatted(decimals: 18, maxFraction: 2))
                        }
                    }
                }

                if let status = vm.status { SysLine(text: status) }
                if let error = vm.error {
                    Text(error).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
    }
}
