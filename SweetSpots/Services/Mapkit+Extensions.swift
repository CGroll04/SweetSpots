//
//  Mapkit+Extensions.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-20.
//

import MapKit

extension MKLocalSearchCompletion {
    /// Combines title and subtitle for display, avoiding redundancy if subtitle is empty or same as title.
    func titleWithSubtitle() -> String {
        var displayString = title
        if !subtitle.isEmpty && subtitle.lowercased() != title.lowercased() {
            displayString += ", \(subtitle)"
        }
        return displayString
    }
}

