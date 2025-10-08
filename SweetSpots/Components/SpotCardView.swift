//
//  SpotCardView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//

import SwiftUI
import CoreLocation

struct SpotCardView: View {
    let spot: Spot
    let userLocation: CLLocation?
    let onEdit: () -> Void
    let onDelete: () -> Void
//    let onIncrement: () -> Void
//    let onDecrement: () -> Void
//    let onReset: () -> Void
    let onShare: () -> Void

    @State private var locationDisplay: (icon: String, text: String)?
//    @State private var showUndoBanner = false
//    @State private var undoTimer: Timer? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Leading Category Icon
                Image(systemName: spot.category.systemImageName)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.from(name: spot.category.associatedColor))
                    .clipShape(Circle())
                    .padding(.leading, 12)
                    .padding(.trailing, 10)

                // Main Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(spot.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.themeTextPrimary)
                            .lineLimit(1)
                        
                        // This icon will only appear if notifications are on for this spot
                        if spot.wantsNearbyNotification {
                            Image(systemName: "bell.fill")
                                .font(.caption) // Makes the icon slightly smaller than the text
                                .foregroundStyle(Color.themeAccent) // Use your app's accent color
                        }
                    }

                    HStack(spacing: 6) {
                        if let display = locationDisplay {
                            Label(display.text, systemImage: display.icon)
                                .font(.caption2)
                                .foregroundStyle(Color.themeTextSecondary)
                                .lineLimit(1)
                        }
                        
//                        if spot.visitCount > 0 {
//                            Text("Visited: \(spot.visitCount)")
//                                .font(.caption2)
//                                .foregroundStyle(Color.themeAccent)
//                                .padding(.horizontal, 6)
//                                .padding(.vertical, 3)
//                                .background(Color.themeAccent.opacity(0.1))
//                                .clipShape(Capsule())
//                        }
                    }
                    
                    if let sender = spot.senderName {
                        Label(sender, systemImage: "square.and.arrow.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 10)

                Spacer()

                // Actions Menu
                ActionsMenuView(
                    spot: spot,
                    onEdit: onEdit,
                    onDelete: onDelete,
//                    onIncrement: onIncrement,
//                    onDecrement: onDecrement,
//                    onReset: onReset,
                    onShare: onShare
                )
                .padding(.trailing, 6)
                

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.themeTextSecondary.opacity(0.6))
                    .padding(.trailing, 10)
            }
            .frame(minHeight: 70)
            .padding(.vertical, 6)
            .background(Material.thin)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                    RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1),
                        lineWidth: 1
                    )
                }
            .task(id: spot.id) {
                await updateLocationDisplay()
            }
            .contextMenu {
                contextMenuContent
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                // This code now runs only after the long press is successful
                hapticGenerator.impactOccurred()
            }


            // Undo Popup
//            if showUndoBanner {
//                HStack {
//                    Text("Marked as visited")
//                    Spacer()
//                    Button("Undo") {
//                        onDecrement()
//                        undoTimer?.invalidate()
//                        showUndoBanner = false
//                    }
//                }
//                .font(.footnote)
//                .foregroundStyle(Color.white)
//                .padding()
//                .background(Color.black.opacity(0.9))
//                .clipShape(RoundedRectangle(cornerRadius: 10))
//                .padding(.horizontal, 12)
//                .transition(.move(edge: .bottom).combined(with: .opacity))
//                .animation(.easeInOut, value: showUndoBanner)
//            }
        }
    }

//    private func showUndoPopupTemporarily() {
//        withAnimation {
//            showUndoBanner = true
//        }
//        undoTimer?.invalidate()
//        undoTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
//            withAnimation {
//                showUndoBanner = false
//            }
//        }
//    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button(action: onEdit) {
            Label("Edit Spot", systemImage: "pencil")
        }
        
        Button(action: onShare) {
            Label("Share Spot", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button(role: .destructive, action: onDelete) {
            Label("Delete Spot", systemImage: "trash")
        }
    }
    
    private func updateLocationDisplay() async {
        // Guard against no user location
        guard let userLoc = userLocation else {
            // If no user location, just show city/country
            locationDisplay = await geocodeSpotLocation()
            return
        }

        let spotLoc = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let distanceInMeters = userLoc.distance(from: spotLoc)
        
        // Set a 100km threshold
        let distanceThreshold: CLLocationDistance = 50_000

        if distanceInMeters <= distanceThreshold {
            // Within threshold: show precise distance
            locationDisplay = (icon: "location.north.fill", text: distanceInMeters.formattedAsDistance())
        } else {
            // Outside threshold: show city and country
            locationDisplay = await geocodeSpotLocation()
        }
    }
    
    private func geocodeSpotLocation() async -> (icon: String, text: String) {
        let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let geocoder = CLGeocoder()
        
        if let placemark = try? await geocoder.reverseGeocodeLocation(spotLocation).first {
            let city = placemark.locality ?? ""
            let country = placemark.country ?? ""
            
            if !city.isEmpty && !country.isEmpty {
                return (icon: "globe.americas.fill", text: "\(city), \(country)")
            } else if !city.isEmpty {
                return (icon: "globe.americas.fill", text: city)
            } else if !country.isEmpty {
                return (icon: "globe.americas.fill", text: country)
            }
        }
        
        // Fallback if geocoding fails
        return (icon: "map.fill", text: "Location loading...")
    }
}
