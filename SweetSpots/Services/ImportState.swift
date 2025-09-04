//
//  ImportState.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-04.
//

import Foundation

// The user's choice for resolving a conflict
enum ConflictResolution: String {
    case keepOriginal = "Keep Original"
    case updateWithImported = "Update"
    case saveAsDuplicate = "Save as Duplicate"
}

// The state of an individual spot being imported
enum ImportState: Equatable {
    // This spot is completely new to the user
    case new
    
    // This spot conflicts with one the user already has
    case conflict(existingSpot: Spot)
    
    // The user has resolved a conflict with a specific choice
    case resolved(resolution: ConflictResolution)
    
    // We need to implement Equatable manually for the associated value
    static func == (lhs: ImportState, rhs: ImportState) -> Bool {
        switch (lhs, rhs) {
        case (.new, .new):
            return true
        case (.conflict(let lhsSpot), .conflict(let rhsSpot)):
            return lhsSpot.id == rhsSpot.id
        case (.resolved(let lhsRes), .resolved(let rhsRes)):
            return lhsRes == rhsRes
        default:
            return false
        }
    }
}

// A wrapper struct to combine an incoming spot with its import state
struct ImportableSpot: Identifiable, Equatable {
    let id = UUID() // Use UUID for identifiable conformance in the list
    let payload: SharedSpotPayload
    var state: ImportState
    
    static func == (lhs: ImportableSpot, rhs: ImportableSpot) -> Bool {
        return lhs.id == rhs.id && lhs.state == rhs.state
    }
}
