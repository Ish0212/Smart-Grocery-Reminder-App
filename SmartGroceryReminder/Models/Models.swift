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
    /// Who checked it off. On a shared list, only your own check-offs count toward your unload reminder.
    var completedBy: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String = "",
        aisle: String = "",
        isCompleted: Bool = false,
        completedBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.aisle = aisle
        self.isCompleted = isCompleted
        self.completedBy = completedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A grocery list's members. A list's ID is its owner's uid; everyone starts on their own list.
struct SharedListInfo: Equatable {
    let ownerId: String
    let memberIds: [String]

    static let maxMembers = 10

    var isShared: Bool { memberIds.count > 1 }

    static func personal(_ userId: String) -> SharedListInfo {
        SharedListInfo(ownerId: userId, memberIds: [userId])
    }
}

enum SharedListError: LocalizedError, Equatable {
    case invalidCode
    case expiredCode
    case listFull
    case cannotLeaveOwnList
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "That code doesn't match a list. Check it and try again."
        case .expiredCode: return "That invite has expired. Ask for a new code."
        case .listFull: return "That list already has \(SharedListInfo.maxMembers) people."
        case .cannotLeaveOwnList: return "This is your own list, so there's nothing to leave."
        case .notSignedIn: return "Sign in first."
        }
    }
}

/// Short codes for joining someone's list: no 0/O/1/I/L, so they're easy to read out loud.
enum InviteCode {
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 8
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    static func generate() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// Uppercases and drops spaces and dashes, so "abcd-2345" and "ABCD 2345" both work.
    static func normalize(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
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
        // Fixed IDs: geofence identifiers are built from place IDs and must stay the same across launches.
        homeLocation: GeoPlace(
            id: "default-home",
            name: "Home",
            latitude: 37.7749,
            longitude: -122.4194,
            radiusMeters: 120,
            kind: .home
        ),
        savedStores: [
            GeoPlace(
                id: "default-store",
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
