//
//  EditCollectionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-08.
//

import SwiftUI

fileprivate struct EditCollectionAlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct EditCollectionView: View {
    @EnvironmentObject var collectionViewModel: CollectionViewModel
    @Environment(\.dismiss) var dismiss
    
    // The collection being edited. Passed in and used to initialize @State.
    // This 'collection' itself won't be directly bound to UI editing fields.
    // Instead, editableName and editableDescription will be bound.
    let collection: SpotCollection
    
    @State private var editableName: String
    @State private var editableDescription: String
    @State private var showDeleteConfirmation: Bool = false
    @State private var isProcessing: Bool = false
    @State private var alertInfo: EditCollectionAlertInfo? = nil

    init(collection: SpotCollection) {
        self.collection = collection // Store the initial collection
        // Initialize @State properties for editing based on the passed-in collection
        _editableName = State(initialValue: collection.name)
        _editableDescription = State(initialValue: collection.descriptionText ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Collection Details") { // Simplified header
                    TextField("Name", text: $editableName)
                        .disabled(isProcessing)
                    
                    // Using TextEditor for potentially multi-line description
                    VStack(alignment: .leading) {
                        Text("Description (Optional)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextEditor(text: $editableDescription)
                            .frame(height: 100) // Give it some default height
                            .border(Color.gray.opacity(0.2), width: 1) // Optional: visual cue
                            .disabled(isProcessing)
                    }
                }

                Section {
                    Button("Save Changes") {
                        saveChanges()
                    }
                    .disabled(editableName.trimmedSafe().isEmpty || isProcessing || !hasChanges())
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                
                Section {
                    Button("Delete Collection", role: .destructive) {
                        guard !isProcessing else { return }
                        showDeleteConfirmation = true
                    }
                    .disabled(isProcessing)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Edit Collection") // Static title, or "Edit \(collection.name)"
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                        .tint(Color.accentColor) // Or your theme accent
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isProcessing { ProgressView().tint(Color.accentColor) }
                }
            }
            .alert(item: $alertInfo) { info in
                Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
            }
            .alert("Delete '\(collection.name)'?", isPresented: $showDeleteConfirmation) { // More specific title
                Button("Delete", role: .destructive) { deleteCollection() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Spots in this collection will become uncategorized. This action cannot be undone.")
            }
            .overlay {
                 if isProcessing { ProcessingOverlayView(message: "Processing...") }
            }
        }
    }

    private func hasChanges() -> Bool {
        let trimmedEditableName = editableName.trimmedSafe()
        let trimmedEditableDescription = editableDescription.trimmedSafe()
        
        // Compare current editable state with the original collection's state
        let nameChanged = trimmedEditableName != collection.name
        let descriptionChanged = (trimmedEditableDescription.isEmpty ? nil : trimmedEditableDescription) != collection.descriptionText
        
        return nameChanged || descriptionChanged
    }

    private func saveChanges() {
        let trimmedName = editableName.trimmedSafe()
        guard !trimmedName.isEmpty else {
            alertInfo = EditCollectionAlertInfo(title: "Name Required", message: "Collection name cannot be empty.")
            return
        }
        
        if trimmedName.localizedCaseInsensitiveCompare(collection.name) != .orderedSame {
            let alreadyExists = collectionViewModel.collections.first { existingColl in
                existingColl.id != collection.id &&
                existingColl.userId == collection.userId && // Ensure check is for the same user
                existingColl.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
            }
            if alreadyExists != nil {
                alertInfo = EditCollectionAlertInfo(title: "Name Exists", message: "Another collection with this name already exists.")
                return
            }
        }

        isProcessing = true
        var updatedCollection = self.collection // Start with the original to preserve ID, userId, createdAt
        updatedCollection.name = trimmedName
        updatedCollection.descriptionText = editableDescription.trimmedSafe().isEmpty ? nil : editableDescription.trimmedSafe()
        
        collectionViewModel.updateCollection(updatedCollection) { result in
            isProcessing = false
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                alertInfo = EditCollectionAlertInfo(title: "Update Failed", message: error.localizedDescription)
            }
        }
    }
    
    private func deleteCollection() {
        isProcessing = true
        // Option A: Spot orphaning is handled by UI filtering based on missing collection.
        collectionViewModel.deleteCollection(self.collection, updateSpotsViewModel: nil) { result in
            isProcessing = false
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                alertInfo = EditCollectionAlertInfo(title: "Delete Failed", message: error.localizedDescription)
            }
        }
    }
}

#Preview {
    let mockCollection = SpotCollection(
        userId: "user123",
        name: "Sample Collection",
        descriptionText: "This is a sample collection for preview"
    )
    
    return NavigationView {
        EditCollectionView(collection: mockCollection)
            .environmentObject(CollectionViewModel())
            .environmentObject(SpotViewModel())
    }
}
