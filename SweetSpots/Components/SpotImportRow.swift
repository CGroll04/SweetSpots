//
//  SpotImportRow.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//

import SwiftUI

struct SpotImportRow: View {
    @Binding var importableSpot: ImportableSpot

    var body: some View {
        HStack {
            // Display an icon based on the import state
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text(importableSpot.payload.name).fontWeight(.semibold)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // Helper properties to determine the row's appearance
    private var iconName: String {
        switch importableSpot.state {
        case .new: return "checkmark.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .resolved(let resolution):
            switch resolution {
            case .keepOriginal: return "shield.slash.fill"
            case .updateWithImported: return "checkmark.circle.fill"
            case .saveAsDuplicate: return "plus.circle.fill"
            }
        }
    }

    private var iconColor: Color {
        switch importableSpot.state {
        case .new: return .green
        case .conflict: return .orange
        case .resolved: return .blue
        }
    }

    private var statusText: String {
        switch importableSpot.state {
        case .new: return "Ready to import."
        case .conflict: return "Conflict: You already have this spot."
        case .resolved(let resolution): return "Resolved: \(resolution.rawValue)."
        }
    }
}
