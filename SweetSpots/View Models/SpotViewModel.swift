//
//  SpotViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI
@preconcurrency import FirebaseFirestore
import CoreLocation
import FirebaseAuth
import Combine
import os.log

@MainActor
class SpotViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SpotViewModel")

    // MARK: - Published Properties
    @Published var spots: [Spot] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var recentlyDeletedSpots: [Spot] = []
    @Published var userSession: FirebaseAuth.User?
    
    private var suppressedUndoSpotIds: Set<String> = []

    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var spotsListenerRegistration: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()

    init(authViewModel: AuthViewModel) {
        // Subscribe to the userSession publisher from the AuthViewModel
        authViewModel.$userSession
            .sink { [weak self] session in
                self?.userSession = session
                self?.logger.info("User session changed. User is now \(session == nil ? "logged out" : "logged in").")
                
                // If the user logs in, fetch their spots.
                // If they log out (session is nil), clear the data.
                if let user = session {
                    self?.logger.info("Initializing spots listener for user ID: \(user.uid)")
                    self?.listenForSpots(userId: user.uid)
                } else {
                    self?.logger.info("User logged out, clearing spot data.")
                    self?.stopListeningAndClearData()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        logger.debug("SpotViewModel deinitialized, listener removed.")
        spotsListenerRegistration?.remove()
    }

    // MARK: - Firestore Path Helper
    private func userSpotsCollection(userId: String) -> CollectionReference {
        return db.collection("users").document(userId).collection("spots")
    }

    // MARK: - Data Fetching
    /// Establishes a real-time listener for all of a user's spots (both active and soft-deleted).
    func listenForSpots(userId: String) {
        guard !userId.isEmpty else {
            logger.error("Cannot listen for spots: User ID is missing.")
            self.errorMessage = "User ID is missing."
            return
        }
        isLoading = true
        spotsListenerRegistration?.remove()

        userSpotsCollection(userId: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.logger.error("Error fetching spots: \(error.localizedDescription)")
                        self.errorMessage = "Error fetching spots: \(error.localizedDescription)"
                        self.isLoading = false
                        return
                    }
                    
                    guard let documents = querySnapshot?.documents else {
                        self.logger.info("Snapshot returned no documents.")
                        self.isLoading = false
                        return
                    }
                    
                    let allSpots = documents.compactMap { document -> Spot? in
                        do {
                            var spot = try document.data(as: Spot.self)
                            spot.id = document.documentID
                            return spot
                        } catch {
                            self.logger.warning("Failed to decode spot \(document.documentID): \(error.localizedDescription)")
                            return nil
                        }
                    }
                    
                    self.spots = allSpots.filter { $0.deletedAt == nil }
                    self.recentlyDeletedSpots = allSpots.filter { $0.deletedAt != nil }
                    
                    self.logger.info("Spot listener updated. Loaded \(self.spots.count) active and \(self.recentlyDeletedSpots.count) deleted spots.")
                    self.isLoading = false
                }
            }
    }

    // MARK: - Data Modification
    
    /// Adds a single new spot to Firestore.
    func addSpot(
        spotData: Spot,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        isLoading = true
        errorMessage = nil

        var spotToAdd = spotData
        if let urlStr = spotToAdd.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !urlStr.isEmpty {
            spotToAdd.sourceURL = urlStr
        } else {
            spotToAdd.sourceURL = nil
        }
        spotToAdd.phoneNumber = spotToAdd.phoneNumber?.trimmed()
        spotToAdd.websiteURL = spotToAdd.websiteURL?.trimmed()
        
        var forFirestore = spotToAdd
        forFirestore.createdAt = nil // Let the server set the timestamp
        var newDocumentRef: DocumentReference?
        
        do {
            newDocumentRef = try userSpotsCollection(userId: forFirestore.userId).addDocument(from: forFirestore) { [weak self] error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.isLoading = false
                        self.logger.error("Failed to add spot to Firestore: \(error.localizedDescription)")
                        self.errorMessage = "Failed to add spot: \(error.localizedDescription)"
                        completion(.failure(error))
                    } else {
                        if let docId = newDocumentRef?.documentID {
                            self.logger.info("Spot '\(spotToAdd.name)' added successfully. ID: \(docId).")
                            self.isLoading = false
                            completion(.success(docId))
                        } else {
                            self.isLoading = false
                            let error = SpotError.unknown
                            self.logger.error("Failed to get document ID after adding spot.")
                            self.errorMessage = error.errorDescription
                            completion(.failure(error))
                        }
                    }
                }
            }
        } catch {
            self.isLoading = false
            self.logger.error("Error preparing spot data for save: \(error.localizedDescription)")
            self.errorMessage = "Error preparing spot data for save: \(error.localizedDescription)"
            completion(.failure(error))
        }
    }
    
    /// Adds multiple spots to a collection in a single batch operation.
    func addSpotsToCollection(spotIDs: Set<String>, toCollection collectionId: String) {
        guard !spotIDs.isEmpty, let userId = self.userSession?.uid else { return }

        let batch = db.batch()
        let spotsRef = userSpotsCollection(userId: userId)

        for spotId in spotIDs {
            let docRef = spotsRef.document(spotId)
            batch.updateData(["collectionIds": FieldValue.arrayUnion([collectionId])], forDocument: docRef)
        }

        batch.commit { error in
            Task { @MainActor in
                if let error = error {
                    self.logger.error("Error adding \(spotIDs.count) spots to collection \(collectionId): \(error.localizedDescription)")
                    self.errorMessage = "Failed to add spots to collection."
                } else {
                    self.logger.info("Successfully added \(spotIDs.count) spots to collection \(collectionId).")
                }
            }
        }
    }
    
    /// Adds multiple new spots to Firestore in a single batch operation.
    func addMultipleSpots(_ spots: [Spot], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let firstSpot = spots.first else {
            completion(.success(()))
            return
        }
        
        let userId = firstSpot.userId
        let batch = db.batch()

        for var spot in spots {
            let docRef = userSpotsCollection(userId: userId).document()
            spot.id = docRef.documentID
            
            do {
                try batch.setData(from: spot, forDocument: docRef)
            } catch {
                let spotError = SpotError.encodingError(description: error.localizedDescription)
                Task { @MainActor in
                    self.logger.error("Failed to encode spot '\(spot.name)' for batch write: \(spotError.localizedDescription)")
                    self.errorMessage = "Failed to save spots: \(spotError.localizedDescription)"
                    completion(.failure(spotError))
                }
                return
            }
        }

        batch.commit { error in
            Task { @MainActor in
                if let error = error {
                    self.logger.error("Batch write of \(spots.count) spots failed: \(error.localizedDescription)")
                    self.errorMessage = "Failed to save spots: \(error.localizedDescription)"
                    completion(.failure(error))
                } else {
                    self.logger.info("Batch write of \(spots.count) spots completed successfully.")
                    self.errorMessage = nil
                    completion(.success(()))
                }
            }
        }
    }

    /// Removes a specific collection ID from the `collectionIds` array for multiple spots.
    func removeSpotsFromCollection(spotIDs: Set<String>, fromCollection collectionId: String) {
        guard !spotIDs.isEmpty, let userId = self.userSession?.uid else { return }

        let batch = db.batch()
        let spotsRef = userSpotsCollection(userId: userId)

        for spotId in spotIDs {
            let docRef = spotsRef.document(spotId)
            batch.updateData(["collectionIds": FieldValue.arrayRemove([collectionId])], forDocument: docRef)
        }

        batch.commit { error in
            Task { @MainActor in
                if let error = error {
                    self.logger.error("Error removing \(spotIDs.count) spots from collection \(collectionId): \(error.localizedDescription)")
                    self.errorMessage = "Failed to remove spots from collection."
                } else {
                    self.logger.info("Successfully removed \(spotIDs.count) spots from collection \(collectionId).")
                }
            }
        }
    }
    
    /// Deletes expired temporary share documents created by the user.
    func performShareCleanup(for userId: String) {
        logger.info("Performing share cleanup for user: \(userId)")

        let db = Firestore.firestore()
        let now = Timestamp()

        db.collection("shares")
            .whereField("creatorUid", isEqualTo: userId)
            .whereField("expiresAt", isLessThan: now)
            .getDocuments { snapshot, error in
                if let error = error {
                    Task { @MainActor in
                        self.logger.error("Error getting expired shares: \(error.localizedDescription)")
                    }
                    return
                }

                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    Task { @MainActor in
                        self.logger.info("No expired shares to clean up for this user.")
                    }
                    return
                }

                Task { @MainActor in
                    self.logger.info("Found \(documents.count) expired shares to delete.")
                }
                let batch = db.batch()
                documents.forEach { doc in
                    batch.deleteDocument(doc.reference)
                }

                batch.commit { err in
                    if let err = err {
                        Task { @MainActor in
                            self.logger.error("Error deleting expired shares: \(err.localizedDescription)")
                        }
                    } else {
                        Task { @MainActor in
                            self.logger.info("Successfully cleaned up expired shares.")
                        }
                    }
                }
            }
    }
    
    /// Updates an existing spot in Firestore.
    func updateSpot(_ spotToUpdate: Spot, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let spotId = spotToUpdate.id else {
            completion(.failure(SpotError.missingSpotID))
            return
        }
        isLoading = true
        errorMessage = nil

        var finalSpotToUpdate = spotToUpdate
        if let urlStr = finalSpotToUpdate.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !urlStr.isEmpty {
            finalSpotToUpdate.sourceURL = urlStr
        } else {
            finalSpotToUpdate.sourceURL = nil
        }
        finalSpotToUpdate.phoneNumber = finalSpotToUpdate.phoneNumber?.trimmed()
        finalSpotToUpdate.websiteURL = finalSpotToUpdate.websiteURL?.trimmed()
        
        do {
            try userSpotsCollection(userId: finalSpotToUpdate.userId).document(spotId).setData(from: finalSpotToUpdate, merge: true) { [weak self] error in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isLoading = false
                    
                    if let error = error {
                        self.logger.error("Failed to update spot '\(finalSpotToUpdate.name)': \(error.localizedDescription)")
                        self.errorMessage = "Failed to update spot: \(error.localizedDescription)"
                        completion(.failure(error))
                    } else {
                        self.logger.info("Successfully updated spot '\(finalSpotToUpdate.name)' in Firestore.")
                        completion(.success(()))
                    }
                }
            }
        } catch {
            self.isLoading = false
            self.logger.error("Failed to encode spot data for update: \(error.localizedDescription)")
            self.errorMessage = "Error preparing spot data for update: \(error.localizedDescription)"
            completion(.failure(error))
        }
    }

    /// Soft-deletes a spot by setting its `deletedAt` timestamp.
    func deleteSpot(_ spotToDelete: Spot, isPermanent: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let spotId = spotToDelete.id else {
            completion(.failure(SpotError.missingSpotID))
            return
        }
        
        let docRef = userSpotsCollection(userId: spotToDelete.userId).document(spotId)
        
        let action: (WriteBatch) -> Void
        let logMessage: String
        
        if isPermanent {
            action = { batch in batch.deleteDocument(docRef) }
            logMessage = "Permanently deleting spot"
        } else {
            action = { batch in batch.updateData(["deletedAt": Timestamp(date: Date())], forDocument: docRef) }
            logMessage = "Soft-deleting spot"
        }
        
        logger.info("\(logMessage) '\(spotToDelete.name)'.")
        
        let batch = db.batch()
        action(batch)
        batch.commit { error in
            Task { @MainActor in
                if let error = error {
                    self.logger.error("Failed to delete spot: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    self.logger.info("Successfully deleted spot.")
                    completion(.success(()))
                }
            }
        }
    }
    
    /// Restores a soft-deleted spot by removing its `deletedAt` timestamp.
    func restoreSpot(_ spotToRestore: Spot) {
        guard let spotId = spotToRestore.id else {
            logger.error("Cannot restore spot: Spot ID is missing.")
            return
        }
        logger.info("Restoring spot '\(spotToRestore.name)'.")
        userSpotsCollection(userId: spotToRestore.userId)
            .document(spotId)
            .updateData(["deletedAt": FieldValue.delete()])
    }

    /// Permanently deletes a spot from Firestore. This action is irreversible.
    func permanentlyDeleteSpot(_ spotToDelete: Spot) {
        guard let spotId = spotToDelete.id else {
            logger.error("Cannot permanently delete spot: Spot ID is missing.")
            return
        }
        logger.info("Permanently deleting spot '\(spotToDelete.name)' (ID: \(spotId)).")
        userSpotsCollection(userId: spotToDelete.userId)
            .document(spotId)
            .delete()
    }
    
    /// Queries for and permanently deletes all spots that were soft-deleted more than 30 days ago.
    func purgeExpiredSpots(for userId: String) {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let thirtyDaysAgoTimestamp = Timestamp(date: thirtyDaysAgo)
        
        let db = self.db
        
        userSpotsCollection(userId: userId)
            .whereField("deletedAt", isLessThan: thirtyDaysAgoTimestamp)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    Task { @MainActor in
                        self.logger.info("No expired spots to purge.")
                    }
                    return
                }
                
                let batch = db.batch()
                Task { @MainActor in
                    self.logger.info("Purging \(documents.count) expired spots...")
                }
                documents.forEach { batch.deleteDocument($0.reference) }
                
                batch.commit { error in
                    if let error = error {
                        Task { @MainActor in
                            self.logger.error("Failed to commit batch purge of expired spots: \(error.localizedDescription)")
                        }
                    } else {
                        Task { @MainActor in
                            self.logger.info("Successfully purged \(documents.count) expired spots.")
                        }
                    }
                }
            }
    }

    /// Detaches the Firestore listener and clears all local spot data.
    func stopListeningAndClearData() {
        logger.info("Stopping listener and clearing local spot data.")
        spotsListenerRegistration?.remove()
        spotsListenerRegistration = nil
        spots = []
        recentlyDeletedSpots = []
        errorMessage = nil
        isLoading = false
    }
    
    /// Forces a re-fetch of all spot data from Firestore.
    func forceRefresh(userId: String) {
        logger.info("Force refresh requested.")
        stopListeningAndClearData()
        listenForSpots(userId: userId)
    }
    
    /// Retrieves a spot from the local array by its ID.
    func getSpot(withId spotId: String) -> Spot? {
        return spots.first { $0.id == spotId }
    }
}

// MARK: - Custom Error
enum SpotError: LocalizedError {
    case missingUserID
    case missingSpotID
    case encodingError(description: String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .missingUserID:
            return "User ID is missing. Cannot perform operation."
        case .missingSpotID:
            return "Spot ID is missing. Cannot perform operation."
        case .encodingError(let description):
            return "Failed to encode spot data: \(description)"
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

