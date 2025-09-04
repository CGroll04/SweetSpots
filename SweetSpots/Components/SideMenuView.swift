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
    
    // Action to dismiss the menu
    let onDismiss: () -> Void
    
    // Environment objects for data
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var navigationViewModel: NavigationViewModel
    
    @State private var optionsCollection: SpotCollection? = nil
    @State private var showDeleteConfirmation = false
    @State private var showManageSpotsSheet = false
    @State private var itemToShare: ShareableContent? = nil
    @State private var isCreatingShareLink = false


    // Local state for presenting sheets
    @State private var collectionToEdit: SpotCollection? = nil
    @State private var isTrashExpanded: Bool = false
    @State private var isShowingAddCollectionView = false
    @State private var newCollectionName = ""
    @State private var spotToShowDetails: Spot? = nil
    
    var body: some View {
        NavigationView {
            List {
                defaultFiltersSection()
                myCollectionsSection()
                actionsSection()
                recentlyDeletedSection()
            }
            .listStyle(InsetGroupedListStyle())
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
                    .environmentObject(spotsViewModel)
                    .environmentObject(authViewModel)
                    .environmentObject(locationManager)
            }
            .sheet(item: $spotToShowDetails) { spot in
                NavigationView {
                    SpotDetailView(spotId: spot.id ?? "", presentedFrom: .list)
                        .environmentObject(spotsViewModel)
                        .environmentObject(collectionViewModel)
                        .environmentObject(locationManager)
                        .environmentObject(navigationViewModel)
                        .environmentObject(authViewModel)
                }
            }
            .sheet(isPresented: $isShowingAddCollectionView) {
                AddCollectionView()
                    .environmentObject(spotsViewModel)
                    .environmentObject(collectionViewModel)
            }
            .sheet(isPresented: $showManageSpotsSheet) {
                if let c = optionsCollection {
                    ManageSpotsInCollectionView(collection: c)
                        .environmentObject(spotsViewModel)
                        .environmentObject(collectionViewModel)
                }
            }
            .confirmationDialog(
                optionsCollection != nil ? "Delete '\(optionsCollection!.name)'?" : "Delete Collection",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Collection & Spots", role: .destructive) {
                    deleteCollection(mode: .collectionAndSpots)
                }
                Button("Remove Collection", role: .destructive) {
                    deleteCollection(mode: .collectionOnly)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(item: $itemToShare) { item in
                // Pass an array containing BOTH the text and the URL
                ShareSheet(items: [item.text, item.url])
            }
        }
    }
    
    private func deleteCollection(mode: DeletionMode) {
        guard let coll = optionsCollection else { return }
        collectionViewModel.deleteCollection(
            coll,
            mode: mode,
            allSpots: spotsViewModel.spots, // <-- PASS IN ALL THE SPOTS
        ) { result in
            switch result {
            case .success:
                // If the deleted collection was selected, reset to All Spots
                if selectedCollectionFilterId == coll.id {
                    selectedCollectionFilterId = nil
                }
            case .failure(let error):
                print("Delete failed: \(error.localizedDescription)")
            }
            optionsCollection = nil
        }
    }
    
    // MARK: - Subviews for Body Sections
    @ViewBuilder
    private func recentlyDeletedSection() -> some View {
        if !spotsViewModel.recentlyDeletedSpots.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isTrashExpanded) {
                    ForEach(spotsViewModel.recentlyDeletedSpots) { spot in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(spot.name)
                                    .foregroundStyle(.primary)
                                
                                if let days = daysRemaining(for: spot) {
                                    Text("Permanently deleted in \(days) day\(days == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                spotToShowDetails = spot
                            }
                            
                            Spacer(minLength: 8)
                            
                            Menu {
                                Button {
                                    spotsViewModel.restoreSpot(spot)
                                } label: {
                                    Label("Restore Spot", systemImage: "arrow.uturn.backward.circle.fill")
                                }
                                
                                Button(role: .destructive) {
                                    spotsViewModel.permanentlyDeleteSpot(spot)
                                } label: {
                                    Label("Delete Permanently", systemImage: "trash.fill")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.body)
                            }
                            .tint(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "trash")
                            .font(.callout)
                            .frame(width: 20, alignment: .center)
                            .foregroundStyle(.secondary)
                        
                        Text("Recently Deleted")
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Text("\(spotsViewModel.recentlyDeletedSpots.count)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            isTrashExpanded.toggle()
                        }
                    }
                }
            }
        }
    }

    private func daysRemaining(for spot: Spot) -> Int? {
        guard let deletedDate = spot.deletedAt?.dateValue() else { return nil }
        let calendar = Calendar.current
        let expirationDate = calendar.date(byAdding: .day, value: 30, to: deletedDate) ?? deletedDate
        let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
        return max(0, components.day ?? 0)
    }
    
    @ViewBuilder
    private func defaultFiltersSection() -> some View {
        Section(header: Text("Filters")) {
            let isSelected = (selectedCollectionFilterId == nil)
            
            let row = FilterRow(
                title: "All Spots",
                icon: "square.stack.3d.up",
                isSelected: isSelected,
                spotCount: spotsViewModel.spots.count,
                onEdit: nil
            ) {
                selectedCollectionFilterId = nil
                onDismiss()
            }
            
            if isSelected {
                row.listRowBackground(Color.themePrimary.opacity(0.2))
            } else {
                row
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
                    let isSelected = (selectedCollectionFilterId == collection.id)
                    let count = spotsViewModel.spots.filter { $0.collectionIds.contains(collection.id ?? "") }.count

                    HStack(spacing: 15) {
                        Button {
                            selectedCollectionFilterId = collection.id
                            onDismiss()
                        } label: {
                            HStack(spacing: 15) {
                                Image(systemName: "folder")
                                    .font(.callout)
                                    .frame(width: 20, alignment: .center)
                                    .foregroundColor(isSelected ? Color.themePrimary : .secondary)

                                Text(collection.name)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                    .foregroundStyle(isSelected ? Color.themePrimary : .primary)

                                Spacer()

                                Text("\(count)")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // ⬇️ The new trailing menu
                        Menu {
                            // 1) Rename / Description
                            Button {
                                self.collectionToEdit = collection
                            } label: {
                                Label("Rename / Description", systemImage: "pencil")
                            }

                            // 2) Edit Spots
                            Button {
                                self.optionsCollection = collection
                                self.showManageSpotsSheet = true
                            } label: {
                                Label("Edit Spots in Collection", systemImage: "checklist")
                            }
                            
                            Button {
                                Task {
                                    await handleShareCollection(collection)
                                }
                            } label: {
                                Label("Share Collection", systemImage: "square.and.arrow.up")
                            }

                            // 3) Delete
                            Button(role: .destructive) {
                                self.optionsCollection = collection
                                self.showDeleteConfirmation = true
                            } label: {
                                Label("Delete Collection", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body)
                        }
                        .tint(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(isSelected ? Color.themePrimary.opacity(0.2) : nil)
                }
            }
        }
    }
    
    // Add this new function inside the SideMenuView struct

    private func handleShareCollection(_ collection: SpotCollection) async {
        guard let collectionId = collection.id, let userId = authViewModel.userSession?.uid else { return }
        isCreatingShareLink = true
        
        let spotsInCollection = spotsViewModel.spots.filter { $0.collectionIds.contains(collectionId) }
        let senderName = authViewModel.userSession?.displayName
        
        do {
            // This 'try await' call now correctly receives a non-optional URL or throws an error
            let url = try await SpotShareManager.makeCollectionShareURL(
                from: collection,
                with: spotsInCollection,
                senderName: senderName,
                userId: userId
            )
            
            let text = senderName != nil ? "\(senderName!) shared the '\(collection.name)' collection with you!" : "Check out the '\(collection.name)' collection on SweetSpots!"
            
            // This line will no longer have an error
            itemToShare = ShareableContent(text: text, url: url)
            
        } catch {
            print("SideMenuView: Failed to create collection share URL: \(error)")
            // You can show an error alert to the user here
        }
        
        isCreatingShareLink = false
    }
    
    @ViewBuilder
    private func actionsSection() -> some View {
        Section {
            Button(action: {
                isShowingAddCollectionView = true
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

        Task {
            do {
                let newId = try await collectionViewModel.addCollection(
                    name: trimmedName,
                    userId: userId,
                    description: nil
                )
                
                self.selectedCollectionFilterId = newId
                self.onDismiss()
                
            } catch {
                print("SideMenuView: Failed to create collection: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Filter Row
struct FilterRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let spotCount: Int
    let onEdit: (() -> Void)?
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
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                
                if let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
