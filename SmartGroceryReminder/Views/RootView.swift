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

struct MainTabView: View {
    var body: some View {
        TabView {
            ShoppingListView()
                .tabItem {
                    Label("List", systemImage: "cart")
                }

            HomeArrivalView()
                .tabItem {
                    Label("Arrival", systemImage: "house.fill")
                }

            LocationsView()
                .tabItem {
                    Label("Places", systemImage: "mappin.and.ellipse")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(Color("AccentGreen"))
    }
}
