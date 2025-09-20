//
//  SharedCollectionPayload.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-26.
//

import Foundation
import FirebaseFirestore

/// A data structure for encoding and decoding a shared collection and its spots.
struct SharedCollectionPayload: Codable, Equatable {
    // Collection Info
    var collectionName: String
    var collectionDescription: String?
    
    var spots: [SharedSpotPayload]
    
    // Versioning
    var senderName: String?
    var creatorUid: String?
    var expiresAt: Timestamp?
    var v: Int = 1
}
