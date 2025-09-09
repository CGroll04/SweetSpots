//
//  SharedSpotPayload.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-25.
//

import Foundation
import FirebaseFirestore

struct SharedSpotPayload: Codable, Equatable {
    // required
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    
    func resolvedCategory(default fallback: SpotCategory = .other) -> SpotCategory {
        SpotCategory(rawValue: category) ?? fallback
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
        
        // Map all other relevant properties
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
