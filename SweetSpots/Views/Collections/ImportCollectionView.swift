//
//  ImportCollectionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-26.
//

import SwiftUI
import os.log

/// A view for importing a shared collection, allowing the user to resolve conflicts before saving.
struct ImportCollectionView: View {
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "ImportCollectionView")
    
    // MARK: - Environment & State
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    @Binding var isPresented: Bool
    let payload: SharedCollectionPayload
    
    
    // Holds the list of spots and their conflict status
    @State private var importableSpots: [ImportableSpot] = []

    // Holds the specific spot the user is currently resolving
    @State private var spotToResolve: ImportableSpot? = nil

    // State for the rename-on-import feature
    @State private var isShowingRenameAlert = false
    @State private var newCollectionName = ""
    @State private var isSaving = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Header
                VStack(spacing: 8) {
                    Text(payload.collectionName)
                        .font(.largeTitle).fontWeight(.bold)
                    if let desc = payload.collectionDescription {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                // List of Spots
                List($importableSpots) { $spot in
                    SpotImportRow(importableSpot: $spot)
                        .onTapGesture {
                            // Allow the sheet to open if there is an existing spot (i.e., it's a conflict)
                            if spot.existingSpot != nil {
                                self.spotToResolve = spot
                            }
                        }
                }
                .sheet(item: $spotToResolve) { spot in
                    // We need to pass a binding to the sheet
                    if let index = importableSpots.firstIndex(where: { $0.id == spot.id }) {
                        ConflictResolutionView(importableSpot: $importableSpots[index])
                    }
                }
                
                // Action Buttons
                VStack {
                    Button(action: handleSave) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                // Use the new computed property for an accurate count
                                Text("Import \(spotsToImportCount) Spots")
                            }
                            Spacer()
                        }
                    }
                    .font(.headline)
                    .padding()
                    .background(hasUnresolvedConflicts || isSaving ? Color.gray : Color.themePrimary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .disabled(hasUnresolvedConflicts || isSaving)

                    // Optional: A helpful message for the user
                    if hasUnresolvedConflicts {
                        Text("Please resolve all conflicts before importing.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("Import Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .onAppear {
                self.importableSpots = payload.spots.map { spotPayload in
                    let normalizedPayloadAddress = normalize(address: spotPayload.address)
                    
                    if let existingSpot = spotsViewModel.spots.first(where: {
                        normalize(address: $0.address) == normalizedPayloadAddress
                    }) {
                        // Now we pass the existing spot into the main struct
                        return ImportableSpot(payload: spotPayload, state: .conflict(existingSpot: existingSpot), existingSpot: existingSpot)
                    } else {
                        // For new spots, existingSpot is nil
                        return ImportableSpot(payload: spotPayload, state: .new, existingSpot: nil)
                    }
                }
            }
            .alert("Name Already Exists", isPresented: $isShowingRenameAlert) {
                TextField("New collection name", text: $newCollectionName)
                Button("Save") {
                    // When save is tapped, run the save logic with the new name
                    Task {
                        await saveData(with: newCollectionName)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You already have a collection named \"\(payload.collectionName)\". Please enter a new name to continue.")
            }
        }
    }
    
    private var hasUnresolvedConflicts: Bool {
        importableSpots.contains {
            if case .conflict = $0.state { return true }
            return false
        }
    }
    
    private var spotsToImportCount: Int {
        importableSpots.filter { spot in
            switch spot.state {
            // A spot is "imported" if it's new or replaces an old one.
            case .new, .resolved(.replaceSpot):
                return true
            
            // Appending notes or keeping the original does not create a new spot.
            case .conflict, .resolved(.keepOriginal), .resolved(.appendNotes):
                return false
            }
        }.count
    }
    
    private func handleSave() {
        // 1. Check for a duplicate name before doing anything else.
        let isDuplicate = collectionViewModel.collections.contains { $0.name.lowercased() == payload.collectionName.lowercased() }
        
        if isDuplicate {
            // 2. If it's a duplicate, trigger the alert and stop.
            self.newCollectionName = payload.collectionName // Pre-fill the text field
            self.isShowingRenameAlert = true
        } else {
            // 3. If it's not a duplicate, save it with the original name.
            Task {
                await saveData(with: payload.collectionName)
            }
        }
    }
    
    private func saveData(with collectionName: String) async {
        guard let userId = authViewModel.userSession?.uid else {
            logger.fault("Cannot save imported collection: user ID is missing.")
            return
        }
        isSaving = true

        do {
            let newCollectionId = try await collectionViewModel.addCollection(
                name: collectionName,
                emoji: payload.emoji,
                senderName: payload.senderName,
                userId: userId,
                description: payload.collectionDescription
            )

            var spotsToCreate: [Spot] = []
            var spotsToUpdate: [Spot] = []
            var spotsToDelete: [Spot] = []

            for item in importableSpots {
                switch item.state {
                case .new:
                    spotsToCreate.append(Spot(userId: userId, from: item.payload, collectionIds: [newCollectionId]))

                case .resolved(.keepOriginal):
                    // Find the existing spot and update it with the new data
                    if item.addExistingToCollection, let existing = item.existingSpot {
                        var spotToUpdate = existing
                        spotToUpdate.collectionIds.append(newCollectionId)
                        spotsToUpdate.append(spotToUpdate)
                    }

                case .resolved(.appendNotes):
                    if let existing = item.existingSpot {
                        var spotToUpdate = existing
                        let newNotes = (existing.notes ?? "") + "\n\n--- Imported Notes ---\n" + (item.payload.notes ?? "")
                        spotToUpdate.notes = newNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                        if item.addExistingToCollection {
                            spotToUpdate.collectionIds.append(newCollectionId)
                        }
                        spotsToUpdate.append(spotToUpdate)
                    }
                case .resolved(.replaceSpot):
                    if let existing = item.existingSpot {
                        spotsToDelete.append(existing)
                        spotsToCreate.append(Spot(userId: userId, from: item.payload, collectionIds: [newCollectionId]))
                    }
                case .conflict: // This case shouldn't be possible if all conflicts are resolved
                    break
                }
            }

            // Perform the batch operations
            if !spotsToCreate.isEmpty { spotsViewModel.addMultipleSpots(spotsToCreate) { _ in } }
            if !spotsToUpdate.isEmpty { spotsToUpdate.forEach { spotsViewModel.updateSpot($0) { _ in } } }
            if !spotsToDelete.isEmpty { spotsToDelete.forEach { spotsViewModel.deleteSpot($0, isPermanent: true) { _ in } } } // Assuming soft delete
            
            isPresented = false
        } catch {
            logger.error("Error creating new collection '(collectionName)': (error.localizedDescription)")
            isSaving = false
        }
    }
    private func normalize(address: String) -> String {
        return address.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


