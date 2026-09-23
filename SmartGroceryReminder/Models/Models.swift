import Foundation
import CoreLocation

struct AppUser: Identifiable, Codable, Equatable {
    let id: String
    var email: String
    var displayName: String
}

struct GroceryItem: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var notes: String
    var aisle: String
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String = "",
        aisle: String = "",
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.aisle = aisle
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GeoPlace: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var kind: PlaceKind

    enum PlaceKind: String, Codable, CaseIterable {
        case home
        case groceryStore
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 150,
        kind: PlaceKind
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.kind = kind
    }
}

extension GeoPlace {
    /// Straight-line distance in meters.
    func distance(to other: GeoPlace) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

struct UserPreferences: Codable, Equatable {
    var homeLocation: GeoPlace?
    var savedStores: [GeoPlace]
    var homeArrivalDelay: TimeInterval
    var reminderHour: Int
    var reminderMinute: Int
    var dailyListReminderEnabled: Bool
    var storeEntryReminderEnabled: Bool
    var repeatCarUnloadReminder: Bool
    var carUnloadRepeatInterval: TimeInterval

    static let `default` = UserPreferences(
        homeLocation: GeoPlace(
            name: "Home",
            latitude: 37.7749,
            longitude: -122.4194,
            radiusMeters: 120,
            kind: .home
        ),
        savedStores: [
            GeoPlace(
                name: "Neighborhood Market",
                latitude: 37.7849,
                longitude: -122.4094,
                radiusMeters: 200,
                kind: .groceryStore
            )
        ],
        homeArrivalDelay: 10 * 60,
        reminderHour: 17,
        reminderMinute: 30,
        dailyListReminderEnabled: true,
        storeEntryReminderEnabled: true,
        repeatCarUnloadReminder: true,
        carUnloadRepeatInterval: 5 * 60
    )
}

enum SampleData {
    static let groceryItems: [GroceryItem] = [
        GroceryItem(title: "Milk", notes: "2% gallon", aisle: "Dairy"),
        GroceryItem(title: "Sourdough bread", aisle: "Bakery"),
        GroceryItem(title: "Bananas", aisle: "Produce"),
        GroceryItem(title: "Eggs", notes: "Cage-free dozen", aisle: "Dairy", isCompleted: true),
        GroceryItem(title: "Coffee beans", aisle: "Beverages")
    ]
}
