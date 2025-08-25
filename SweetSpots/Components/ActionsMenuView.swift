//
//  ActionsMenuView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-07-20.
//

import SwiftUI

struct ActionsMenuView: View {
    let spot: Spot
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onReset: () -> Void

    var body: some View {
        Menu {
            Button {
                onIncrement()
            } label: {
                Label("Add Visit", systemImage: "plus")
            }

            if spot.visitCount > 0 {
                Divider()
                
                Button {
                    onDecrement()
                } label: {
                    Label("Remove Visit", systemImage: "minus")
                }
                
                Button(role: .destructive) {
                    onReset()
                } label: {
                    Label("Reset Visits", systemImage: "arrow.counterclockwise")
                }
            }
            
            Divider()
            
            Button {
                onEdit()
            } label: {
                Label("Edit Spot", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Spot", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.themePrimary) // Use theme color for consistency
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}
