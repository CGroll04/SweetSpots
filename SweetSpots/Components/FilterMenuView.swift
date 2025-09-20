//
//  FilterMenuView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-07-20.
//

import SwiftUI

/// A popover menu view that provides options for filtering a list of spots by collection status and category.
struct FilterMenuView: View {
    // Bindings to control the parent view's state
    @Binding var collectionFilterState: SpotListView.CollectionFilterState
    @Binding var selectedCategoryFilters: Set<SpotCategory>
    
    let showCollectionFilterOptions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Collection Filtering
            if showCollectionFilterOptions {
                filterSection(title: "Show Spots") {
                    collectionToggleButton(for: .all, title: "All Spots", icon: "square.stack.3d.up")
                    collectionToggleButton(for: .inCollection, title: "In Collections", icon: "folder.fill")
                    collectionToggleButton(for: .notInCollection, title: "Not in a Collection", icon: "tray.fill")
                }
                
                Divider().padding(.vertical, 8)
            }
            

            // Section 2: Category Filtering
            filterSection(title: "Filter by Category") {
                categoryToggleButton(for: nil) // Button for "All Categories"
                ForEach(SpotCategory.allCases) { category in
                    categoryToggleButton(for: category)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 280) // A good width for a popover menu
    }
    
    /// A view builder for creating a standardized filter section with a title.
    @ViewBuilder
    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 4)
        content()
    }
    
    /// A view builder for a toggle button that controls the collection filter state.
    private func collectionToggleButton(for state: SpotListView.CollectionFilterState, title: String, icon: String) -> some View {
        Button(action: {
            collectionFilterState = state
        }) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if collectionFilterState == state {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    /// A view builder for a toggle button that controls the category filter set.
    private func categoryToggleButton(for category: SpotCategory?) -> some View {
        Button(action: {
            if let categoryToToggle = category {
                if selectedCategoryFilters.contains(categoryToToggle) {
                    selectedCategoryFilters.remove(categoryToToggle)
                } else {
                    selectedCategoryFilters.insert(categoryToToggle)
                }
            } else {
                selectedCategoryFilters.removeAll()
            }
        }) {
            HStack {
                if let category {
                    Label(category.displayName, systemImage: category.systemImageName)
                } else {
                    Label("All Categories", systemImage: "checklist")
                }
                Spacer()
                
                let isSelected = isCategorySelected(category)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
    
    private func isCategorySelected(_ category: SpotCategory?) -> Bool {
        if let category {
            // This is a specific category row, so it's selected if it's in the set.
            return selectedCategoryFilters.contains(category)
        } else {
            // This is the "All Categories" row, so it's selected if the set is empty.
            return selectedCategoryFilters.isEmpty
        }
    }
}
