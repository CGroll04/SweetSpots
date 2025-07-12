//
//  SideMenuView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-09.
//

import SwiftUI

// MARK: - Side Menu View
struct SideMenuView: View {
    // Bindings to control the parent view's state
    @Binding var selectedCollectionFilterId: String?
    @Binding var showOnlyUncategorized: Bool
    
    // Action to dismiss the menu
    let onDismiss: () -> Void
    
    // Environment objects for data
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel // Needed for NewCollectionView sheet
    @EnvironmentObject private var locationManager: LocationManager // ✅ 1. ADD THIS
    
    // Local state for presenting sheets
    @State private var collectionToEdit: SpotCollection? = nil
    @State private var isShowingAddCollectionAlert = false
    @State private var newCollectionName = ""
    
    var body: some View {
        NavigationView {
            List { // Using a List is more conventional for settings/menu lists and handles scrolling
                defaultFiltersSection()
                myCollectionsSection()
                actionsSection()
            }
            .listStyle(InsetGroupedListStyle()) // Or .plain for a tighter look
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }.tint(Color.themeAccent)
                }
            }
            .sheet(item: $collectionToEdit) { collection in
                EditCollectionView(collection: collection)
                    .environmentObject(collectionViewModel)
                    .environmentObject(spotsViewModel) // Pass spotsVM for orphaning on delete
                    .environmentObject(authViewModel)
                    .environmentObject(locationManager)
            }
            .alert("New Collection", isPresented: $isShowingAddCollectionAlert) {
                TextField("Collection Name", text: $newCollectionName)
                    .autocorrectionDisabled()

                Button("Create") {
                    handleCreateCollection()
                }
                .disabled(newCollectionName.trimmedSafe().isEmpty)

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter a name for your new collection.")
            }
        }
    }
    
    // MARK: - Subviews for Body Sections

    @ViewBuilder
    private func defaultFiltersSection() -> some View {
        Section(header: Text("Filters")) {
            // All spots option
            FilterRow(
                title: "All Spots",
                icon: "square.stack.3d.up", // A more descriptive icon
                isSelected: selectedCollectionFilterId == nil && !showOnlyUncategorized,
                spotCount: spotsViewModel.spots.count,
                onEdit: nil // No edit action for this row
            ) {
                selectedCollectionFilterId = nil
                showOnlyUncategorized = false
                onDismiss()
            }
            
            // Uncategorized option
            FilterRow(
                title: "Uncategorized",
                icon: "tray",
                isSelected: showOnlyUncategorized,
                spotCount: spotsViewModel.spots.filter { $0.collectionId == nil }.count,
                onEdit: nil // No edit action for this row
            ) {
                selectedCollectionFilterId = nil
                showOnlyUncategorized = true
                onDismiss()
            }
        }
    }
    
    @ViewBuilder
    private func myCollectionsSection() -> some View {
        Section(header: Text("My Collections")) {
            if collectionViewModel.collections.isEmpty {
                Text("No collections yet. Tap '+' to create one.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.vertical)
            } else {
                ForEach(collectionViewModel.collections) { collection in
                    FilterRow(
                        title: collection.name, // Use name, not displayName if it's the same
                        icon: "folder",
                        isSelected: selectedCollectionFilterId == collection.id,
                        spotCount: spotsViewModel.spots.filter { $0.collectionId == collection.id }.count,
                        onEdit: { // Provide the edit action
                            self.collectionToEdit = collection
                        }
                    ) {
                        selectedCollectionFilterId = collection.id
                        showOnlyUncategorized = false
                        onDismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func actionsSection() -> some View {
        Section {
            // The button now just toggles our alert state.
            Button(action: {
                newCollectionName = "" // Clear any previous text
                isShowingAddCollectionAlert = true
            }) {
                Label("New Collection", systemImage: "plus.circle.fill")
            }
            .foregroundStyle(Color.accentColor)
        }
    }
    
    private func handleCreateCollection() {
        guard let userId = authViewModel.userSession?.uid else { return }
        let trimmedName = newCollectionName.trimmedSafe()
        guard !trimmedName.isEmpty else { return }

        // Use a Task to call the async function from a synchronous context.
        Task {
            do {
                // Use 'try await' to call the async function.
                let newId = try await collectionViewModel.addCollection(
                    name: trimmedName,
                    userId: userId,
                    description: nil
                )
                
                // --- SUCCESS ---
                // If the await call succeeds, this code will run.
                // On success, select the new collection filter and dismiss the side menu.
                self.selectedCollectionFilterId = newId
                self.showOnlyUncategorized = false
                self.onDismiss()
                
            } catch {
                // If the await call throws an error, this code will run.
                print("SideMenuView: Failed to create collection: \(error.localizedDescription)")
                // Optionally, you could set an alert here to inform the user of the failure.
            }
        }
    }
}

// MARK: - Filter Row (Slightly Refined)
struct FilterRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let spotCount: Int
    let onEdit: (() -> Void)? // Made onEdit optional
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.callout)
                    .frame(width: 20, alignment: .center)
                    .foregroundColor(isSelected ? Color.themePrimary : .secondary)

                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.themePrimary : .primary)

                Spacer()

                Text("\(spotCount)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1)) // Use theme-agnostic secondary
                    .clipShape(Capsule())
                
                // Only show edit button if onEdit action is provided
                if let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain) // Important for tap target separation
                    .padding(.leading, 4) // Space between count and edit button
                }
            }
            .padding(.vertical, 8)
            .background(isSelected ? Color.themePrimary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle()) // Make the whole area tappable for the main action
        }
        .buttonStyle(.plain) // Allows custom backgrounds and prevents blue tint on whole row
    }
}
