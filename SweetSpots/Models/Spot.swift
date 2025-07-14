//
//  Spot.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//
import SwiftUI
import FirebaseFirestore
import CoreLocation

/// Represents a single saved location.
struct Spot: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var id: String?
    var userId: String                 // ID of the user who owns this spot
    var name: String
    var address: String
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
    var sourceURL: String?              // Optional URL for the original post/source
    var category: SpotCategory
    // ✅ ADD THIS NEW PROPERTY
    var notes: String?
    
    @ServerTimestamp var createdAt: Timestamp?


    // Additional details from MKMapItem (if populated)
    var phoneNumber: String?
    var websiteURL: String?
    
    var wantsNearbyNotification: Bool = false
    private var _notificationRadiusMeters: Double = 200.0
    var notificationRadiusMeters: Double {
        get { _notificationRadiusMeters }
        set {
            // Clamp the value to the allowed range upon setting.
            _notificationRadiusMeters = max(50.0, min(50000.0, newValue))
        }
    }
    var collectionId: String?     // Optional: ID of the SpotCollection this spot belongs to

    /// Provides map-compatible coordinates.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // ✅ IMPROVEMENT: Enhanced equality check
    static func == (lhs: Spot, rhs: Spot) -> Bool {
        // If both have IDs, compare by ID
        if let lhsId = lhs.id, let rhsId = rhs.id {
            return lhsId == rhsId
        }
        // If neither has ID (both are new), compare by content
        if lhs.id == nil && rhs.id == nil {
            return lhs.userId == rhs.userId &&
                   lhs.name == rhs.name &&
                   lhs.address == rhs.address &&
                   abs(lhs.latitude - rhs.latitude) < 0.000001 &&
                   abs(lhs.longitude - rhs.longitude) < 0.000001
        }
        // If one has ID and other doesn't, they're different
        return false
    }

    // ✅ IMPROVEMENT: Better hash implementation
    func hash(into hasher: inout Hasher) {
        if let id = id {
            hasher.combine(id)
        } else {
            hasher.combine(userId)
            hasher.combine(name)
            hasher.combine(address)
            hasher.combine(latitude)
            hasher.combine(longitude)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
            case id
            case userId
            case name
            case address
            case latitude
            case longitude
            case sourceURL
            case category
            case createdAt
            case phoneNumber
            case websiteURL
            case wantsNearbyNotification
            // Map the private property to the desired key in Firestore
            case _notificationRadiusMeters = "notificationRadiusMeters"
            case collectionId
            case notes
        }

    // ✅ CLEANED UP: Removed trailing whitespace
    init(
        id: String? = nil,
        userId: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        sourceURL: String? = nil,
        category: SpotCategory = .other,
        phoneNumber: String? = nil,
        websiteURL: String? = nil,
        collectionId: String? = nil,
        wantsNearbyNotification: Bool = false,
        notificationRadiusMeters: Double = 200.0,
        notes: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.sourceURL = sourceURL
        self.category = category
        self.phoneNumber = phoneNumber
        self.websiteURL = websiteURL
        self.collectionId = collectionId
        self.wantsNearbyNotification = wantsNearbyNotification
        self.notes = notes
        
        // ✅ IMPROVEMENT: Validate and clamp radius to valid range
        self.notificationRadiusMeters = notificationRadiusMeters
    }
    
    // ✅ NEW: Validation helpers
    var isValidCoordinate: Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
    }
    
    var isValidNotificationRadius: Bool {
        notificationRadiusMeters >= 50.0 && notificationRadiusMeters <= 50000.0
    }
    
    var hasValidData: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidCoordinate &&
        isValidNotificationRadius
    }
    
    // ✅ NEW: Distance helper
    func distance(from location: CLLocation) -> CLLocationDistance {
        let spotLocation = CLLocation(latitude: latitude, longitude: longitude)
        return location.distance(from: spotLocation)
    }
    
    // ✅ NEW: URL validation helpers
    var hasValidSourceURL: Bool {
        guard let urlString = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return true } // nil or empty is valid
        return URL(string: urlString) != nil
    }
    
    var hasValidWebsiteURL: Bool {
        guard let urlString = websiteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return true } // nil or empty is valid
        return URL(string: urlString) != nil
    }
}

/// Defines categories for spots, with associated display names and icons.
enum SpotCategory: String, CaseIterable, Identifiable, Codable {
    case food = "Food & Drink"
    case nature = "Nature & Parks"
    case shopping = "Shopping"
    case sights = "Sights & Landmarks"
    case activities = "Activities"
    case other = "Other"

    var id: String { self.rawValue }

    var displayName: String {
        return self.rawValue
    }

    var systemImageName: String {
        switch self {
        case .food: return "fork.knife"
        case .nature: return "leaf.fill"
        case .shopping: return "bag.fill"
        case .sights: return "camera.fill"
        case .activities: return "figure.walk"
        case .other: return "mappin.and.ellipse"
        }
    }
    
    // ✅ NEW: Helper for color coding categories if needed
    var associatedColor: String {
        switch self {
        case .food: return "orange"
        case .nature: return "green"
        case .shopping: return "purple"
        case .sights: return "blue"
        case .activities: return "red"
        case .other: return "gray"
        }
    }
}
