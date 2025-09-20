//
//  SpotShareManager.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-25.
//

import Foundation
import FirebaseFirestore
import os.log

/// A manager responsible for creating temporary and permanent sharing URLs for spots and collections.
enum SpotShareManager {

    private static let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SpotShareManager")
    
    /// Creates a temporary, 30-day share link for a single spot.
    ///
    /// This saves a payload to the `/shares` collection in Firestore and returns a URL containing the new document ID.
    static func makeShareURL(from spot: Spot, collectionName: String?, senderName: String?, userId: String) async throws -> URL {
        let expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days in seconds

        let payload = SharedSpotPayload(
            name: spot.name,
            address: spot.address,
            latitude: spot.latitude,
            longitude: spot.longitude,
            category: spot.category.rawValue,
            phoneNumber: spot.phoneNumber,
            websiteURL: spot.websiteURL,
            notes: spot.notes,
            collectionName: collectionName,
            sourceURL: spot.sourceURL,
            senderName: senderName,
            creatorUid: userId,
            expiresAt: Timestamp(date: expirationDate),
            v: 1
        )
        
        // 1. Save the payload to the new 'shares' collection in Firestore
        let db = Firestore.firestore()
        let ref = try await db.collection("shares").addDocument(from: payload)
        let shareId = ref.documentID
        
        logger.info("Saved temporary spot share payload with ID: \(shareId)")
        
        // 2. Build the new, short URL with the document ID
        let urlString = "https://sweetspotsshare.netlify.app/s/spot/\(shareId)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        return url
    }
    
    static func makePrivateCollectionShareURL(
            from collection: SpotCollection,
            with spots: [Spot],
            senderName: String?,
            userId: String
        ) async throws -> URL {
            /// Creates a temporary, 30-day share link for a private collection and its spots.
            let expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)
            let payload = SharedCollectionPayload(
                collectionName: collection.name,
                collectionDescription: collection.descriptionText,
                spots: spots.map { spot in
                    // Convert each Spot into a SharedSpotPayload
                    SharedSpotPayload(
                        name: spot.name,
                        address: spot.address,
                        latitude: spot.latitude,
                        longitude: spot.longitude,
                        category: spot.category.rawValue,
                        phoneNumber: spot.phoneNumber,
                        websiteURL: spot.websiteURL,
                        notes: spot.notes,
                        sourceURL: spot.sourceURL
                        // Note: We don't include senderName/creatorUid per-spot here
                    )
                },
                senderName: senderName,
                creatorUid: userId,
                expiresAt: Timestamp(date: expirationDate),
                v: 1
            )
            let db = Firestore.firestore()
            let ref = try await db.collection("shares").addDocument(from: payload)
            let shareId = ref.documentID
            
            logger.info("Saved temporary collection share payload with ID: \(shareId)")
            
            let urlString = "https://sweetspotsshare.netlify.app/s/collection/\(shareId)"
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            return url
        }
    
    /// Creates a permanent, public link for a collection and marks it as public in Firestore.
    static func makePublicCollectionShareURL(for collection: SpotCollection) async throws -> URL {
        guard let collectionId = collection.id, !collection.userId.isEmpty else {
            throw URLError(.badURL)
        }
        
        // 1. Make the collection public in Firestore
        let db = Firestore.firestore()
        let collectionRef = db.collection("users").document(collection.userId).collection("spotCollections").document(collectionId)
        
        // This makes the collection readable by the public via security rules
        try await collectionRef.updateData(["isPublic": true])
        
        // 2. Build the permanent URL that points directly to the data
        let urlString = "https://sweetspotsshare.netlify.app/c/\(collection.userId)/\(collectionId)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        logger.info("Successfully created permanent public link for collection: \(collectionId)")
        
        return url
    }
}
