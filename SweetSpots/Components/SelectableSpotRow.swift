//
//  SelectableSpotRow.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//
import SwiftUI

// A new, dedicated view for a selectable spot row.
struct SelectableSpotRow: View {
    let spot: Spot
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: spot.category.systemImageName)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.from(name: spot.category.associatedColor))
                .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(spot.name)
                    .fontWeight(.semibold)
                Text(spot.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.themeAccent)
            }
        }
        .padding(.vertical, 6)
    }
}
