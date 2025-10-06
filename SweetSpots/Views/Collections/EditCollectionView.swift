//
//  EditCollectionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-08.
//

import SwiftUI
import os.log

typealias DeletionMode = CollectionViewModel.DeletionMode


fileprivate struct EditCollectionAlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// A view for editing the name and description of an existing collection.
struct EditCollectionView: View {
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "EditCollectionView")
    
    @EnvironmentObject var collectionViewModel: CollectionViewModel
    @EnvironmentObject var spotViewModel: SpotViewModel // Ensure SpotViewModel is in the environment
    @Environment(\.dismiss) var dismiss
    
    let collection: SpotCollection
    
    @FocusState private var isEmojiFieldFocused: Bool
    @State private var editableEmoji: String
    @State private var editableName: String
    @State private var editableDescription: String
    @State private var showDeleteConfirmation: Bool = false
    @State private var isProcessing: Bool = false
    @State private var alertInfo: EditCollectionAlertInfo? = nil
    @State private var isPublic: Bool


    init(collection: SpotCollection) {
        self.collection = collection // Store the initial collection
        // Initialize @State properties for editing based on the passed-in collection
        _editableName = State(initialValue: collection.name)
        _editableDescription = State(initialValue: collection.descriptionText ?? "")
        _isPublic = State(initialValue: collection.isPublic)
        _editableEmoji = State(initialValue: collection.emoji ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Collection Details") { // Simplified header
                    TextField("Name", text: $editableName)
                        .disabled(isProcessing)
                    
                    HStack {
                        Text("Emoji (Optional)")
                        Spacer()
                        ZStack {
                            // The actual TextField, with no visible title
                            TextField("", text: $editableEmoji)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                                .focused($isEmojiFieldFocused) // Link the focus state
                                .onChange(of: editableEmoji) {
                                    if let firstChar = editableEmoji.first, firstChar.isEmoji {
                                        editableEmoji = String(firstChar)
                                    } else {
                                        editableEmoji = ""
                                    }
                                }

                            // The custom placeholder
                            if editableEmoji.isEmpty && !isEmojiFieldFocused {
                                Text("😀")
                            }
                        }
                    }
                    
                    // Using TextEditor for potentially multi-line description
                    VStack(alignment: .leading) {
                        Text("Description (Optional)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextEditor(text: $editableDescription)
                            .frame(height: 100) // Give it some default height
                            .border(Color.gray.opacity(0.2), width: 1)
                            .disabled(isProcessing)
                    }
                }
                
                Section("Sharing") {
                    Toggle("Publicly Shareable Link", isOn: $isPublic)
                    Text("Anyone with the link can view this collection. Turn this off to disable any previously shared links.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .navigationTitle("Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                        .tint(Color.accentColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isProcessing { ProgressView().tint(Color.accentColor) }
                }
            }
            .alert(item: $alertInfo) { info in
                Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog(
                            "Delete '\(collection.name)'?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            // Option 1: Delete everything (destructive)
                            Button("Delete Collection & Spots", role: .destructive) {
                                deleteCollection(mode: .collectionAndSpots)
                            }
                            
                            // Option 2: Delete collection only
                            Button("Remove Collection)") {
                                deleteCollection(mode: .collectionOnly)
                            }
                            
                            // Standard cancel button
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This action cannot be undone.")
                        }
            .overlay {
                 if isProcessing { ProcessingOverlayView(message: "Processing...") }
            }
        }
    }
    
    private func deleteCollection(mode: DeletionMode) {
        logger.info("User initiated deletion of collection '\(self.collection.name)' with mode: \(String(describing: mode)).")
        Task {
            isProcessing = true
            do {
                try await collectionViewModel.deleteCollection(
                    self.collection,
                    mode: mode,
                    allSpots: spotViewModel.spots
                )
                dismiss()
            } catch {
                logger.error("Failed to delete collection '\(self.collection.name)': \(error.localizedDescription)")
                alertInfo = EditCollectionAlertInfo(title: "Delete Failed", message: error.localizedDescription)
            }
            isProcessing = false
        }
    }

    private func hasChanges() -> Bool {
        let trimmedName = editableName.trimmedSafe()
        let trimmedDescription = editableDescription.trimmedSafe()

        let nameChanged = trimmedName != collection.name
        
        let descriptionChanged = trimmedDescription != (collection.descriptionText ?? "")
        
        let sharingChanged = isPublic != collection.isPublic
        
        let emojiChanged = editableEmoji != (collection.emoji ?? "")

        return nameChanged || descriptionChanged || sharingChanged || emojiChanged
    }

    private func saveChanges() {
        logger.info("User initiated save for collection '\(collection.name)'.")
        let trimmedName = editableName.trimmedSafe()
        guard !trimmedName.isEmpty else {
            logger.debug("Save validation failed: collection name was empty.")
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
                logger.debug("Save validation failed: duplicate collection name '\(trimmedName)'.")
                alertInfo = EditCollectionAlertInfo(title: "Name Exists", message: "Another collection with this name already exists.")
                return
            }
        }

        isProcessing = true
        var updatedCollection = self.collection // Start with the original to preserve ID, userId, createdAt
        updatedCollection.name = trimmedName
        updatedCollection.descriptionText = editableDescription.trimmedSafe().isEmpty ? nil : editableDescription.trimmedSafe()
        updatedCollection.isPublic = self.isPublic
        updatedCollection.emoji = editableEmoji.isEmpty ? nil : editableEmoji
        
        collectionViewModel.updateCollection(updatedCollection) { result in
            isProcessing = false
            switch result {
            case .success:
                logger.info("Successfully updated collection '\(updatedCollection.name)'.")
                dismiss()
            case .failure(let error):
                logger.error("Failed to update collection '\(updatedCollection.name)': \(error.localizedDescription)")
                alertInfo = EditCollectionAlertInfo(title: "Update Failed", message: error.localizedDescription)
            }
        }
    }
}
