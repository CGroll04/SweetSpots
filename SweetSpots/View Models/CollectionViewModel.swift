//
//  CollectionViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-04.
//

import SwiftUI
import FirebaseFirestore
import os.log

// MARK: - Collection Error Types
enum CollectionError: LocalizedError {
    case emptyName
    case duplicateName
    case invalidDataForUpdate
    case missingIDs
    case encodingError(underlyingError: Error)
    case firestoreError(underlyingError: Error)
    case spotUpdateFailed(details: String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Collection name cannot be empty."
        case .duplicateName:
            return "A collection with this name already exists."
        case .invalidDataForUpdate:
            return "Invalid collection data provided for update."
        case .missingIDs:
            return "Collection ID or User ID missing, cannot perform operation."
        case .encodingError(let underlyingError):
            return "Failed to encode collection data: \(underlyingError.localizedDescription)"
        case .firestoreError(let underlyingError):
            return "A database error occurred: \(underlyingError.localizedDescription)"
        case .spotUpdateFailed(let details):
            return "Collection deleted, but failed to update some associated spots: \(details)"
        }
    }
}

@MainActor
/// Manages the state and operations for user-created collections of spots.
class CollectionViewModel: ObservableObject {
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "CollectionViewModel")
    
    public enum DeletionMode {
            case collectionOnly // Uncategorize spots
            case collectionAndSpots // Delete spots as well
        }
    
    @Published var collections: [SpotCollection] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()
    private var collectionsListenerRegistration: ListenerRegistration?

    // Deinitializer to remove listener
    deinit {
        logger.debug("CollectionViewModel deinitialized, listener removed.")
        collectionsListenerRegistration?.remove()
    }

    // Helper to get the path to a user's spotCollections subcollection
    private func userCollectionsRef(userId: String) -> CollectionReference {
        return db.collection("users").document(userId).collection("spotCollections")
    }

    /// Fetches all collections for the specified `userId` and listens for real-time updates.
    func listenForCollections(userId: String) {
        guard !userId.isEmpty else {
            self.errorMessage = "User ID is missing. Cannot fetch collections."
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        collectionsListenerRegistration?.remove()

        collectionsListenerRegistration = userCollectionsRef(userId: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    defer { self.isLoading = false }

                    if let error = error {
                        self.errorMessage = "Error fetching collections: \(error.localizedDescription)"
                        logger.error("Error fetching collections: \(error.localizedDescription)")
                        return
                    }

                    guard let documents = querySnapshot?.documents else {
                        self.errorMessage = "No collections found."
                        self.collections = []
                        return
                    }
                    
                    var decodedCollections: [SpotCollection] = []
                    var hasDecodingErrors = false
                    
                    for document in documents {
                        do {
                            let collection = try document.data(as: SpotCollection.self)
                            decodedCollections.append(collection)
                            logger.debug("Decoded collection '\(collection.name)' (ID: \(collection.id ?? "nil"))")
                        } catch {
                            logger.warning("Error decoding collection \(document.documentID): \(error.localizedDescription).")
                            hasDecodingErrors = true
                        }
                    }
                    
                    self.collections = decodedCollections
                    
                    // Handle error messages
                    if hasDecodingErrors && !decodedCollections.isEmpty {
                        self.errorMessage = nil // Some collections loaded successfully
                    } else if hasDecodingErrors && decodedCollections.isEmpty {
                        self.errorMessage = "Could not process any collection data."
                    } else {
                        self.errorMessage = nil
                    }
                    
                    logger.info("Collections listener updated. Total collections: \(self.collections.count)")
                }
            }
    }

    /// Adds a new collection for the specified user.
    func addCollection(name: String, userId: String, description: String? = nil) async throws -> String {
        guard let trimmedName = name.trimmed() else {
            throw CollectionError.emptyName
        }

        if isDuplicateCollectionName(trimmedName, for: userId) {
            throw CollectionError.duplicateName
        }

        let finalDescription = description?.trimmed()
        var newCollection = SpotCollection(userId: userId, name: trimmedName, descriptionText: finalDescription)
        
        do {
            let documentReference = try await userCollectionsRef(userId: userId).addDocument(from: newCollection)
            
            let newId = documentReference.documentID
            
            // Perform the optimistic update to the local array.
            newCollection.id = newId
            newCollection.createdAt = Timestamp(date: Date())
            
            self.collections.insert(newCollection, at: 0)
            
            logger.info("Successfully added collection '\(trimmedName)' with ID: \(newId)")
            
            // Return the new ID on success.
            return newId
            
        } catch {
            logger.error("Failed to add collection to Firestore: \(error.localizedDescription)")
            throw CollectionError.firestoreError(underlyingError: error)
        }
    }

    /// Updates an existing collection.
    func updateCollection(_ collection: SpotCollection, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let collectionId = collection.id, !collection.userId.isEmpty else {
            completion(.failure(CollectionError.invalidDataForUpdate))
            return
        }
        
        guard let trimmedName = collection.name.trimmed() else {
            completion(.failure(CollectionError.emptyName))
            return
        }
        
        if isDuplicateCollectionName(trimmedName, for: collection.userId, excluding: collectionId) {
            completion(.failure(CollectionError.duplicateName))
            return
        }
        
        isLoading = true
        
        // 1. Manually create a dictionary to ensure we can handle field deletion.
        var updateData: [String: Any] = [
            "name": trimmedName
        ]
        
        // 2. If the description is present, add it. If it's nil or an empty string,
        //    explicitly tell Firestore to delete the field.
        if let description = collection.descriptionText?.trimmed() {
            updateData["descriptionText"] = description
        } else {
            updateData["descriptionText"] = FieldValue.delete()
        }
        
        let docRef = userCollectionsRef(userId: collection.userId).document(collectionId)
        docRef.updateData(updateData) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    logger.error("Failed to update collection '\(trimmedName)': \(error.localizedDescription)")
                    completion(.failure(CollectionError.firestoreError(underlyingError: error)))
                } else {
                    logger.info("Successfully updated collection '\(trimmedName)'")
                    // Note: The local listener will automatically handle the UI update.
                    completion(.success(()))
                }
            }
        }
    }

    /// Deletes a collection and optionally updates associated spots to remove their collectionId.
    func deleteCollection(
        _ collection: SpotCollection,
        mode: DeletionMode,
        allSpots: [Spot]
    ) async throws { // Changed to async throws, removed completion handler
        guard let collectionId = collection.id, !collection.userId.isEmpty else {
            throw CollectionError.missingIDs
        }
        
        // This logic is now cleaner with async/await
        isLoading = true
        
        let spotsToUpdate = allSpots.filter { $0.collectionIds.contains(collectionId) }
        
        // Use a do-catch block to handle errors
        do {
            try await handleSpotUpdates(
                for: mode,
                spots: spotsToUpdate,
                collectionIdToRemove: collectionId,
                userId: collection.userId
            )
            
            try await deleteCollectionDocument(collection)
            
            // On success, simply finish the function
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            // If any step fails, throw the error
            await MainActor.run {
                self.isLoading = false
            }
            throw error // The calling view will catch this
        }
    }
    
    /// Private helper to perform batch updates/deletes on spots.
    private func handleSpotUpdates(
        for mode: DeletionMode,
        spots: [Spot],
        collectionIdToRemove: String,
        userId: String
    ) async throws {
        guard !spots.isEmpty else {
            // No spots to update, so this step is successful.
            return
        }
        
        let batch = db.batch()
        let spotsRef = db.collection("users").document(userId).collection("spots")

        for spot in spots {
            guard let spotId = spot.id else { continue }
            let docRef = spotsRef.document(spotId)
            
            switch mode {
            case .collectionOnly:
                batch.updateData(["collectionIds": FieldValue.arrayRemove([collectionIdToRemove])], forDocument: docRef)
                
            case .collectionAndSpots:
                // Soft-delete the spot by setting the deletedAt timestamp
                batch.updateData(["deletedAt": Timestamp(date: Date())], forDocument: docRef)
            }
        }
        
        // Asynchronously commit the batch and throw an error if it fails
        try await batch.commit()
    }
    private func deleteCollectionDocument(_ collection: SpotCollection) async throws {
        guard let collectionId = collection.id else {
            throw CollectionError.missingIDs
        }
        
        do {
            try await userCollectionsRef(userId: collection.userId).document(collectionId).delete()
        } catch {
            throw CollectionError.firestoreError(underlyingError: error)
        }
    }

    /// Detaches the Firestore listener for collections.
    func detachCollectionsListener() {
        collectionsListenerRegistration?.remove()
        collectionsListenerRegistration = nil
        logger.info("Detached collections listener.")
    }
    
    /// Checks if a collection name is a duplicate for the given user
    private func isDuplicateCollectionName(_ name: String, for userId: String, excluding excludeId: String? = nil) -> Bool {
        return collections.contains { collection in
            collection.userId == userId &&
            collection.id != excludeId &&
            collection.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
    
    /// Gets a collection by ID
    func getCollection(withId collectionId: String) -> SpotCollection? {
        return collections.first { $0.id == collectionId }
    }
    
    /// Gets all collections for a specific user
    func getCollections(for userId: String) -> [SpotCollection] {
        return collections.filter { $0.userId == userId }
    }
    
    /// Counts spots in a collection (requires SpotViewModel)
    func getSpotCount(for collectionId: String, from spotsViewModel: SpotViewModel) -> Int {
        return spotsViewModel.spots.filter { $0.collectionIds.contains(collectionId) }.count
    }
    
    /// Validates collection name
    func isValidCollectionName(_ name: String) -> Bool {
        guard let trimmedName = name.trimmed() else { return false }
        return trimmedName.count >= 1 && trimmedName.count <= 50 // Reasonable limits
    }
    
    /// Validates collection description
    func isValidCollectionDescription(_ description: String?) -> Bool {
        guard let description = description else { return true } // nil is valid
        guard let trimmedDescription = description.trimmed() else { return true } // empty after trim is valid
        return trimmedDescription.count <= 500 // Reasonable limit
    }
}


