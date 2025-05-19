//
//  MapView.swift // Ideally SpotsMapView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//
import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject var spotsViewModel: SpotViewModel
    @EnvironmentObject var locationManager: LocationManager

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var viewingRegion: MKCoordinateRegion = MKCoordinateRegion( // For internal logic if needed
        center: CLLocationCoordinate2D(latitude: 37.331516, longitude: -121.891054),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    @State private var selectedSpot: Spot? = nil

    var body: some View {
        Map(position: $cameraPosition, selection: $selectedSpot) { // Add selection binding
            UserAnnotation()

            ForEach(spotsViewModel.spots) { spot in
                Annotation(spot.name, coordinate: spot.coordinate, anchor: .bottom) {
                    VStack(spacing: 0) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundColor(.pink) // Changed color for visibility
                        Text(spot.name)
                            .font(.caption)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                            .background(.regularMaterial) // Use material for better legibility
                            .clipShape(Capsule())
                            .shadow(radius: 1)
                    }
                }
                .tag(spot) // Tag for selection
            }
        }
        .onAppear {
            setupInitialCameraPosition()
        }
        .onChange(of: locationManager.userLocation) { oldLocation, newLocation in
            updateCameraForNewUserLocation(newLocation)
        }
        .onChange(of: selectedSpot) { oldSpot, newSpot in
            // Optional: If a spot is selected, you might want to move the camera to it
            if let spot = newSpot {
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: spot.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02) // Zoom in on selected spot
                    ))
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapPitchToggle()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .bottomTrailing) { // Custom Zoom Buttons
            VStack(spacing: 12) {
                Button { zoomIn() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2).padding(6).background(.regularMaterial, in: Circle()).shadow(radius: 2)
                }
                Button { zoomOut() } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2).padding(6).background(.regularMaterial, in: Circle()).shadow(radius: 2)
                }
            }
            .padding()
            .padding(.bottom, 30) // Adjust if it overlaps tab bar too much
        }
        .sheet(item: $selectedSpot) { spot in // Uses selection binding now
            SpotDetailView(spot: spot)
                .presentationDetents([.medium, .large])
        }
        .alert(isPresented: $locationManager.showGeofenceAlert) {
            Alert(
                title: Text(locationManager.geofenceAlert?.title ?? "Nearby Spot"),
                message: Text(locationManager.geofenceAlert?.body ?? "You are near a saved spot."),
                dismissButton: .default(Text("OK")) { locationManager.geofenceAlert = nil }
            )
        }
        .edgesIgnoringSafeArea(.top)
        // .navigationTitle("Spots Map") // Usually not needed with full-screen map + TabView
        // .navigationBarHidden(true)
    }

    private func setupInitialCameraPosition() {
        if let userLocation = locationManager.userLocation {
            let initialRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            cameraPosition = .region(initialRegion)
            viewingRegion = initialRegion
        } else {
            cameraPosition = .region(viewingRegion) // Use default
        }
    }

    private func updateCameraForNewUserLocation(_ newUserLocation: CLLocation?) {
        guard let userLoc = newUserLocation else { return }
        
        // Only move if user hasn't significantly panned away or if map is somewhat zoomed out
        let currentSpan = viewingRegion.span
        if currentSpan.latitudeDelta > 0.01 { // Heuristic: if not super zoomed in
             let updatedRegion = MKCoordinateRegion(
                center: userLoc.coordinate,
                span: viewingRegion.span // Keep current span or adjust (e.g., MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
            )
            withAnimation {
                cameraPosition = .region(updatedRegion)
            }
            viewingRegion = updatedRegion
        }
    }
    
    private func zoomIn() {
        guard var currentRegion = cameraPosition.currentRegion ?? viewingRegion else { return }
        currentRegion.span = MKCoordinateSpan(
            latitudeDelta: max(currentRegion.span.latitudeDelta / 2, 0.001), // Prevent over-zooming
            longitudeDelta: max(currentRegion.span.longitudeDelta / 2, 0.001)
        )
        withAnimation { cameraPosition = .region(currentRegion) }
        viewingRegion = currentRegion
    }

    private func zoomOut() {
        guard var currentRegion = cameraPosition.currentRegion ?? viewingRegion else { return }
        currentRegion.span = MKCoordinateSpan(
            latitudeDelta: min(currentRegion.span.latitudeDelta * 2, 120), // Cap zoom out
            longitudeDelta: min(currentRegion.span.longitudeDelta * 2, 120)
        )
        withAnimation { cameraPosition = .region(currentRegion) }
        viewingRegion = currentRegion
    }
}

extension MapCameraPosition {
    var currentRegion: MKCoordinateRegion? {
        switch self {
        case .region(let region):
            return region
        // TODO: Implement conversion for other MapCameraPosition cases if you use them
        // e.g., .camera(let mapCamera): return mapCamera.region (MapCamera doesn't directly expose MKCoordinateRegion)
        // You might need to store the region separately or compute it.
        default:
            return nil // Or a sensible default if self is .automatic initially
        }
    }
}

// SpotDetailView remains the same as previously corrected, no changes needed here for these points.
// Spot struct remains the same.

struct SpotsMapView_Previews: PreviewProvider {
    static var previews: some View {
        let spotsVM = SpotViewModel()
        spotsVM.spots = [
            Spot(id: "1", userId: "testUser", name: "Preview Cafe", address: "1 Infinite Loop", latitude: 37.3318, longitude: -122.0312, sourceURL: "https://example.com"),
                         
            Spot(id: "2", userId: "testUser", name: "Preview Park", address: "Golden Gate Park", latitude: 37.7694, longitude: -122.4862)]
        return MapView()
            .environmentObject(spotsVM)
            .environmentObject(LocationManager())
    }
}
