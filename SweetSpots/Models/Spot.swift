//
//  Spot.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import FirebaseFirestore
import CoreLocation

struct Spot: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var id: String?
    var userId: String?
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var sourceURL: String?
    var category: String // Make category non-optional for consistency, default if needed
    @ServerTimestamp var createdAt: Timestamp? = Timestamp()
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    static func == (lhs: Spot, rhs: Spot) -> Bool {
        lhs.id == rhs.id
    }

    // Initialize with a default category if it's not provided
    init(id: String? = nil, userId: String? = nil, name: String, address: String, latitude: Double, longitude: Double, sourceURL: String? = nil, category: String = SpotCategory.other.displayName, createdAt: Timestamp? = Timestamp()) {
        self.id = id
        self.userId = userId
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.sourceURL = sourceURL
        self.category = category
        self.createdAt = createdAt
    }
}

// Define your categories
// Using an enum is good practice for type safety and managing display names/icons
enum SpotCategory: String, CaseIterable, Identifiable {
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
        case .food: return "fork.knife.circle.fill"
        case .nature: return "leaf.fill"
        case .shopping: return "tag.fill"
        case .sights: return "camera.fill"
        case .activities: return "figure.walk.motion"
        case .other: return "mappin.and.ellipse.circle.fill"
        }
    }
}
