// SpotShareManager.swift

import Foundation
import FirebaseFunctions
import FirebaseFirestore
import os.log

enum SpotShareManager {

    private static let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SpotShareManager")
    private static let functions = Functions.functions()

    // MARK: - New enum to define what's being shared
    enum ShareableItem {
        case spot(id: String)
        case collection(id: String)
    }

    /// Creates a temporary, private share link by generating a signed token via a Cloud Function.
    static func makePrivateShareURL(for item: ShareableItem) async throws -> URL {
        let (type, id): (String, String)
        
        switch item {
        case .spot(let spotId):
            type = "spot"
            id = spotId
        case .collection(let collectionId):
            type = "collection"
            id = collectionId
        }

        do {
            // Call the Cloud Function to generate a secure token
            let result = try await functions.httpsCallable("generateShareToken").call([
                "targetType": type,
                "targetId": id
            ])
            
            guard let token = (result.data as? [String: Any])?["token"] as? String else {
                throw URLError(.cannotParseResponse)
            }
            
            logger.info("Successfully generated private share token.")
            
            // Build the URL containing the new stateless token
            let urlString = "https://sweetspotsshare.netlify.app/s/t/\(token)"
            guard let url = URL(string: urlString) else {
                throw URLError(.badURL)
            }
            return url

        } catch {
            logger.error("Failed to generate share token: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Creates a permanent, public link for a collection. This function remains the same.
    static func makePublicCollectionShareURL(for collection: SpotCollection) async throws -> URL {
        guard let collectionId = collection.id, !collection.userId.isEmpty else {
            throw URLError(.badURL)
        }
        
        let db = Firestore.firestore()
        let collectionRef = db.collection("users").document(collection.userId).collection("spotCollections").document(collectionId)
        try await collectionRef.updateData(["isPublic": true])
        
        // The permanent URL that points directly to the data
        let urlString = "https://sweetspotsshare.netlify.app/c/\(collection.userId)/\(collectionId)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        logger.info("Successfully created permanent public link for collection: \(collectionId)")
        return url
    }
}
