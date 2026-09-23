import Foundation
import MapKit

/// A place found by `PlaceSearchService`, ready to save as home or a store.
struct PlaceSearchResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    func geoPlace(kind: GeoPlace.PlaceKind) -> GeoPlace {
        switch kind {
        case .home:
            return GeoPlace(name: "Home", latitude: latitude, longitude: longitude, radiusMeters: 120, kind: .home)
        case .groceryStore:
            return GeoPlace(name: name, latitude: latitude, longitude: longitude, radiusMeters: 150, kind: .groceryStore)
        }
    }
}

@MainActor
enum PlaceSearchService {
    /// Searches Apple Maps for grocery stores, or for street addresses when picking home,
    /// preferring results around `center` when it is known.
    static func search(
        _ query: String,
        kind: GeoPlace.PlaceKind,
        near center: CLLocationCoordinate2D?
    ) async throws -> [PlaceSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        switch kind {
        case .groceryStore:
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket])
        case .home:
            request.resultTypes = .address
        }
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        }

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            PlaceSearchResult(
                name: item.name ?? query,
                address: item.placemark.title ?? "",
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
        }
    }
}
