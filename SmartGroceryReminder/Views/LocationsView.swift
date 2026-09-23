import SwiftUI
import MapKit

struct LocationsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var searchKind: GeoPlace.PlaceKind?
    @State private var placeMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Location access", value: LocationService.describe(locationService.authorizationStatus))
                    LabeledContent("Monitoring", value: locationService.monitoredRegions.isEmpty ? "Off" : locationService.monitoredRegions.joined(separator: ", "))
                    Text(locationService.lastEventDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    NavigationLink("Diagnostics") {
                        DiagnosticsView(diagnostics: appState.diagnostics)
                    }
                    if locationService.authorizationStatus == .notDetermined {
                        Button("Request location access") {
                            locationService.requestAuthorization()
                        }
                    }
                }

                Section("Home") {
                    if let home = appState.preferences.homeLocation {
                        placeRow(home)
                    }
                    Button("Search for home address") {
                        searchKind = .home
                    }
                    Button(appState.preferences.homeLocation == nil ? "Set home from current location" : "Use current location as home") {
                        setHomeFromCurrent()
                    }
                    .disabled(locationService.currentLocation == nil)
                }

                Section {
                    ForEach(appState.preferences.savedStores) { store in
                        placeRow(store)
                    }
                    .onDelete { offsets in
                        appState.preferences.savedStores.remove(atOffsets: offsets)
                        Task { await appState.savePreferences() }
                    }

                    Button("Search for a store") {
                        searchKind = .groceryStore
                    }

                    Button("Add demo store near SF") {
                        addPlace(GeoPlace(
                            name: "Fresh Mart",
                            latitude: 37.7810,
                            longitude: -122.4110,
                            radiusMeters: 180,
                            kind: .groceryStore
                        ))
                    }

                    Button("Simulate entering a store") {
                        locationService.simulateEnterStore()
                    }
                } header: {
                    Text("Grocery stores")
                } footer: {
                    Text("\(appState.preferences.savedStores.count) of \(AppState.maxStores) stores. iOS can watch up to 20 places per app, including home.")
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
            // One fix for "use current location" and nearby search, and again once access is granted.
            .task { locationService.requestCurrentLocation() }
            .onChange(of: locationService.authorizationStatus) { _, _ in
                locationService.requestCurrentLocation()
            }
            .sheet(item: $searchKind) { kind in
                PlaceSearchView(kind: kind, near: searchCenter) { place in
                    addPlace(place)
                }
            }
            .alert(
                "Couldn't add store",
                isPresented: Binding(get: { placeMessage != nil }, set: { if !$0 { placeMessage = nil } }),
                presenting: placeMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    /// Search near the user, or near home when the current location is unknown.
    private var searchCenter: CLLocationCoordinate2D? {
        if let current = locationService.currentLocation { return current }
        guard let home = appState.preferences.homeLocation else { return nil }
        return CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude)
    }

    private func addPlace(_ place: GeoPlace) {
        Task {
            switch place.kind {
            case .home:
                await appState.setHome(place)
            case .groceryStore:
                switch await appState.addStore(place) {
                case .added:
                    break
                case .duplicate:
                    placeMessage = "\(place.name) is already one of your stores."
                case .limitReached:
                    placeMessage = "You can save up to \(AppState.maxStores) stores. Remove one to add another."
                }
            }
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
        addPlace(GeoPlace(
            name: "Home",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: 120,
            kind: .home
        ))
    }
}

extension GeoPlace.PlaceKind: Identifiable {
    var id: String { rawValue }
}

#Preview {
    LocationsView()
        .environmentObject(AppState())
        .environmentObject(LocationService())
}
