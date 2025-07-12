//
//  SpotViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI
import FirebaseFirestore
import CoreLocation

@MainActor
class SpotViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var spots: [Spot] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var spotsListenerRegistration: ListenerRegistration?

    deinit {
        spotsListenerRegistration?.remove()
    }

    // MARK: - Firestore Path Helper
    private func userSpotsCollection(userId: String) -> CollectionReference {
        return db.collection("users").document(userId).collection("spots")
    }

    // MARK: - Data Fetching
    func listenForSpots(userId: String) {
        guard !userId.isEmpty else {
            self.errorMessage = "User ID is missing. Cannot fetch spots."
            self.isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        spotsListenerRegistration?.remove()

        spotsListenerRegistration = userSpotsCollection(userId: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                // Ensure UI updates happen on main thread
                Task { @MainActor in
                    guard let self = self else { return }
                    defer { self.isLoading = false }

                    if let error = error {
                        self.errorMessage = "Failed to fetch spots: \(error.localizedDescription)"
                        return
                    }

                    guard let documents = querySnapshot?.documents else {
                        self.errorMessage = "No spots data found."
                        self.spots = []
                        return
                    }
                    
                    // Single decoding pass with logging
                    var tempDecodedSpots: [Spot] = []
                    var hasDecodingErrors = false

                    for document in documents {
                        do {
                            let decodedSpot = try document.data(as: Spot.self)
                            tempDecodedSpots.append(decodedSpot)
                        } catch {
                            hasDecodingErrors = true
                        }
                    }
                    
                    // ✅ IMPROVEMENT: Check if data actually changed before updating
                    if !self.spotsAreEqual(tempDecodedSpots, self.spots) {
                        self.spots = tempDecodedSpots
                        print("SpotViewModel: Spots array updated from Firestore listener. Count: \(self.spots.count)")
                    } else {
                        print("SpotViewModel: Firestore listener fired but no actual changes detected.")
                    }
                    
                    // Handle error messages
                    if hasDecodingErrors && !tempDecodedSpots.isEmpty {
                        self.errorMessage = nil
                    } else if hasDecodingErrors && tempDecodedSpots.isEmpty {
                        self.errorMessage = "Could not process any spot data."
                    } else {
                        self.errorMessage = nil
                    }
                }
            }
    }

    // MARK: - Data Modification
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
        forFirestore.createdAt = nil
        var newDocumentRef: DocumentReference?
        
        do {
            newDocumentRef = try userSpotsCollection(userId: forFirestore.userId).addDocument(from: forFirestore) { [weak self] error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.isLoading = false
                        self.errorMessage = "Failed to add spot: \(error.localizedDescription)"
                        completion(.failure(error))
                    } else {
                        if let docId = newDocumentRef?.documentID {
                            // ✅ IMPROVEMENT: Let the Firestore listener handle the update instead of optimistic update
                            // This prevents potential race conditions and ensures consistency
                            print("SpotViewModel: Spot '\(spotToAdd.name)' added successfully. ID: \(docId). Firestore listener will update the local array.")
                            
                            self.isLoading = false
                            completion(.success(docId))
                        } else {
                            self.isLoading = false
                            self.errorMessage = "Failed to get document ID after adding spot."
                            completion(.failure(SpotError.unknown))
                        }
                    }
                }
            }
        } catch {
            self.isLoading = false
            self.errorMessage = "Error preparing spot data for save: \(error.localizedDescription)"
            completion(.failure(error))
        }
    }
    
    func addMultipleSpots(_ spots: [Spot], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let firstSpot = spots.first else {
            // Nothing to save, so we're successful.
            completion(.success(()))
            return
        }
        
        let userId = firstSpot.userId
        let batch = db.batch()

        // We create a temporary array to hold the new spots with their final IDs
        var spotsWithIDs: [Spot] = []

        for var spot in spots {
            let docRef = userSpotsCollection(userId: userId).document()
            spot.id = docRef.documentID // Assign the new ID
            
            // Add the operation to the batch
            do {
                try batch.setData(from: spot, forDocument: docRef)
                spotsWithIDs.append(spot) // Keep track of the final spot data
            } catch {
                completion(.failure(SpotError.encodingError(description: error.localizedDescription)))
                return
            }
        }

        // Commit the batch
        batch.commit { error in
            // Because the ViewModel is @MainActor, this closure is on the main thread.
            if let error = error {
                print("ERROR: Batch write failed: \(error.localizedDescription)")
                self.errorMessage = "Failed to save spots: \(error.localizedDescription)"
                completion(.failure(error))
            } else {
                print("SUCCESS: Batch write of \(spots.count) spots completed.")
                self.errorMessage = nil
                completion(.success(()))
            }
        }
    }

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
                        self.errorMessage = "Failed to update spot: \(error.localizedDescription)"
                        completion(.failure(error))
                    } else {
                        // ✅ THIS IS THE CRITICAL FIX ✅
                        // The database write was successful. Now, update our local data to match.
                        
                        // 1. Find the index of the spot that was just updated.
                        if let index = self.spots.firstIndex(where: { $0.id == spotId }) {
                            // 2. Replace the old data at that index with the new, updated data.
                            self.spots[index] = finalSpotToUpdate
                            print("SpotViewModel: Successfully updated '\(finalSpotToUpdate.name)' in local array.")
                        } else {
                            // This case is unlikely but good to handle.
                            // It means the spot was updated but wasn't in our local list,
                            // so we can add it. Or just log it.
                            print("SpotViewModel: Spot with ID \(spotId) was updated in Firestore but not found in the local array.")
                            // Optionally, you could append it: self.spots.append(finalSpotToUpdate)
                        }
                        
                        // 3. Signal success to the calling view.
                        completion(.success(()))
                    }
                }
            }
        } catch {
            self.isLoading = false
            self.errorMessage = "Error preparing spot data for update: \(error.localizedDescription)"
            completion(.failure(error))
        }
    }

    func deleteSpot(_ spotToDelete: Spot, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let spotId = spotToDelete.id else {
            completion(.failure(SpotError.missingSpotID))
            return
        }
        isLoading = true
        errorMessage = nil
        
        userSpotsCollection(userId: spotToDelete.userId).document(spotId).delete { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Failed to delete spot: \(error.localizedDescription)"
                    completion(.failure(error))
                } else {
                    // ✅ IMPROVEMENT: Let Firestore listener handle removal for consistency
                    print("SpotViewModel: Spot '\(spotToDelete.name)' deleted from Firestore. Firestore listener will update local array.")
                    completion(.success(()))
                }
            }
        }
    }

    func stopListeningAndClearData() {
        print("SpotViewModel: Stopping listener and clearing data.")
        spotsListenerRegistration?.remove()
        spotsListenerRegistration = nil
        spots = []
        errorMessage = nil
        isLoading = false
    }
    
    // MARK: - Helper Methods
    
    /// ✅ NEW: Compare two spot arrays to detect actual changes
    private func spotsAreEqual(_ spots1: [Spot], _ spots2: [Spot]) -> Bool {
        guard spots1.count == spots2.count else { return false }
        
        // Sort both arrays by ID for comparison
        let sorted1 = spots1.sorted { ($0.id ?? "") < ($1.id ?? "") }
        let sorted2 = spots2.sorted { ($0.id ?? "") < ($1.id ?? "") }
        
        for (spot1, spot2) in zip(sorted1, sorted2) {
            if !spotsAreEqual(spot1, spot2) {
                return false
            }
        }
        return true
    }
    
    /// ✅ NEW: Compare two individual spots
    private func spotsAreEqual(_ spot1: Spot, _ spot2: Spot) -> Bool {
        return spot1.id == spot2.id &&
               spot1.name == spot2.name &&
               spot1.address == spot2.address &&
               spot1.latitude == spot2.latitude &&
               spot1.longitude == spot2.longitude &&
               spot1.category == spot2.category &&
               spot1.sourceURL == spot2.sourceURL &&
               spot1.phoneNumber == spot2.phoneNumber &&
               spot1.websiteURL == spot2.websiteURL &&
               spot1.collectionId == spot2.collectionId &&
               spot1.wantsNearbyNotification == spot2.wantsNearbyNotification &&
               abs(spot1.notificationRadiusMeters - spot2.notificationRadiusMeters) < 0.1 &&
               spot1.createdAt?.dateValue() == spot2.createdAt?.dateValue()
    }
    
    /// ✅ NEW: Get a specific spot by ID (useful for other views)
    func getSpot(withId spotId: String) -> Spot? {
        return spots.first { $0.id == spotId }
    }
    
    /// ✅ NEW: Force refresh from Firestore (useful for debugging)
    func forceRefresh(userId: String) {
        print("SpotViewModel: Force refresh requested")
        stopListeningAndClearData()
        listenForSpots(userId: userId)
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
