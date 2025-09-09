//
//  SpotCollection.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-04.
//

import Foundation
import FirebaseFirestore

/// Represents a user-defined collection of spots.
struct SpotCollection: Identifiable, Codable, Hashable {
    
    /// The document ID from Firestore.
    @DocumentID var id: String?
    
    /// The ID of the user who owns this collection.
    var userId: String
    
    /// The name of the collection (e.g., "Italy Trip 2024", "Local Cafes").
    var name: String
    
    /// An optional, user-provided description for the collection.
    var descriptionText: String?
    
    
    // It will be nil until set by the Firestore server.
    /// The server-side timestamp of when the collection was created.
    @ServerTimestamp var createdAt: Timestamp?
    var isPublic: Bool = false // Default to private


    
    init(
        id: String? = nil,
        userId: String,
        name: String,
        descriptionText: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.descriptionText = descriptionText
        // `createdAt` is no longer assigned here.
    }
    
    
    /// A Boolean value indicating whether the collection has valid, non-empty essential data.
    var hasValidData: Bool {
        // Ensure name and userId are not just whitespace.
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
