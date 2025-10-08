//
//  CollectionCardView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-08.
//

import SwiftUI

/// A card-style view that displays a summary of a single spot collection.
struct CollectionCardView: View {
    let collection: SpotCollection
    let spotsInCollection: [Spot]
    
    let onSharePrivately: () -> Void
    let onSharePublicly: () -> Void
    let onEditDetails: () -> Void
    let onManageSpots: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

    private var sortedCategories: [SpotCategory] {
        // Create a frequency dictionary
        let categoryCounts = spotsInCollection.reduce(into: [:]) { counts, spot in
            counts[spot.category, default: 0] += 1
        }
        // Sort the dictionary by count (descending) and return the categories
        return categoryCounts.sorted { $0.value > $1.value }.map { $0.key }
    }
    
    var body: some View {
        ZStack{
            // 1. The attractive gradient background
            backgroundGradient
            
            Menu {
                Button(action: onSharePrivately) {
                    Label("Share Privately...", systemImage: "person.2.fill")
                }
                Button(action: onSharePublicly) {
                    Label("Share Publicly...", systemImage: "globe")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.black.opacity(0.3))
                    .clipShape(Circle())
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            
            VStack(spacing:8){
                Spacer(minLength: 0)
                
                // 1. Emoji
                if let emoji = collection.emoji {
                    Text(emoji)
                        .font(.system(size: 50))
                }
                
                Spacer(minLength: 0)
                
                // 2. The main content (Name and Spot Count)
                VStack(alignment: .leading, spacing: 4) {
                    // 2. Collection Name
                    Text(collection.name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(2)
                    
                    // 3. Description
                    if let description = collection.descriptionText, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .lineLimit(1)
                            .opacity(0.9)
                    }
                    
                    // 4. Number of Spots
                    Text("\(spotsInCollection.count) \(spotsInCollection.count == 1 ? "Spot" : "Spots")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .opacity(0.8)
                    
                    if let sender = collection.senderName {
                        Label(sender, systemImage: "square.and.arrow.down")
                            .font(.caption)
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                    
                    // 5. Category Icons
                    categoryIcons
                        .padding(.top, 2)
                        
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.25)) // Adds a background for readability
            }
            .foregroundColor(.white)
            .shadow(radius: 2) // Makes text readable on any background
        }
        .frame(height: 200) // Ensures all cards in the grid are the same size
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            contextMenuContent
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            // This code now runs only after the long press is successful
            hapticGenerator.impactOccurred()
        }
    }
    
    @ViewBuilder
    private var categoryIcons: some View {
        HStack(spacing: 8) {
            ForEach(sortedCategories.prefix(5), id: \.self) { category in
                Image(systemName: category.systemImageName)
                    .font(.caption)
                    .opacity(0.8)
            }
            

            if sortedCategories.count > 5 {
                Text("+\(sortedCategories.count - 5)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .opacity(0.8)
            }
        }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        
        Button(action: onEditDetails) {
            Label("Edit Details", systemImage: "pencil")
        }
        
        Button(action: onManageSpots) {
            Label("Edit Spots in Collection", systemImage: "checklist")
        }
        
        Menu {
            Button(action: onSharePrivately) {
                Label("Share Privately...", systemImage: "person.2.fill")
            }
            Button(action: onSharePublicly) {
                Label("Share Publicly...", systemImage: "globe")
            }
        } label: {
            Label("Share Collection", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button(role: .destructive, action: onDelete) {
            Label("Delete Collection", systemImage: "trash")
        }
    }
    
    // Helper view for the gradient to keep the main body clean
    private var backgroundGradient: some View {
        let colors = Color.gradient(for: collection.id ?? "")
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
