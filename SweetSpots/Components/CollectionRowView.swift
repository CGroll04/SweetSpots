//
//  CollectionRowView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-09.
//

import SwiftUI

struct CollectionRowView: View {
    let collection: SpotCollection
    let isSelected: Bool
    var onEdit: () -> Void // Closure to trigger editing

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "folder.fill") // Example icons
                .foregroundColor(isSelected ? Color.themePrimary : .secondary)
            Text(collection.name)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Button {
                onEdit()
            } label: {
                Image(systemName: "ellipsis.circle") // Or "pencil", "slider.horizontal.3"
                    .foregroundColor(.gray)
            }
            .buttonStyle(BorderlessButtonStyle()) // Important for list row behavior
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // Makes the whole HStack tappable for selection if wrapped in Button
    }
}

// Simple Preview for CollectionRowView
#Preview {
    VStack {
        CollectionRowView(
            collection: SpotCollection(id: "1", userId: "uid", name: "Summer Trip", descriptionText: "Fun times"),
            isSelected: true,
            onEdit: { print("Edit Summer Trip") }
        )
        CollectionRowView(
            collection: SpotCollection(id: "2", userId: "uid", name: "Local Cafes"),
            isSelected: false,
            onEdit: { print("Edit Local Cafes") }
        )
    }
    .padding()
    .environmentObject(CollectionViewModel()) // If it ever needs it directly
}
