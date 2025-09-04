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
    
    static func makeCollectionShareURL(from collection: SpotCollection, with spots: [Spot], senderName: String?, userId: String) async throws -> URL {
        // 1. Convert the Spot models into shareable payload models.
        let spotPayloads = spots.map { spot in
            SharedSpotPayload(
                name: spot.name,
                address: spot.address,
                latitude: spot.latitude,
                longitude: spot.longitude,
                category: spot.category.rawValue,
                phoneNumber: spot.phoneNumber,
                websiteURL: spot.websiteURL,
                notes: spot.notes,
                sourceURL: spot.sourceURL,
                senderName: senderName,
                v: 1
            )
        }
        let expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days in seconds

        // 2. Create the main collection payload.
        let collectionPayload = SharedCollectionPayload(
            collectionName: collection.name,
            collectionDescription: collection.descriptionText,
            spots: spotPayloads,
            senderName: senderName,
            creatorUid: userId,
            expiresAt: Timestamp(date: expirationDate) // <-- ADD THIS
        )
        
        let db = Firestore.firestore()
        let ref = try await db.collection("shares").addDocument(from: collectionPayload)
        let shareId = ref.documentID
        
        // This part builds the final URL
        let urlString = "https://sweetspotsshare.netlify.app/s/collection/\(shareId)"
        guard let url = URL(string: urlString) else {
            // If the URL is invalid for some reason, we throw an error
            throw URLError(.badURL)
        }
        
        // The function returns a non-optional URL on success
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
