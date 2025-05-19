//
//  SpotViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI
import FirebaseFirestore
import CoreLocation // Only if still needed for other things, not for geocoding in addSpot

@MainActor
class SpotViewModel: ObservableObject {
    @Published var spots: [Spot] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    // private let geocoder = CLGeocoder() // No longer needed for adding spots

    func fetchData(userId: String) {
        isLoading = true
        listenerRegistration?.remove() // Detach previous listener if any

        print("Fetching data for userId: \(userId)")
        listenerRegistration = db.collection("spots")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Error fetching spots: \(error.localizedDescription)"
                    print("Firestore listener error: \(error.localizedDescription)")
                    return
                }

                guard let documents = querySnapshot?.documents else {
                    self.errorMessage = "No spots found or snapshot was empty."
                    self.spots = []
                    print("No documents in snapshot.")
                    return
                }
                
                print("Received \(documents.count) documents from Firestore.")

                self.spots = documents.compactMap { document -> Spot? in
                    do {
                        let spot = try document.data(as: Spot.self)
                        // print("Successfully decoded spot: \(spot.name), ID: \(spot.id ?? "no id")")
                        return spot
                    } catch {
                        print("Error decoding spot \(document.documentID): \(error.localizedDescription)")
                        self.errorMessage = "Error decoding spot data." // Show a generic error
                        return nil
                    }
                }
                
                if !documents.isEmpty && self.spots.isEmpty {
                     print("WARNING: Documents received but spots array is empty. Check Spot struct decoding and Codable conformance.")
                }
                
                // Clear error message if spots are successfully loaded or if there are no spots (not an error)
                if !self.spots.isEmpty || documents.isEmpty {
                    self.errorMessage = nil
                }
                print("SpotsViewModel updated spots. Count: \(self.spots.count)")
            }
    }

    // Updated addSpot method
    func addSpot(name: String, address: String, latitude: Double, longitude: Double, sourceURL: String?, userId: String, completion: @escaping (Bool, String?) -> Void) {
        isLoading = true

        let newSpot = Spot(
            userId: userId,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            sourceURL: sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? nil : sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            // createdAt will be set by @ServerTimestamp
        )

        do {
            _ = try self.db.collection("spots").addDocument(from: newSpot) { error in
                self.isLoading = false
                if let error = error {
                    print("Error adding spot to Firestore: \(error.localizedDescription)")
                    completion(false, "Error adding spot: \(error.localizedDescription)")
                } else {
                    print("Spot '\(newSpot.name)' added successfully to Firestore.")
                    completion(true, nil) // Success
                }
            }
        } catch {
            self.isLoading = false
            print("Error encoding spot for Firestore: \(error.localizedDescription)")
            completion(false, "Error encoding spot: \(error.localizedDescription)")
        }
    }

    func deleteSpot(_ spot: Spot) {
        guard let spotId = spot.id else {
            errorMessage = "Error: Spot ID missing for deletion."
            print("Error: Spot ID missing for deletion: \(spot.name)")
            return
        }
        isLoading = true
        db.collection("spots").document(spotId).delete { [weak self] error in
            self?.isLoading = false
            if let error = error {
                self?.errorMessage = "Error deleting spot: \(error.localizedDescription)"
                print("Error deleting spot \(spotId): \(error.localizedDescription)")
            } else {
                print("Spot \(spotId) deleted successfully.")
            }
        }
    }

    func clearData() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        spots = []
        errorMessage = nil
        isLoading = false
        print("SpotsViewModel data cleared.")
    }
}
