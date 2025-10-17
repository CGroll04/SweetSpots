//
//  MultiCollectionSelectorView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-04.
//


import SwiftUI

struct MultiCollectionSelectorView: View {
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel // Needed for userId
    @Binding var selectedCollectionIds: Set<String>
    
    @State private var isShowingAddAlert = false
    @State private var newCollectionName = ""
    
    var body: some View {
        List {
            Section {
                Button(action: {
                    newCollectionName = "" // Clear previous input
                    isShowingAddAlert = true
                }) {
                    Label("Create New Collection", systemImage: "plus")
                }
            }
            
            // Your existing list of collections
            Section(header: Text("Existing Collections")) {
                ForEach(collectionViewModel.collections) { collection in
                    HStack {
                        Text(collection.name)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
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
            }
        }
        .navigationTitle("Select Collections")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Collection", isPresented: $isShowingAddAlert) {
            TextField("Collection Name", text: $newCollectionName)
            Button("Create & Select") {
                Task {
                    await handleCreateCollection()
                }
            }
            .disabled(newCollectionName.isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for your new collection.")
        }
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
    
    private func handleCreateCollection() async {
        guard let userId = authViewModel.userSession?.uid, !newCollectionName.isEmpty else { return }
        
        do {
            // Call your existing view model function
            let newCollectionId = try await collectionViewModel.addCollection(
                name: newCollectionName,
                emoji: nil,
                senderName: nil,
                userId: userId,
                description: nil
            )
            
            // Automatically select the new collection
            selectedCollectionIds.insert(newCollectionId)
            
        } catch {
            // Handle any errors from the view model, e.g., show another alert
            print("Failed to create collection: \(error.localizedDescription)")
        }
    }
}
