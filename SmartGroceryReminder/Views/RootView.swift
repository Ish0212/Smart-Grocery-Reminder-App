import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isAuthenticated)
    }
}

/// The tabs, also reachable from the widget as `smartgrocery://<tab>`.
enum AppTab: String, CaseIterable {
    case list, arrival, places, settings

    init?(url: URL) {
        guard url.scheme == "smartgrocery", let host = url.host(), let tab = AppTab(rawValue: host) else { return nil }
        self = tab
    }
}

struct MainTabView: View {
    @State private var selection: AppTab = .list

    var body: some View {
        TabView(selection: $selection) {
            ShoppingListView()
                .tabItem {
                    Label("List", systemImage: "cart")
                }
                .tag(AppTab.list)

            HomeArrivalView()
                .tabItem {
                    Label("Arrival", systemImage: "house.fill")
                }
                .tag(AppTab.arrival)

            LocationsView()
                .tabItem {
                    Label("Places", systemImage: "mappin.and.ellipse")
                }
                .tag(AppTab.places)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .tint(Color("AccentGreen"))
        .onOpenURL { url in
            if let tab = AppTab(url: url) {
                selection = tab
            }
        }
    }
}
