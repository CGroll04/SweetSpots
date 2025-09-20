//
//  DeepLinkRouter.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-25.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import os.log

/// A static router responsible for parsing and handling incoming deep link URLs.
enum DeepLinkRouter {
    static let allowedHosts: Set<String> = ["sweetspotsshare.netlify.app", "localhost"]
    private static let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "DeepLinkRouter")
    
    private static var lastHandledURL: URL?
    private static var lastHandledTime: Date?

    static func handle(url: URL, navigation: NavigationCoordinator) {
        // 1. De-bouncing logic (This part is correct)
        if let lastURL = lastHandledURL, let lastTime = lastHandledTime,
           url == lastURL && Date().timeIntervalSince(lastTime) < 2.0 {
            logger.debug("Ignoring duplicate URL handled within 2s.")
            return
        }
        lastHandledURL = url
        lastHandledTime = Date()
        
        // 2. Get URL components
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            logger.warning("Could not create URL components from URL: \(url.absoluteString)")
            return
        }
        
        // 3. --- CORRECTED ROUTING LOGIC ---
        // First, check if it's our custom app scheme.
        if comps.scheme == "sweetspotsapp" {
            handleAppScheme(components: comps, navigation: navigation)
        
        // If not, THEN check if it's a valid Universal Link host.
        } else if let host = comps.host, allowedHosts.contains(host) {
            handleUniversalLink(components: comps, navigation: navigation)
            
        // Otherwise, it's an unknown URL.
        } else {
            logger.warning("URL is from an unknown source: \(url.absoluteString)")
        }
    }
    
    private static func handleUniversalLink(components: URLComponents, navigation: NavigationCoordinator) {
        let pathComponents = components.path.split(separator: "/").map(String.init)
        guard let routeType = pathComponents.first else {
            logger.warning("Universal Link path is empty.")
            return
        }
        
        switch routeType {
        case "s":
            handleTemporaryShare(pathComponents: pathComponents, navigation: navigation)
        case "c":
            handlePermanentCollectionShare(pathComponents: pathComponents, navigation: navigation)
        default:
            logger.warning("Unknown Universal Link route type '\(routeType)'.")
        }
    }
    
    
    // Your new function for the app scheme
    private static func handleAppScheme(components: URLComponents, navigation: NavigationCoordinator) {
        guard components.host == "addSpotFromShare",
              let sourceURLString = components.queryItems?.first(where: { $0.name == "sourceURL" })?.value,
              let url = URL(string: sourceURLString)
        else {
            logger.warning("Could not parse app scheme URL: \(components.url?.absoluteString ?? "N/A")")
            return
        }
        
        Task { @MainActor in
            // This will trigger the .onChange in MainTabView
            navigation.incomingSharedURL = url
        }
    }
    
    /// Handles temporary shares for both individual spots and collections from the `/s/` path.
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
                    logger.info("Successfully fetched temporary spot payload for shareID: \(shareId)")
                    await MainActor.run { navigation.incomingSharedPayload = payload }
                } else if shareType == "collection" {
                    let payload = try doc.data(as: SharedCollectionPayload.self)
                    logger.info("Successfully fetched temporary collection payload for shareID: \(shareId)")
                    await MainActor.run { navigation.incomingSharedCollectionPayload = payload }
                }
            } catch {
                logger.error("Failed to fetch temporary share payload for ID \(shareId): \(error.localizedDescription)")
            }
        }
    }
    
    /// Handles permanent, public collection links from the /c/ path.
    private static func handlePermanentCollectionShare(pathComponents: [String], navigation: NavigationCoordinator) {
        // Expected path: ["c", "{userID}", "{collectionID}"]
        guard pathComponents.count == 3 else { return }
        let userId = pathComponents[1]
        let collectionId = pathComponents[2]
        logger.info("Handling permanent collection link for user: \(userId), collection: \(collectionId)")
        
        Task {
            do {
                // This single function now contains all the logic for fetching the data
                let payload = try await fetchPublicCollection(userId: userId, collectionId: collectionId)
                logger.info("Successfully fetched permanent collection payload.")
                await MainActor.run {
                    navigation.incomingSharedCollectionPayload = payload
                }
            } catch {
                logger.error("Failed to fetch permanent collection payload: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches a public collection and its associated spots to create a shareable payload.
    ///
    /// This function performs a security check to ensure the collection is marked as public before returning any data.
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
