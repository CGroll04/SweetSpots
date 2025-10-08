//
//  MultiCollectionSelectorView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-04.
//


import SwiftUI

struct MultiCollectionSelectorView: View {
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @Binding var selectedCollectionIds: Set<String>

    var body: some View {
        
        List(collectionViewModel.collections) { collection in
            
            HStack {
                Text(collection.name)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // This button acts as the checkbox
                Button(action: {
                    toggleSelection(for: collection.id)
                }) {
                    Image(systemName: isSelected(collection) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected(collection) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Select Collections")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    /// Checks if a given collection is in the selection set.
    private func isSelected(_ collection: SpotCollection) -> Bool {
        guard let id = collection.id else { return false }
        return selectedCollectionIds.contains(id)
    }
    
    /// Adds or removes a collection ID from the selection set.
    private func toggleSelection(for collectionId: String?) {
        guard let collectionId = collectionId else { return }
        
        if selectedCollectionIds.contains(collectionId) {
            selectedCollectionIds.remove(collectionId)
        } else {
            selectedCollectionIds.insert(collectionId)
        }
    }
}
