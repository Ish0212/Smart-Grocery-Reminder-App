import XCTest
@testable import SmartGroceryReminder

final class PlacesTests: XCTestCase {
    private func store(_ name: String, latitude: Double, longitude: Double = -122.4) -> GeoPlace {
        GeoPlace(name: name, latitude: latitude, longitude: longitude, kind: .groceryStore)
    }

    @MainActor
    func testAddStoreAppendsNewStore() async {
        let state = AppState()
        let before = state.preferences.savedStores.count

        let result = await state.addStore(store("Far Market", latitude: 38.5))

        XCTAssertEqual(result, .added)
        XCTAssertEqual(state.preferences.savedStores.count, before + 1)
        XCTAssertEqual(state.preferences.savedStores.last?.name, "Far Market")
    }

    @MainActor
    func testAddStoreRejectsStoreWithin50Meters() async {
        let state = AppState()
        let existing = state.preferences.savedStores[0]
        let before = state.preferences.savedStores.count
        // 0.0002° of latitude is about 22 m.
        let nearby = store("Same shop", latitude: existing.latitude + 0.0002, longitude: existing.longitude)

        let result = await state.addStore(nearby)

        XCTAssertEqual(result, .duplicate)
        XCTAssertEqual(state.preferences.savedStores.count, before)
    }

    @MainActor
    func testAddStoreStopsAtGeofenceLimit() async {
        let state = AppState()
        state.preferences.savedStores = (0..<AppState.maxStores).map {
            store("Store \($0)", latitude: 30 + Double($0) * 0.1)
        }

        let result = await state.addStore(store("One more", latitude: 50))

        XCTAssertEqual(result, .limitReached)
        XCTAssertEqual(state.preferences.savedStores.count, AppState.maxStores)
    }

    @MainActor
    func testSetHomeReplacesHome() async {
        let state = AppState()
        let home = GeoPlace(name: "Home", latitude: 40.7, longitude: -74.0, radiusMeters: 120, kind: .home)

        await state.setHome(home)

        XCTAssertEqual(state.preferences.homeLocation, home)
    }

    func testDistanceBetweenPlaces() {
        let a = store("A", latitude: 37.0)
        let b = store("B", latitude: 37.001)  // ~111 m north
        XCTAssertEqual(a.distance(to: b), 111, accuracy: 2)
        XCTAssertEqual(a.distance(to: a), 0, accuracy: 0.001)
    }

    func testSearchResultBecomesStoreOrHome() {
        let result = PlaceSearchResult(name: "Safeway", address: "1 Main St", latitude: 37.1, longitude: -122.2)

        let asStore = result.geoPlace(kind: .groceryStore)
        XCTAssertEqual(asStore.name, "Safeway")
        XCTAssertEqual(asStore.kind, .groceryStore)
        XCTAssertEqual(asStore.latitude, 37.1)

        let asHome = result.geoPlace(kind: .home)
        XCTAssertEqual(asHome.name, "Home")
        XCTAssertEqual(asHome.kind, .home)
        XCTAssertEqual(asHome.radiusMeters, 120)
    }
}
