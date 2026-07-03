//
//  ThousandApp.swift
//  Thousand
//
//  One second. A thousand chances.
//

import SwiftUI

@main
struct ThousandApp: App {
    @StateObject private var wallet = WalletService.shared

    @MainActor
    init() {
        ChainService.shared.selfCheck()
        WalletService.shared.configureIfPossible()

        // Monochrome chrome
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = .black
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = .black
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(wallet)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
                    .navigationTitle("THOUSAND")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Markets", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack {
                VaultView()
                    .navigationTitle("VAULT")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Vault", systemImage: "lock.square") }

            NavigationStack {
                BurnView()
                    .navigationTitle("BURN")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Burn", systemImage: "flame") }

            NavigationStack {
                TiersView()
                    .navigationTitle("TIERS")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Tiers", systemImage: "square.stack.3d.up") }

            NavigationStack {
                CompanyView()
                    .navigationTitle("COMPANY")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Company", systemImage: "building.2") }
        }
        .tint(.white)
        .background(Theme.bg)
    }
}
