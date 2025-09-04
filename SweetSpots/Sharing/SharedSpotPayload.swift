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
