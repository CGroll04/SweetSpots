//
//  SharedSpotPayload.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-25.
//

import Foundation
import FirebaseFirestore
import os.log

/// A data structure for encoding and decoding a single shared spot.
struct SharedSpotPayload: Codable, Equatable {
    
    private static let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SharedSpotPayload")
    
    // required
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    
    /// Safely converts the raw string category into a `SpotCategory` enum, falling back to a default value if the raw value is invalid.
    func resolvedCategory(default fallback: SpotCategory = .other) -> SpotCategory {
        if let resolved = SpotCategory(rawValue: category) {
            return resolved
        } else {
            Self.logger.warning("Unrecognized category string '\(self.category)' found in payload. Falling back to default.")
            return fallback
        }
    }

    
    // optional
    var phoneNumber: String?
    var websiteURL: String?
    var notes: String?
    var collectionName: String?
    var sourceURL: String?
    var wantsNearbyNotification: Bool?
    var notificationRadiusMeters: Double?
    
    // versioning
    var senderName: String?
    var creatorUid: String?
    var expiresAt: Timestamp?
    var v: Int = 1
}

extension SharedSpotPayload {
    /// Creates a payload from a full Spot object.
    init(from spot: Spot) {
        self.name = spot.name
        self.address = spot.address
        self.latitude = spot.latitude
        self.longitude = spot.longitude
        self.category = spot.category.rawValue
        self.phoneNumber = spot.phoneNumber
        self.websiteURL = spot.websiteURL
        self.notes = spot.notes
        self.sourceURL = spot.sourceURL
        self.wantsNearbyNotification = spot.wantsNearbyNotification
        self.notificationRadiusMeters = spot.notificationRadiusMeters
        
        // Note: Fields like `senderName` and `expiresAt` are left nil
        // because they belong to the temporary share model, not the
        // new permanent link model.
    }
}

extension SharedSpotPayload: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(address)
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}
