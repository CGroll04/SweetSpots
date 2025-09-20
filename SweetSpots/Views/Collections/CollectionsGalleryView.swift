//
//  CollectionsGalleryView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-08.
//

import SwiftUI

/// A view that displays all of the user's collections in a grid layout.
struct CollectionsGalleryView: View {
    // MARK: - Environment
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    
    // MARK: - State
    @State private var isShowingAddSheet = false
    
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
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
        .sheet(isPresented: $isShowingAddSheet) {
            // EnvironmentObjects are passed down automatically.
            AddCollectionView()
                .environmentObject(spotsViewModel)
                .environmentObject(collectionViewModel)
        }
    }
    
    // MARK: - Subviews
    
    /// The main scrolling grid of collection cards.
    private var collectionsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(collectionViewModel.collections) { collection in
                    NavigationLink(destination: CollectionDetailView(collectionID: collection.id ?? "")) {
                        CollectionCardView(
                            collection: collection,
                            spotCount: spotCount(for: collection.id)
                        )
                    }
                }
            }
            .padding()
        }
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
    
    /// Calculates the number of spots in a given collection.
    private func spotCount(for collectionId: String?) -> Int {
        guard let collectionId = collectionId else { return 0 }
        return spotsViewModel.spots.filter { $0.collectionIds.contains(collectionId) }.count
    }
}
