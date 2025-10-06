// DeepLinkRouter.swift

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import os.log

/// A static router responsible for parsing and handling incoming deep link URLs.
enum DeepLinkRouter {
    static let allowedHosts: Set<String> = ["sweetspotsshare.netlify.app", "localhost"]
    private static let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "DeepLinkRouter")
    
    private static var lastHandledURL: URL?
    private static var lastHandledTime: Date?

    static func handle(url: URL, navigation: NavigationCoordinator) {
        // De-bouncing logic
        if let lastURL = lastHandledURL, let lastTime = lastHandledTime,
           url == lastURL && Date().timeIntervalSince(lastTime) < 2.0 {
            logger.debug("Ignoring duplicate URL handled within 2s.")
            return
        }
        lastHandledURL = url
        lastHandledTime = Date()
        
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            logger.warning("Could not create URL components from URL: \(url.absoluteString)")
            return
        }
        
        if comps.scheme == "sweetspotsapp" {
            handleAppScheme(components: comps, navigation: navigation)
        } else if let host = comps.host, allowedHosts.contains(host) {
            handleUniversalLink(components: comps, navigation: navigation)
        } else {
            logger.warning("URL is from an unknown source: \(url.absoluteString)")
        }
    }
    
    private static func handleUniversalLink(components: URLComponents, navigation: NavigationCoordinator) {
        let pathComponents = components.path.split(separator: "/").map(String.init)
        guard let routeType = pathComponents.first else { return }
        
        switch routeType {
        case "s":
            handleTemporaryShare(pathComponents: pathComponents, navigation: navigation)
        case "c":
            handlePermanentCollectionShare(pathComponents: pathComponents, navigation: navigation)
        default:
            logger.warning("Unknown Universal Link route type '\(routeType)'.")
        }
    }
    
    private static func handleAppScheme(components: URLComponents, navigation: NavigationCoordinator) {
        guard components.host == "addSpotFromShare",
              let sourceURLString = components.queryItems?.first(where: { $0.name == "sourceURL" })?.value,
              let url = URL(string: sourceURLString)
        else {
            logger.warning("Could not parse app scheme URL: \(components.url?.absoluteString ?? "N/A")")
            return
        }
        
        Task { @MainActor in
            navigation.incomingSharedURL = url
        }
    }
    
    /// Handles temporary shares by verifying a JWT and fetching the data.
    private static func handleTemporaryShare(pathComponents: [String], navigation: NavigationCoordinator) {
        // Expected path: ["s", "t", "{jwt_token}"]
        guard pathComponents.count == 3, pathComponents[1] == "t" else { return }
        let token = pathComponents[2]
        
        Task {
            do {
                let functions = Functions.functions()
                let result = try await functions.httpsCallable("verifyAndFetchSharedData").call(["token": token])
                
                guard let responseData = result.data as? [String: Any],
                      let type = responseData["type"] as? String,
                      let data = responseData["data"] as? [String: Any] else {
                    logger.error("Could not parse response from verification function.")
                    return
                }

                // Decode the data from the dictionary back into our Swift models
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                let decoder = JSONDecoder()

                if type == "spot" {
                    let payload = try decoder.decode(SharedSpotPayload.self, from: jsonData)
                    logger.info("Successfully fetched temporary spot payload via token.")
                    await MainActor.run { navigation.incomingSharedPayload = payload }
                } else if type == "collection" {
                    let payload = try decoder.decode(SharedCollectionPayload.self, from: jsonData)
                    logger.info("Successfully fetched temporary collection payload via token.")
                    await MainActor.run { navigation.incomingSharedCollectionPayload = payload }
                }
            } catch {
                logger.error("Failed to verify and fetch share data for token: \(error.localizedDescription)")
                // TODO: You could show an "Invalid or Expired Link" error to the user here.
            }
        }
    }

    /// Handles permanent, public collection links from the /c/ path.
    private static func handlePermanentCollectionShare(pathComponents: [String], navigation: NavigationCoordinator) {
        guard pathComponents.count == 3 else { return }
        let userId = pathComponents[1]
        let collectionId = pathComponents[2]
        logger.info("Handling permanent collection link for user: \(userId), collection: \(collectionId)")
        
        Task {
            do {
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
        )
    }
}
