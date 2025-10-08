//
//  CollectionsGalleryView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-08.
//

import SwiftUI

enum CollectionSortOrder: String, CaseIterable, Identifiable {
    case dateDescending = "Date Added (Newest)"
    case dateAscending = "Date Added (Oldest)"
    case nameAscending = "Name (A-Z)"
    case spotCountDescending = "Spot Count (Most First)"
    case spotCountAscending = "Spot Count (Fewest First)"
    
    var id: String { self.rawValue }
}


/// A view that displays all of the user's collections in a grid layout.
struct CollectionsGalleryView: View {
    // MARK: - Environment
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    // MARK: - State
    @State private var isShowingAddSheet = false
    @State private var collectionToEdit: SpotCollection?
    @State private var collectionToManage: SpotCollection?
    @State private var collectionToDelete: SpotCollection?
    @State private var itemToShare: ShareableContent?
    @State private var currentSortOrder: CollectionSortOrder = .dateDescending
    
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    private var sortedCollections: [SpotCollection] {
        collectionViewModel.collections.sorted { c1, c2 in
            switch currentSortOrder {
            case .dateDescending:
                return (c1.createdAt?.dateValue() ?? .distantPast) > (c2.createdAt?.dateValue() ?? .distantPast)
            case .dateAscending:
                return (c1.createdAt?.dateValue() ?? .distantPast) < (c2.createdAt?.dateValue() ?? .distantPast)
            case .nameAscending:
                return c1.name.localizedCaseInsensitiveCompare(c2.name) == .orderedAscending
            case .spotCountDescending:
                return spotCount(for: c1) > spotCount(for: c2)
            case .spotCountAscending:
                return spotCount(for: c1) < spotCount(for: c2)
            }
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main content layer
            Color.themeBackground.ignoresSafeArea()
            Group {
                if collectionViewModel.isLoading {
                    ProgressView("Loading Collections...")
                } else if collectionViewModel.collections.isEmpty {
                    emptyStateView
                } else {
                    collectionsGrid
                }
            }
            
            // Floating Action Button (FAB) layer
            floatingAddButton
        }
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sortMenu
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            // EnvironmentObjects are passed down automatically.
            AddCollectionView()
                .environmentObject(spotsViewModel)
                .environmentObject(collectionViewModel)
        }
        .sheet(item: $collectionToEdit) { collection in
            EditCollectionView(collection: collection)
        }
        .sheet(item: $collectionToManage) { collection in
            ManageSpotsInCollectionView(collection: collection)
        }
        .sheet(item: $itemToShare) { item in
            ShareSheet(items: [item.text, item.url])
        }
        .confirmationDialog(
            "Delete '\(collectionToDelete?.name ?? "Collection")'?",
            isPresented: .constant(collectionToDelete != nil),
            titleVisibility: .visible,
            presenting: collectionToDelete
        ) { collection in
            deleteButtons(for: collection)
        }
    }
    
    // MARK: - Subviews
    
    /// The main scrolling grid of collection cards.
    private var collectionsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(sortedCollections) { collection in
                    VStack{
                        NavigationLink(destination: CollectionDetailView(collectionID: collection.id ?? "")) {
                            
                            let spotsInCollection = spotsViewModel.spots.filter {
                                $0.collectionIds.contains(collection.id ?? "")
                            }
                            
                            CollectionCardView(
                                collection: collection,
                                spotsInCollection: spotsInCollection,
                                onSharePrivately: {
                                    Task { await handleShare(for: collection, publicly: false) }
                                },
                                onSharePublicly: {
                                    Task { await handleShare(for: collection, publicly: true) }
                                },
                                onEditDetails: {
                                    collectionToEdit = collection
                                },
                                onManageSpots: {
                                    collectionToManage = collection
                                },
                                onDelete: {
                                    collectionToDelete = collection
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }
    
    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $currentSortOrder) {
                ForEach(CollectionSortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down.circle")
        }
    }
    
    private func spotCount(for collection: SpotCollection) -> Int {
        return spotsViewModel.spots.filter { $0.collectionIds.contains(collection.id ?? "") }.count
    }

    
    /// The view to show when the user has no collections.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.themePrimary.opacity(0.7))
            
            Text("No Collections Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the '+' button to create your first collection and organize your favorite spots.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }
    
    /// The floating '+' button in the bottom corner.
    private var floatingAddButton: some View {
        Button(action: {
            isShowingAddSheet = true
        }) {
            Image(systemName: "plus")
                .font(.title.weight(.semibold))
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Circle())
                .shadow(radius: 4, x: 0, y: 2)
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    @ViewBuilder
    private func deleteButtons(for collection: SpotCollection) -> some View {
        Button("Delete Collection & Spots", role: .destructive) {
            Task { await deleteCollection(collection, mode: .collectionAndSpots) }
        }
        Button("Remove Collection Only", role: .destructive) {
            Task { await deleteCollection(collection, mode: .collectionOnly) }
        }
        Button("Cancel", role: .cancel) { collectionToDelete = nil }
    }
    
    private func deleteCollection(_ collection: SpotCollection, mode: CollectionViewModel.DeletionMode) async {
        do {
            try await collectionViewModel.deleteCollection(
                collection,
                mode: mode,
                allSpots: spotsViewModel.spots
            )
        } catch {
            // Handle error, e.g., show an alert
            print("Failed to delete collection: \(error.localizedDescription)")
        }
        collectionToDelete = nil
    }

    private func handleShare(for collection: SpotCollection, publicly: Bool) async {
        guard let collectionId = collection.id else { return }
        do {
            let url: URL
            if publicly {
                url = try await SpotShareManager.makePublicCollectionShareURL(for: collection)
            } else {
                url = try await SpotShareManager.makePrivateShareURL(for: .collection(id: collectionId))
            }
            
            let senderName = authViewModel.userSession?.displayName ?? "A friend"
            let text = "\(senderName) shared the '\(collection.name)' collection with you!"
            itemToShare = ShareableContent(text: text, url: url)
        } catch {
            // Handle error
            print("Failed to create share link: \(error.localizedDescription)")
        }
    }
}
