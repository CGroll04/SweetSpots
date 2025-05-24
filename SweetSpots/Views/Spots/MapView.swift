//
//  MapView.swift // Ideally SpotsMapView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//
import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var locationManager: LocationManager
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var viewingRegion: MKCoordinateRegion = .init(
        center: CLLocationCoordinate2D(latitude: 37.331516, longitude: -121.891054),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    @State private var selectedSpot: Spot?
    @State private var isUserTracking = true
    
    var body: some View {
        Map(position: $cameraPosition, selection: $selectedSpot) {
            UserAnnotation()
            
            ForEach(spotsViewModel.spots) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    SpotAnnotationView(spot: spot)
                }
                .tag(spot)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapPitchToggle()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .bottomTrailing) {
            MapControlsOverlay(
                isUserTracking: $isUserTracking,
                onZoomIn: zoomIn,
                onZoomOut: zoomOut
            )
        }
        .sheet(item: $selectedSpot) { spot in
            SpotDetailView(spot: spot)
                .presentationDetents([.medium, .large])
        }
        .alert("Nearby Spot", isPresented: $locationManager.showGeofenceAlert) {
            Button("OK") {
                locationManager.geofenceAlert = nil
            }
        } message: {
            Text(locationManager.geofenceAlert?.body ?? "You are near a saved spot.")
        }
        .task {
            setupInitialCameraPosition()
        }
        .onChange(of: locationManager.userLocation) { _, newLocation in
            if isUserTracking {
                updateCameraForNewUserLocation(newLocation)
            }
        }
        .onChange(of: selectedSpot) { _, newSpot in
            if let spot = newSpot {
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: spot.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))
                }
            }
        }
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
            cameraPosition = .region(viewingRegion)
        }
    }
    
    private func updateCameraForNewUserLocation(_ newUserLocation: CLLocation?) {
        guard let userLoc = newUserLocation else { return }

        let updatedRegion = MKCoordinateRegion(
            center: userLoc.coordinate,
            span: viewingRegion.span // keep same zoom level
        )
        
        withAnimation {
            cameraPosition = .region(updatedRegion)
        }
        viewingRegion = updatedRegion
    }
    
    private func zoomIn() {
        var currentRegion = viewingRegion
        currentRegion.span = MKCoordinateSpan(
            latitudeDelta: max(currentRegion.span.latitudeDelta / 2, 0.001),
            longitudeDelta: max(currentRegion.span.longitudeDelta / 2, 0.001)
        )
        withAnimation {
            cameraPosition = .region(currentRegion)
        }
        viewingRegion = currentRegion
    }
    
    private func zoomOut() {
        var currentRegion = viewingRegion
        currentRegion.span = MKCoordinateSpan(
            latitudeDelta: min(currentRegion.span.latitudeDelta * 2, 120),
            longitudeDelta: min(currentRegion.span.longitudeDelta * 2, 120)
        )
        withAnimation {
            cameraPosition = .region(currentRegion)
        }
        viewingRegion = currentRegion
    }
}

// MARK: - Supporting Views
private struct SpotAnnotationView: View {
    let spot: Spot
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            
            Text(spot.name)
                .font(.caption)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(radius: 1)
        }
    }
}

private struct MapControlsOverlay: View {
    @Binding var isUserTracking: Bool
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Button {
                isUserTracking.toggle()
            } label: {
                Image(systemName: isUserTracking ? "location.fill" : "location")
                    .font(.title2)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .shadow(radius: 2)
            }
            
            Button(action: onZoomIn) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .shadow(radius: 2)
            }
            
            Button(action: onZoomOut) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .shadow(radius: 2)
            }
        }
        .padding()
        .padding(.bottom, 30)
    }
}

#Preview {
    MapView()
        .environmentObject(SpotViewModel())
        .environmentObject(LocationManager())
}
