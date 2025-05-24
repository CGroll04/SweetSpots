//
//  SpotDetailView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-19.
//

import SwiftUI
import MapKit

struct SpotDetailView: View {
    let spot: Spot
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Title
                Text(spot.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Map Preview
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: spot.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                ) {
                    Marker(spot.name, coordinate: spot.coordinate)
                }
                .frame(height: 200)
                .cornerRadius(12)
                
                // Placeholder for additional info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Source:")
                        .font(.headline)
                    Text(spot.sourceURL ?? "Unknown")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Spot Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
