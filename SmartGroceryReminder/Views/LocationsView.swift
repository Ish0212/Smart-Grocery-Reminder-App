import SwiftUI
import MapKit

struct LocationsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Location access", value: authLabel)
                    LabeledContent("Monitoring", value: locationService.monitoredRegions.isEmpty ? "Off" : locationService.monitoredRegions.joined(separator: ", "))
                    Text(locationService.lastEventDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Home") {
                    if let home = appState.preferences.homeLocation {
                        placeRow(home)
                        Button("Use current location as home") {
                            setHomeFromCurrent()
                        }
                        .disabled(locationService.currentLocation == nil)
                    } else {
                        Button("Set home from current location") {
                            setHomeFromCurrent()
                        }
                    }
                }

                Section("Grocery stores") {
                    ForEach(appState.preferences.savedStores) { store in
                        placeRow(store)
                    }
                    .onDelete { offsets in
                        appState.preferences.savedStores.remove(atOffsets: offsets)
                        Task { await appState.savePreferences() }
                    }

                    Button("Add demo store near SF") {
                        let store = GeoPlace(
                            name: "Fresh Mart",
                            latitude: 37.7810,
                            longitude: -122.4110,
                            radiusMeters: 180,
                            kind: .groceryStore
                        )
                        appState.preferences.savedStores.append(store)
                        Task { await appState.savePreferences() }
                    }

                    Button("Simulate entering a store") {
                        locationService.simulateEnterStore()
                    }
                }

                Section("Map preview") {
                    Map(position: $cameraPosition) {
                        if let home = appState.preferences.homeLocation {
                            Annotation(home.name, coordinate: .init(latitude: home.latitude, longitude: home.longitude)) {
                                Image(systemName: "house.fill").foregroundStyle(Color("AccentGreen"))
                            }
                        }
                        ForEach(appState.preferences.savedStores) { store in
                            Annotation(store.name, coordinate: .init(latitude: store.latitude, longitude: store.longitude)) {
                                Image(systemName: "cart.fill").foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .navigationTitle("Places")
            .onAppear {
                locationService.requestAuthorization()
                locationService.startMonitoring(
                    home: appState.preferences.homeLocation,
                    stores: appState.preferences.savedStores
                )
            }
        }
    }

    private var authLabel: String {
        switch locationService.authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "Unknown"
        }
    }

    private func placeRow(_ place: GeoPlace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.name).font(.body.weight(.medium))
            Text(String(format: "%.4f, %.4f · %.0fm radius", place.latitude, place.longitude, place.radiusMeters))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func setHomeFromCurrent() {
        guard let coordinate = locationService.currentLocation else { return }
        appState.preferences.homeLocation = GeoPlace(
            name: "Home",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: 120,
            kind: .home
        )
        Task { await appState.savePreferences() }
    }
}

#Preview {
    LocationsView()
        .environmentObject(AppState())
        .environmentObject(LocationService())
}
