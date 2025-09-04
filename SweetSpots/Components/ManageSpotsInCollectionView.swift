//
//  ManageSpotsInCollectionView.swift
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
    private func colorFromString(_ colorName: String) -> Color {
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

struct ManageSpotsInCollectionView: View {
    // Environment
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @Environment(\.dismiss) private var dismiss

    // Input
    let collection: SpotCollection

    // State
    @State private var selectedSpotIDs: Set<String> = []
    @State private var isProcessing = false

    private var allSpots: [Spot] {
        spotsViewModel.spots
    }

    private var initiallyInCollection: Set<String> {
        Set(spotsViewModel.spots
            .filter { $0.collectionIds.contains(collection.id ?? "") }
            .compactMap { $0.id })
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Spots in ‘\(collection.name)’ (\(selectedSpotIDs.count) selected)")) {
                    List(allSpots) { spot in
                        Button {
                            toggle(spot)
                        } label: {
                            SelectableSpotRow(
                                spot: spot,
                                isSelected: selectedSpotIDs.contains(spot.id ?? "")
                            )
                        }
                    }
                }
            }
            .navigationTitle("Edit Spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isProcessing)
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("Updating…")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear {
                selectedSpotIDs = initiallyInCollection
            }
        }
    }

    private func toggle(_ spot: Spot) {
        guard let id = spot.id else { return }
        if selectedSpotIDs.contains(id) {
            selectedSpotIDs.remove(id)
        } else {
            selectedSpotIDs.insert(id)
        }
    }

    private func save() {
        guard let collId = collection.id else { return }
        isProcessing = true

        let current = initiallyInCollection
        let toAdd = selectedSpotIDs.subtracting(current)
        let toRemove = current.subtracting(selectedSpotIDs)

        // CORRECTED: Call the new, specific function names
        if !toAdd.isEmpty {
            spotsViewModel.addSpotsToCollection(spotIDs: toAdd, toCollection: collId)
        }
        if !toRemove.isEmpty {
            spotsViewModel.removeSpotsFromCollection(spotIDs: toRemove, fromCollection: collId)
        }

        // Give Firestore a moment to process before dismissing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isProcessing = false
            self.dismiss()
        }
    }
}
