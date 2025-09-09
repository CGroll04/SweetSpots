//
//  DeepLinkRouter.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-25.
//

import Foundation
import SwiftUI
import FirebaseFirestore

final class NavigationCoordinator: ObservableObject {
    @Published var incomingSharedPayload: SharedSpotPayload? = nil
    @Published var incomingSharedCollectionPayload: SharedCollectionPayload? = nil
}

// ✅ CLEANED UP AND REFACTORED VERSION
enum DeepLinkRouter {
    static let allowedHosts: Set<String> = ["sweetspotsshare.netlify.app", "localhost"]
    
    // De-bouncing logic is good, no changes needed
    private static var lastHandledURL: URL?
    private static var lastHandledTime: Date?

    static func handle(url: URL, navigation: NavigationCoordinator) {
        // De-bouncing logic to prevent duplicate calls
        if let lastURL = lastHandledURL, let lastTime = lastHandledTime,
           url == lastURL && Date().timeIntervalSince(lastTime) < 2.0 {
            print("ℹ️ DeepLinkRouter: Ignoring duplicate URL handled within the last 2 seconds.")
            return
        }
        
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host, allowedHosts.contains(host) else {
            print("❌ DeepLinkRouter: Host check FAILED.")
            return
        }
        
        lastHandledURL = url
        lastHandledTime = Date()
        
        // We get the path components to decide where to go
        let pathComponents = comps.path.split(separator: "/").map(String.init)
        guard let routeType = pathComponents.first else {
            print("❌ DeepLinkRouter: Path is empty.")
            return
        }
        
        // --- ✅ SIMPLIFIED ROUTING LOGIC ---
        // We just look at the first part of the path to decide what to do.
        switch routeType {
        case "s":
            // Handles all temporary shares: /s/spot/... and /s/collection/...
            handleTemporaryShare(pathComponents: pathComponents, navigation: navigation)
        case "c":
            // Handles all permanent shares: /c/{userID}/{collectionID}
            handlePermanentCollectionShare(pathComponents: pathComponents, navigation: navigation)
        default:
            print("❌ DeepLinkRouter: Unknown route type '\(routeType)'.")
        }
    }
    
    // --- Handles BOTH temporary spots and temporary collections ---
    private static func handleTemporaryShare(pathComponents: [String], navigation: NavigationCoordinator) {
        // Expected path: ["s", "spot" or "collection", "{shareID}"]
        guard pathComponents.count == 3 else { return }
        let shareType = pathComponents[1]
        let shareId = pathComponents[2]
        
        Task {
            do {
                let db = Firestore.firestore()
                let doc = try await db.collection("shares").document(shareId).getDocument()
                
                if shareType == "spot" {
                    let payload = try doc.data(as: SharedSpotPayload.self)
                    print("✅ DeepLinkRouter: Successfully fetched temporary SPOT payload.")
                    await MainActor.run { navigation.incomingSharedPayload = payload }
                } else if shareType == "collection" {
                    let payload = try doc.data(as: SharedCollectionPayload.self)
                    print("✅ DeepLinkRouter: Successfully fetched temporary COLLECTION payload.")
                    await MainActor.run { navigation.incomingSharedCollectionPayload = payload }
                }
            } catch {
                print("❌ DeepLinkRouter: FAILED to fetch temporary share payload for ID \(shareId): \(error)")
            }
        }
    }
    
    // --- Handles permanent, public collection links ---
    private static func handlePermanentCollectionShare(pathComponents: [String], navigation: NavigationCoordinator) {
        // Expected path: ["c", "{userID}", "{collectionID}"]
        guard pathComponents.count == 3 else { return }
        let userId = pathComponents[1]
        let collectionId = pathComponents[2]
        print("  - Found permanent collection link for user: \(userId), collection: \(collectionId)")
        
        Task {
            do {
                // This single function now contains all the logic for fetching the data
                let payload = try await fetchPublicCollection(userId: userId, collectionId: collectionId)
                print("✅ DeepLinkRouter: Successfully fetched PERMANENT COLLECTION payload.")
                await MainActor.run {
                    navigation.incomingSharedCollectionPayload = payload
                }
            } catch {
                print("❌ DeepLinkRouter: FAILED to fetch permanent collection payload: \(error)")
            }
        }
    }

    // --- ✅ This is now the SINGLE source of truth for fetching a public collection ---
    private static func fetchPublicCollection(userId: String, collectionId: String) async throws -> SharedCollectionPayload {
        let db = Firestore.firestore()
        
        // 1. Fetch the collection document
        let collectionDoc = try await db.collection("users").document(userId).collection("spotCollections").document(collectionId).getDocument()
        
        guard collectionDoc.exists else {
            throw URLError(.badServerResponse, userInfo: ["Reason": "Collection does not exist."])
        }
        
        let collection = try collectionDoc.data(as: SpotCollection.self)
        
        // 2. SECURITY CHECK: This is important. We only proceed if the owner marked it as public.
        guard collection.isPublic else {
            throw URLError(.userAuthenticationRequired, userInfo: ["Reason": "This collection is private."])
        }
        
        // 3. Fetch all spots that belong to this collection
        let spotsSnapshot = try await db.collection("users").document(userId).collection("spots")
            .whereField("collectionIds", arrayContains: collectionId)
            .getDocuments()
        
        // Convert the Firestore Spot models into the SharedSpotPayload models
        let spotPayloads = spotsSnapshot.documents.compactMap { doc -> SharedSpotPayload? in
            guard let spot = try? doc.data(as: Spot.self) else { return nil }
            return SharedSpotPayload(
                name: spot.name, address: spot.address, latitude: spot.latitude,
                longitude: spot.longitude, category: spot.category.rawValue,
                phoneNumber: spot.phoneNumber, websiteURL: spot.websiteURL,
                notes: spot.notes, sourceURL: spot.sourceURL
            )
        }
        
        // 4. Build and return the final payload for the UI
        return SharedCollectionPayload(
            collectionName: collection.name,
            collectionDescription: collection.descriptionText,
            spots: spotPayloads,
            senderName: nil // Sender name isn't relevant for a permanent public link
        )
    }
}
