//
//  ManageSpotsInCollectionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-24.
//

import SwiftUI
import os.log

/// A view for editing which spots are included in an existing collection.
struct ManageSpotsInCollectionView: View {
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "ManageSpotsInCollectionView")
    
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
        guard let collId = collection.id else {
            logger.fault("Cannot save collection changes: collection ID is missing.")
            return
        }
        
        Task{
            isProcessing = true
            
            let current = initiallyInCollection
            let toAdd = selectedSpotIDs.subtracting(current)
            let toRemove = current.subtracting(selectedSpotIDs)
            logger.info("Saving changes for collection '\(self.collection.name)': adding \(toAdd.count) spots, removing \(toRemove.count) spots.")
            
            if !toAdd.isEmpty {
                spotsViewModel.addSpotsToCollection(spotIDs: toAdd, toCollection: collId)
            }
            if !toRemove.isEmpty {
                spotsViewModel.removeSpotsFromCollection(spotIDs: toRemove, fromCollection: collId)
            }
            
            isProcessing = false
            dismiss()
        }
    }
}
