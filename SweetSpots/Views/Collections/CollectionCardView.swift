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
    let spotCount: Int
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 1. The attractive gradient background
            backgroundGradient
            
            // 2. The main content (Name and Spot Count)
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2) // Allow name to wrap to two lines
                    .shadow(radius: 2) // Makes text readable on any background

                VStack(alignment: .leading, spacing: 2) {
                    if let description = collection.descriptionText, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1) // Show only one line of the description
                    }
                    
                    Text("\(spotCount) \(spotCount == 1 ? "Spot" : "Spots")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                }
                .shadow(radius: 1)
            }
            .padding()

            // 3. A small icon in the corner if the collection is public
            if collection.isPublic {
                Image(systemName: "globe")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.black.opacity(0.25))
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            }
        }
        .frame(height: 150) // Ensures all cards in the grid are the same size
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // Helper view for the gradient to keep the main body clean
    private var backgroundGradient: some View {
        Group { // Use Group to conditionally apply different backgrounds
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hue: 0.75, saturation: 0.6, brightness: 0.55), // Brighter, rich purple
                        Color(hue: 0.7, saturation: 0.5, brightness: 0.4)   // Darker purple, but still brighter
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else { // Light Mode
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hue: 0.75, saturation: 0.5, brightness: 0.75), // Muted light purple
                        Color(hue: 0.7, saturation: 0.3, brightness: 0.9)    // Very light, almost white purple
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}
