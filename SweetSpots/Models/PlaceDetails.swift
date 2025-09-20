//
//  PlaceDetails.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//
import SwiftUI
import MapKit

// MARK: - Supporting Types
struct PlaceDetails {
    let name: String
    let fullAddress: String
    let coordinates: CLLocationCoordinate2D
    let phoneNumber: String?
    let websiteURL: URL?
}

enum PlaceDetailsError: LocalizedError {
    case noDetailsFound
    
    var errorDescription: String? {
        switch self {
        case .noDetailsFound:
            return "Could not find details for this location"
        }
    }
}
