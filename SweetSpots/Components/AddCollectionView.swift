//
//  AddCollectionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-24.
//

import SwiftUI

// A new, dedicated view for a selectable spot row.
private struct SelectableSpotRow: View {
    let spot: Spot
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: spot.category.systemImageName)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(colorFromString(spot.category.associatedColor))
                .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(spot.name)
                    .fontWeight(.semibold)
                Text(spot.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.themeAccent)
            }
        }
        .padding(.vertical, 6)
    }
    
    // This helper can be moved from SpotCardView or duplicated here
    public func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "blue": return .blue
        case "red": return .red
        case "teal": return .teal
        case "brown": return .brown
        default: return .gray
        }
    }
}

struct AddCollectionView: View {
    // Environment Objects
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    // State
    @State private var selectedSpotIDs: Set<String> = []
    @State private var collectionName: String = ""
    @State private var isProcessing = false
    
    private var allSpots: [Spot] {
        spotsViewModel.spots
    }
    
    private var canCreateCollection: Bool {
        !collectionName.trimmingCharacters(in: .whitespaces).isEmpty && !isProcessing
    }
    
    var body: some View {
        NavigationView {
            Form {
                // SECTION 1: Name the Collection
                Section(header: Text("Collection Name")) {
                    TextField("e.g., Summer Trip, Best Cafes", text: $collectionName)
                }
                
                // SECTION 2: Select Spots
                Section(header: Text("Select Spots (\(selectedSpotIDs.count) selected)")) {
                    // Use a List for the selectable items
                    List(allSpots) { spot in
                        Button {
                            toggleSelection(for: spot)
                        } label: {
                            SelectableSpotRow(
                                spot: spot,
                                isSelected: selectedSpotIDs.contains(spot.id ?? "")
                            )
                        }
                    }
                }
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        handleCreateCollection()
                    }
                    .disabled(!canCreateCollection)
                }
            }
            .overlay {
                if isProcessing {
                    // You can replace this with a more sophisticated overlay
                    ProgressView("Saving...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    
    private func toggleSelection(for spot: Spot) {
        guard let spotId = spot.id else { return }
        if selectedSpotIDs.contains(spotId) {
            selectedSpotIDs.remove(spotId)
        } else {
            selectedSpotIDs.insert(spotId)
        }
    }
    
    private func handleCreateCollection() {
        // It's more robust to get the userId from the authViewModel
        guard let userId = authViewModel.userSession?.uid else { return }
        isProcessing = true

        Task {
            do {
                let newCollectionId = try await collectionViewModel.addCollection(
                    name: collectionName,
                    userId: userId
                )

                if !selectedSpotIDs.isEmpty {
                    // Use the new, correct function name
                    spotsViewModel.addSpotsToCollection(spotIDs: selectedSpotIDs, toCollection: newCollectionId)
                }

                dismiss()
            } catch {
                isProcessing = false
                print("Failed to create collection: \(error.localizedDescription)")
            }
        }
    }
}
