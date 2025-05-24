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
    @Published var spots: [Spot] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?

    // Helper to get the path to a user's spots subcollection
    private func userSpotsCollection(userId: String) -> CollectionReference {
        return db.collection("users").document(userId).collection("spots")
    }

    func fetchData(userId: String) {
        isLoading = true
        listenerRegistration?.remove()

        // Now querying the subcollection: /users/{userId}/spots
        listenerRegistration = userSpotsCollection(userId: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Error fetching spots: \(error.localizedDescription)"
                    return
                }

                guard let documents = querySnapshot?.documents else {
                    self.errorMessage = "No spots found."
                    self.spots = []
                    return
                }
                
                self.spots = documents.compactMap { document -> Spot? in
                    do {
                        var spot = try document.data(as: Spot.self)
                        if spot.userId == nil { // Ensure userId is populated if missing (e.g. for older data)
                            spot.userId = userId
                        }
                        return spot
                    } catch {
                        print("Error decoding spot \(document.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }
                
                if !documents.isEmpty && self.spots.isEmpty {
                     print("WARNING: Documents received but spots array is empty. Check Spot struct decoding and Firestore data structure for /users/\(userId)/spots.")
                }
                
                if !self.spots.isEmpty || documents.isEmpty {
                    self.errorMessage = nil
                }
            }
    }

    func addSpot(name: String, address: String, latitude: Double, longitude: Double, sourceURL: String?, category: String, userId: String, completion: @escaping (Bool, String?) -> Void) {
        isLoading = true

        // The Spot model still includes userId for clarity/denormalization
        let newSpot = Spot(
            userId: userId,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            sourceURL: sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? nil : sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category
        )

        do {
            // Adding document to the subcollection: /users/{userId}/spots
            _ = try userSpotsCollection(userId: userId).addDocument(from: newSpot) { error in
                self.isLoading = false
                if let error = error {
                    completion(false, "Error adding spot: \(error.localizedDescription)")
                } else {
                    completion(true, nil)
                }
            }
        } catch {
            self.isLoading = false
            completion(false, "Error encoding spot: \(error.localizedDescription)")
        }
    }

    func deleteSpot(_ spot: Spot) async {
        guard let userId = spot.userId, let spotId = spot.id else { // Ensure userId is available for path
            errorMessage = "Error: Spot or User ID missing for deletion."
            return
        }
        isLoading = true
        do {
            // Deleting document from the subcollection: /users/{userId}/spots/{spotId}
            try await userSpotsCollection(userId: userId).document(spotId).delete()
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Error deleting spot: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func clearData() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        spots = []
        errorMessage = nil
        isLoading = false
    }
}
