//
//  ConflictResolutionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-04.
//

import SwiftUI

struct ConflictResolutionView: View {
    @Binding var importableSpot: ImportableSpot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Resolve Conflict")
                        .font(.largeTitle).fontWeight(.bold)
                    
                    Text("You already have a spot named **\(importableSpot.payload.name)**. How would you like to proceed?")
                    
                    Divider()
                    
                    // Display existing and imported data side-by-side
                    VStack(alignment: .leading) {
                        Text("Your Existing Spot").font(.headline)
                        if case .conflict(let existingSpot) = importableSpot.state {
                            Text("Notes: \(existingSpot.notes ?? "None")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("New Imported Spot").font(.headline)
                        Text("Notes: \(importableSpot.payload.notes ?? "None")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    Divider()

                    // Action Buttons
                    VStack(spacing: 12) {
                        resolveButton(
                            title: "Keep My Original Spot",
                            subtitle: "The imported spot will be ignored.",
                            icon: "shield.fill",
                            resolution: .keepOriginal
                        )
                        
                        resolveButton(
                            title: "Update My Spot",
                            subtitle: "Your existing spot will be updated with the imported notes and info.",
                            icon: "arrow.triangle.2.circlepath.circle.fill",
                            resolution: .updateWithImported
                        )
                        
                        resolveButton(
                            title: "Save as a New Duplicate",
                            subtitle: "A second copy of this spot will be added to your list.",
                            icon: "plus.square.on.square.fill",
                            resolution: .saveAsDuplicate
                        )
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    // Helper for creating the choice buttons
    private func resolveButton(title: String, subtitle: String, icon: String, resolution: ConflictResolution) -> some View {
        Button(action: {
            importableSpot.state = .resolved(resolution: resolution)
            dismiss()
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 40)
                VStack(alignment: .leading) {
                    Text(title).fontWeight(.semibold)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
