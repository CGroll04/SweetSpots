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
                            // If the spot is a conflict, set it as the one to resolve
                            if case .conflict = spot.state {
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
                // Pre-scan for duplicates when the view appears
                self.importableSpots = payload.spots.map { spotPayload in
                    // Find a spot in the user's library with the same name and address
                    if let existingSpot = spotsViewModel.spots.first(where: {
                        $0.name.lowercased() == spotPayload.name.lowercased() &&
                        $0.address.lowercased() == spotPayload.address.lowercased()
                    }) {
                        // If found, mark it as a conflict
                        return ImportableSpot(payload: spotPayload, state: .conflict(existingSpot: existingSpot))
                    } else {
                        // Otherwise, it's a new spot
                        return ImportableSpot(payload: spotPayload, state: .new)
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
            case .new, .resolved(.saveAsDuplicate), .resolved(.updateWithImported):
                // These states result in a spot being saved
                return true
            case .conflict, .resolved(.keepOriginal):
                // These states do not
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
                userId: userId,
                description: payload.collectionDescription
            )

            var spotsToCreate: [Spot] = []
            var spotsToUpdate: [Spot] = []

            for item in importableSpots {
                switch item.state {
                case .new, .resolved(.saveAsDuplicate):
                    // Create a new spot
                    let newSpot = Spot(userId: userId, from: item.payload, collectionIds: [newCollectionId])
                    spotsToCreate.append(newSpot)

                case .resolved(.updateWithImported):
                    // Find the existing spot and update it with the new data
                    if let existingSpot = spotsViewModel.spots.first(where: {
                        $0.name.lowercased() == item.payload.name.lowercased() &&
                        $0.address.lowercased() == item.payload.address.lowercased()
                    }) {
                        var updatedSpot = existingSpot
                        updatedSpot.update(from: item.payload, newCollectionId: newCollectionId)
                        spotsToUpdate.append(updatedSpot)
                    }

                case .conflict, .resolved(.keepOriginal):
                    // Do nothing for unresolved conflicts or if user chose to keep their original
                    break
                }
            }

            // Perform the batch operations
            spotsViewModel.addMultipleSpots(spotsToCreate) { result in
                if case .failure(let error) = result {
                    self.logger.error("Failed to batch-create imported spots: \(error.localizedDescription)")
                }
            }
            for spot in spotsToUpdate {
                spotsViewModel.updateSpot(spot) { result in
                    if case .failure(let error) = result {
                        self.logger.error("Failed to update spot '\(spot.name)' during import: \(error.localizedDescription)")
                    }
                }
            }

            logger.info("Successfully imported collection '\(collectionName)' with \(spotsToCreate.count) new spots and \(spotsToUpdate.count) updated spots.")
            isPresented = false
        } catch {
            logger.error("Error creating new collection '(collectionName)': (error.localizedDescription)")
            isSaving = false
        }
    }
}


