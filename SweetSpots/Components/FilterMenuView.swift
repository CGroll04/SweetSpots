//
//  FilterPopoverView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-07-20.
//

import SwiftUI

struct FilterMenuView: View {
    // Bindings to control the parent view's state
    @Binding var collectionFilterState: SpotListView.CollectionFilterState
    @Binding var selectedCategoryFilters: Set<SpotCategory>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Collection Filtering
            filterSection(title: "Show Spots") {
                // We'll create a button for each state to look like the category rows
                collectionToggleButton(for: .all, title: "All Spots", icon: "square.stack.3d.up")
                collectionToggleButton(for: .inCollection, title: "In Collections", icon: "folder.fill")
                collectionToggleButton(for: .notInCollection, title: "Not in a Collection", icon: "tray.fill")
            }
            
            Divider().padding(.vertical, 8)

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
        .presentationCompactAdaptation(.popover) // Crucial for iPhone to look like a popover
    }
    
    // A generic view for section headers
    @ViewBuilder
    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 4)
        content()
    }
    
    // Button for the Collection Filter State
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

    // Button for the Category Filter
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
                
                let isSelected = (category == nil && selectedCategoryFilters.isEmpty) || (category != nil && selectedCategoryFilters.contains(category!))
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
}
