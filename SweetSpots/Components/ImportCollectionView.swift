//
//  ImportCollectionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-26.
//

import SwiftUI

// Make SharedSpotPayload Hashable so we can use it in a Set
extension SharedSpotPayload: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(address)
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

struct ImportCollectionView: View {
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
                    // The "Select All" button has been removed.

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
        guard let userId = authViewModel.userSession?.uid else { return }
        isSaving = true

        do {
            let newCollectionId = try await collectionViewModel.addCollection(
                name: collectionName,
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
            spotsViewModel.addMultipleSpots(spotsToCreate) { _ in }
            for spot in spotsToUpdate {
                spotsViewModel.updateSpot(spot) { _ in }
            }

            print("Successfully imported collection with resolved spots.")
            isPresented = false

        } catch {
            print("Error creating new collection: \(error.localizedDescription)")
            isSaving = false
        }
    }
}

struct SpotImportRow: View {
    @Binding var importableSpot: ImportableSpot

    var body: some View {
        HStack {
            // Display an icon based on the import state
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text(importableSpot.payload.name).fontWeight(.semibold)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // Helper properties to determine the row's appearance
    private var iconName: String {
        switch importableSpot.state {
        case .new: return "checkmark.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .resolved(let resolution):
            switch resolution {
            case .keepOriginal: return "shield.slash.fill"
            case .updateWithImported: return "checkmark.circle.fill"
            case .saveAsDuplicate: return "plus.circle.fill"
            }
        }
    }

    private var iconColor: Color {
        switch importableSpot.state {
        case .new: return .green
        case .conflict: return .orange
        case .resolved: return .blue
        }
    }

    private var statusText: String {
        switch importableSpot.state {
        case .new: return "Ready to import."
        case .conflict: return "Conflict: You already have this spot."
        case .resolved(let resolution): return "Resolved: \(resolution.rawValue)."
        }
    }
}
