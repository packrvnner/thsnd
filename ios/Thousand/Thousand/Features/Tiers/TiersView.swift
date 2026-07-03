//
//  TiersView.swift
//  Thousand
//
//  Execution Tiers: T1 / T10 / T100 / T1000. Locked THSND counts 2×.
//  T1000 = all thousand milliseconds, zero protocol fee.
//

import SwiftUI

@MainActor
final class TiersViewModel: ObservableObject {
    @Published var info: TierInfo?
    @Published var table: ([U256], [Int])?
    @Published var error: String?

    func refresh(address: String?) async {
        do {
            table = try await ChainService.shared.fetchTierTable()
            if let address {
                info = try await ChainService.shared.fetchTierInfo(for: address)
            } else {
                info = nil
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TiersView: View {
    @EnvironmentObject var wallet: WalletService
    @StateObject private var vm = TiersViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let info = vm.info {
                    Card {
                        HeroNumber(label: "Your tier", value: info.name,
                                   sub: info.discountBps == 10_000
                                       ? "fees declined to exist."
                                       : "−\(info.discountBps / 100)% protocol fee")
                        StatRow(label: "Effective balance",
                                value: info.effectiveBalance.formatted(decimals: 18, maxFraction: 0) + " THSND")
                    }
                } else {
                    Card {
                        SectionLabel("Your tier")
                        SysLine(text: "connect or watch an address to read your tier.")
                    }
                }

                Card {
                    SectionLabel("Tier table")
                    tierRow(name: "T1", requirement: "—", discount: discount(0))
                    ForEach(0..<(vm.table?.0.count ?? 0), id: \.self) { i in
                        tierRow(name: TierInfo.names[min(i + 1, TierInfo.names.count - 1)],
                                requirement: "≥ " + (vm.table?.0[i].formatted(decimals: 18, maxFraction: 0) ?? "—"),
                                discount: discount(i + 1))
                    }
                    Divider().background(Theme.hairline)
                    Text("Effective balance = wallet THSND + 2× actively locked THSND. Expired locks stop counting.")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.secondary)
                }

                Card {
                    SectionLabel("The math")
                    Text("T1000 holds all one thousand milliseconds: protocol fee zero. Tiers re-read on every trade — no registration, no snapshots.")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.secondary)
                }

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

    private func tierRow(name: String, requirement: String, discount: String) -> some View {
        HStack {
            Text(name)
                .font(Theme.mono(14, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 64, alignment: .leading)
            Text(requirement)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text(discount)
                .font(Theme.mono(12, weight: .medium))
                .foregroundStyle(Theme.text)
        }
    }

    private func discount(_ tier: Int) -> String {
        guard let d = vm.table?.1, tier < d.count else { return "—" }
        return d[tier] == 10_000 ? "0 fee" : "−\(d[tier] / 100)%"
    }
}
