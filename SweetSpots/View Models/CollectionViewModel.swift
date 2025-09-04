//
//  CollectionViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-04.
//

import SwiftUI
import FirebaseFirestore

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
class CollectionViewModel: ObservableObject {
    
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
        collectionsListenerRegistration?.remove()
    }

    // Helper to get the path to a user's spotCollections subcollection
    private func userCollectionsRef(userId: String) -> CollectionReference {
        return db.collection("users").document(userId).collection("spotCollections")
    }

    /// Fetches all collections for the specified `userId` and listens for real-time updates.
    func fetchCollections(userId: String) {
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
                        print("CollectionViewModel: Error fetching collections: \(error.localizedDescription)")
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
                            print("CollectionViewModel: Decoded collection '\(collection.name)' (ID: \(collection.id ?? "nil"))")
                        } catch {
                            print("CollectionViewModel: Error decoding collection \(document.documentID): \(error.localizedDescription). Data: \(document.data())")
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
                    
                    print("CollectionViewModel: Collections array updated. Count: \(self.collections.count)")
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
            
            print("CollectionViewModel: Successfully added collection '\(trimmedName)' with ID: \(newId)")
            
            // Return the new ID on success.
            return newId
            
        } catch {
            print("ERROR: Failed to add collection to Firestore: \(error.localizedDescription)")
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
        
        // --- CORRECTED LOGIC ---
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
        
        // 3. Use `updateData` instead of `setData(from:merge:)`
        docRef.updateData(updateData) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    print("CollectionViewModel: Failed to update collection '\(trimmedName)': \(error.localizedDescription)")
                    completion(.failure(CollectionError.firestoreError(underlyingError: error)))
                } else {
                    print("CollectionViewModel: Successfully updated collection '\(trimmedName)'")
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
        allSpots: [Spot], // We need all spots to find the ones to update
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let collectionId = collection.id, !collection.userId.isEmpty else {
            completion(.failure(CollectionError.missingIDs))
            return
        }
        
        isLoading = true
        
        // **CORRECTED:** Find spots where `collectionIds` array contains the ID
        let spotsToUpdate = allSpots.filter { $0.collectionIds.contains(collectionId) }
        
        Task {
            do {
                // First, handle all the associated spot updates in a batch
                try await handleSpotUpdates(
                    for: mode,
                    spots: spotsToUpdate,
                    collectionIdToRemove: collectionId,
                    userId: collection.userId
                )
                
                // If spot updates succeed, delete the collection document itself
                try await deleteCollectionDocument(collection)
                
                // If everything succeeds, complete on the main thread
                self.isLoading = false
                completion(.success(()))
                
            } catch {
                // If any step fails, report the error
                self.isLoading = false
                completion(.failure(error))
            }
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
                // **CORRECTED:** Use FieldValue.arrayRemove to pull the ID from the array
                batch.updateData(["collectionIds": FieldValue.arrayRemove([collectionIdToRemove])], forDocument: docRef)
                
            case .collectionAndSpots:
                // Soft-delete the spot by setting the deletedAt timestamp
                batch.updateData(["deletedAt": Timestamp(date: Date())], forDocument: docRef)
            }
        }
        
        // Asynchronously commit the batch and throw an error if it fails
        try await batch.commit()
    }

    // 4. New private helper to just delete the Firestore document
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
        print("CollectionViewModel: Detached collections listener.")
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

enum FirestoreWrapperError: Error, LocalizedError {
    case unexpectedNilReference
    
    var errorDescription: String? {
        "An unexpected error occurred while communicating with the database."
    }
}

extension CollectionReference {
    /// A modern async/await wrapper for adding a document that correctly handles all error paths.
    @discardableResult
    func addDocument<T: Encodable>(from data: T) async throws -> DocumentReference {
        try await withCheckedThrowingContinuation { continuation in
            var ref: DocumentReference?
            
            do {
                // The call to addDocument(from:completion:) can itself throw an
                // encoding error, so we must wrap it in a `do-catch`.
                ref = try self.addDocument(from: data) { error in
                    if let error = error {
                        // This handles network errors from the completion handler.
                        continuation.resume(throwing: error)
                    } else if let ref = ref {
                        // This handles the success case.
                        continuation.resume(returning: ref)
                    } else {
                        // This handles the unlikely case of no error and no reference.
                        continuation.resume(throwing: FirestoreWrapperError.unexpectedNilReference)
                    }
                }
            } catch {
                // This handles encoding errors thrown synchronously by `addDocument`.
                continuation.resume(throwing: error)
            }
        }
    }
}
