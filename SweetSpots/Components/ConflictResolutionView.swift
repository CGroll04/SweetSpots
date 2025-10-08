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
    @State private var selectedChoice: ResolutionChoice
    @State private var addExistingToCollection: Bool
    
    init(importableSpot: Binding<ImportableSpot>) {
        self._importableSpot = importableSpot
        
        // Set the initial choice based on the spot's current state
        if case .resolved(let choice) = importableSpot.wrappedValue.state {
            self._selectedChoice = State(initialValue: choice)
        } else {
            self._selectedChoice = State(initialValue: .keepOriginal) // Default choice
        }
        // Set the initial toggle state
        self._addExistingToCollection = State(initialValue: importableSpot.wrappedValue.addExistingToCollection)
    }

    var body: some View {
        NavigationView {
            Form {
                if let existingSpot = importableSpot.existingSpot {
                    Section("Conflict Detected") {
                        Text("You already have a spot at this address named '\(existingSpot.name)'.")
                    }
                    
                    Section("How would you like to resolve this?") {
                        Picker("Action", selection: $selectedChoice) { // Bind to local state
                            // You can add .allCases to ResolutionChoice to generate this automatically
                            Text(ResolutionChoice.keepOriginal.rawValue).tag(ResolutionChoice.keepOriginal)
                            Text(ResolutionChoice.appendNotes.rawValue).tag(ResolutionChoice.appendNotes)
                            Text(ResolutionChoice.replaceSpot.rawValue).tag(ResolutionChoice.replaceSpot)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        
                        if canAddToCollection() {
                            Toggle("Add my existing spot to this new collection", isOn: $addExistingToCollection)
                                .animation(.default, value: canAddToCollection())
                        }
                    }
                }
            }
            .navigationTitle("Resolve Conflict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // The "Done" button now saves the local state back to the binding
                    Button("Done") {
                        importableSpot.state = .resolved(choice: selectedChoice)
                        importableSpot.addExistingToCollection = addExistingToCollection
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func canAddToCollection() -> Bool {
        return selectedChoice == .keepOriginal || selectedChoice == .appendNotes
    }
}
