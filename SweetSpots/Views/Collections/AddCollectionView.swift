//
//  AddCollectionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-24.
//

import SwiftUI
import Combine
import os.log

/// A view presented modally for creating a new collection and selecting spots to include in it.
struct AddCollectionView: View {
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "AddCollectionView")
    
    // Environment Objects
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    @FocusState private var isEmojiFieldFocused: Bool
    @State private var collectionEmoji: String = ""
    
    // State
    @State private var selectedSpotIDs: Set<String> = []
    @State private var collectionName: String = ""
    @State private var collectionDescription: String = ""
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
                Section(header: Text("Collection Details")) {
                    TextField("Name (e.g., Summer Trip, Best Cafes)", text: $collectionName)
                    HStack {
                        Text("Emoji (Optional)")
                        Spacer()
                        ZStack {
                            // The actual TextField, with no visible title
                            TextField("", text: $collectionEmoji)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                                .focused($isEmojiFieldFocused) // Link the focus state
                                .onChange(of: collectionEmoji) {
                                    if let firstChar = collectionEmoji.first, firstChar.isEmoji {
                                        collectionEmoji = String(firstChar)
                                    } else {
                                        collectionEmoji = ""
                                    }
                                }

                            // The custom placeholder
                            if collectionEmoji.isEmpty && !isEmojiFieldFocused {
                                Text("😀")
                            }
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Description (Optional)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextEditor(text: $collectionDescription)
                            .frame(height: 80)
                    }
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
        guard let userId = authViewModel.userSession?.uid else {
            logger.fault("User ID is missing. Cannot create collection.")
            return
        }

        Task {
            isProcessing = true
            do {
                let newCollectionId = try await collectionViewModel.addCollection(
                    name: collectionName,
                    emoji: collectionEmoji.isEmpty ? nil : collectionEmoji,
                    senderName: nil,
                    userId: userId,
                    description: collectionDescription.isEmpty ? nil : collectionDescription
                )

                if !selectedSpotIDs.isEmpty {
                    spotsViewModel.addSpotsToCollection(spotIDs: selectedSpotIDs, toCollection: newCollectionId)
                }
                
                logger.info("Successfully created collection '\(self.collectionName)' with \(self.selectedSpotIDs.count) spots.")
                
                isProcessing = false
                dismiss()
                
            } catch {
                isProcessing = false
                logger.error("Failed to create collection: \(error.localizedDescription)")
            }
        }
    }
}
