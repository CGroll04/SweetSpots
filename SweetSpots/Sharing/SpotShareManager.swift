//
//  SpotShareManager.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-25.
//

import Foundation
import FirebaseFirestore

enum SpotShareManager {
    // Change to your real Universal Link domain
    static let universalBase = URL(string: "https://\(AppConstants.universalLinkHost)\(AppConstants.universalLinkPrefix)/spot")!
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
            // This is the logic from my previous answer. It creates a temporary
            // document in the `/shares` collection with a 30-day expiry.
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
            
            let urlString = "https://sweetspotsshare.netlify.app/s/collection/\(shareId)"
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            return url
        }
    
    /// PATH 2: Creates a permanent, public link to the original collection.
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
        
        return url
    }

    static func encode<T: Codable>(_ value: T) -> String? {
        do {
            let data = try JSONEncoder().encode(value)
            return base64URLEncode(data)
        } catch { return nil }
    }

    static func decode<T: Codable>(_ type: T.Type, from base64url: String) -> T? {
        guard let data = base64URLDecode(base64url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private static func base64URLDecode(_ str: String) -> Data? {
        var s = str.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (s.count % 4)
        if pad < 4 { s.append(String(repeating: "=", count: pad)) }
        return Data(base64Encoded: s)
    }
}
