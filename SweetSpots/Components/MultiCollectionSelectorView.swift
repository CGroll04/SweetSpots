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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(collectionViewModel.collections) { collection in
                Button(action: {
                    toggleSelection(for: collection.id)
                }) {
                    HStack {
                        Text(collection.name)
                        Spacer()
                        if let id = collection.id, selectedCollectionIds.contains(id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Select Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func toggleSelection(for collectionId: String?) {
        guard let collectionId = collectionId else { return }
        
        if selectedCollectionIds.contains(collectionId) {
            selectedCollectionIds.remove(collectionId)
        } else {
            selectedCollectionIds.insert(collectionId)
        }
    }
}
