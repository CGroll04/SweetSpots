//
//  ImportState.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-04.
//

import Foundation

/// The user's choice for resolving a conflict
enum ResolutionChoice: String, Equatable {
    case keepOriginal = "Keep My Original Spot"
    case appendNotes = "Add Shared Notes to My Spot"
    case replaceSpot = "Replace My Spot with Shared One"
}

/// The state of an individual spot being imported
enum ImportState: Equatable {
    /// This spot is completely new to the user
    case new
    /// This spot conflicts with one the user already has
    case conflict(existingSpot: Spot)
    /// The user has resolved a conflict with a specific choice
    case resolved(choice: ResolutionChoice)
    
    // We need to implement Equatable manually for the associated value
    static func == (lhs: ImportState, rhs: ImportState) -> Bool {
        switch (lhs, rhs) {
        case (.new, .new):
            return true
        case (.conflict(let lhsSpot), .conflict(let rhsSpot)):
            return lhsSpot.id == rhsSpot.id
        case (.resolved(let lhsChoice), .resolved(let rhsChoice)):
            return lhsChoice == rhsChoice
        default:
            return false
        }
    }
}

/// A wrapper struct to combine an incoming spot with its import state
struct ImportableSpot: Identifiable {
    let id = UUID()
    let payload: SharedSpotPayload
    var state: ImportState
    
    let existingSpot: Spot? // This will hold the conflicting spot
    
    var addExistingToCollection: Bool = true
}
