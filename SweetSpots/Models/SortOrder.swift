//
//  SortOrder.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//
import SwiftUI

enum SortOrder: String, CaseIterable, Identifiable {
    case dateDescending = "Newest First"
    case dateAscending = "Oldest First"
    case nameAscending = "Name (A-Z)"
    case nameDescending = "Name (Z-A)"
    case categoryAscending = "Category (A-Z)"
    case distanceAscending = "Distance (Nearest)"
    var id: String { self.rawValue }
}
