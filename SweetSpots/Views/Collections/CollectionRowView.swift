//
//  CollectionRowView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-09.
//

import SwiftUI

/// A view that displays a single collection row with selection state and an edit button.
struct CollectionRowView: View {
    let collection: SpotCollection
    let isSelected: Bool
    var onEdit: () -> Void // Closure to trigger editing

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "folder.fill")
                .foregroundColor(isSelected ? Color.themePrimary : .secondary)
            Text(collection.name)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Button {
                onEdit()
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.gray)
            }
            .buttonStyle(BorderlessButtonStyle()) // Important for list row behavior
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // Makes the whole HStack tappable for selection if wrapped in Button
    }
}
