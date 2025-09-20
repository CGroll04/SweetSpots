//
//  CollectionSpotRow.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-08.
//

import SwiftUI
import CoreLocation

/// A view that displays a single spot as a row, showing its name, icon, and distance from the user.
struct CollectionSpotRow: View {
    let spot: Spot
    
    @EnvironmentObject private var locationManager: LocationManager
    
    // 1. A simple state variable to hold the final calculated text.
    @State private var locationDisplayText: String = ""

    var body: some View {
        HStack(spacing: 12) {
            // Category Icon
            Image(systemName: spot.category.systemImageName)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.from(name: spot.category.associatedColor))
                .clipShape(Circle())

            // Main Content
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.headline)
                    .lineLimit(1)
                
                // 2. The Text view now displays our state variable.
                // It shows the address by default until the distance is calculated.
                Text(locationDisplayText.isEmpty ? spot.address : locationDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        // 3. This modifier runs the async function when the view appears.
        .task {
            await updateLocationDisplay()
        }
    }
    
    // 4. The async logic is now simplified and updates the state.
    private func updateLocationDisplay() async {
        guard let userLocation = locationManager.userLocation else {
            // If we don't have the user's location, just use the address.
            locationDisplayText = spot.address
            return
        }

        let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let distanceInMeters = userLocation.distance(from: spotLocation)
        
        // Update the state variable on the main thread.
        locationDisplayText = distanceInMeters.formattedAsDistance()
    }
}
