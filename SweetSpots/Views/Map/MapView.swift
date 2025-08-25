//
//  MapView.swift
//  SweetSpots
//
//  Enhanced version with geofencing integration
//

import SwiftUI
import MapKit

struct MapView: View {
    // MARK: - Environment Objects
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var navigationViewModel: NavigationViewModel
    

    // MARK: - State Variables
    @State private var showingAddSheet: Bool = false // 1. ADD THIS STATE
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var viewingRegion: MKCoordinateRegion? = nil
    
    @State private var selectedSpotIdForSheet: String? = nil
    @State private var selectedSpot: Spot? = nil
    @State private var selectedSpotId: String? = nil
    
    @State private var showClarityPopup: Bool = false
    @State private var popupTask: Task<Void, Never>?
    
    @State private var isNavigating: Bool = false // <<<< NEW: To track

    @State private var selectedCategoryFilters: Set<SpotCategory> = []
    @State private var initialCameraHasBeenSet = false
    
    @State private var showGeofenceRadii: Bool = false
    @AppStorage("globalGeofencingEnabled") private var globalGeofencingEnabled: Bool = true
    
    // MARK: - Computed Properties
    private var spotsForMap: [Spot] {
        if selectedCategoryFilters.isEmpty {
            return spotsViewModel.spots
        } else {
            return spotsViewModel.spots.filter { selectedCategoryFilters.contains($0.category) }
        }
    }
    
    private var spotsWithGeofences: [Spot] {
        spotsForMap.filter { $0.wantsNearbyNotification && globalGeofencingEnabled }
    }
    
    private var selectedSpotForAnnotation: Spot? {
        guard let selectedId = selectedSpotId else { return nil }
        return spotsViewModel.spots.first { $0.id == selectedId }
    }
    
    private var isShowingSpotSheet: Binding<Bool> {
        Binding(
            get: { selectedSpotIdForSheet != nil },
            set: { isShowing in
                if !isShowing {
                    selectedSpotIdForSheet = nil
                    selectedSpotId = nil
                }
            }
        )
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) { // Use ZStack to overlay navigation UI
                // mapViewWithOverlays should have NO modifiers here
                mapViewWithOverlays

                RouteSelectionView(navigationViewModel: navigationViewModel)

                
                geofenceClarityOverlay()
            
                // Show turn-by-turn UI when navigating
                if navigationViewModel.isNavigating {
                    VStack {
                        TurnByTurnInstructionView()
                        Spacer()
                        EndNavigationButton()
                            .padding(.bottom, 100)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
                
                // Show "Calculating..." overlay
                if navigationViewModel.isCalculatingRoute {
                    RouteInfoCard(message: "Calculating route...")
                }
                
                // Show error overlay
                if let error = navigationViewModel.routeCalculationError {
                    RouteInfoCard(message: error, isError: true) {
                        navigationViewModel.stopNavigation() // Let the user dismiss the error
                    }
                }
            }
            .onAppear { handleInitialLocationSetup() }
            .task { await fallbackInitialCameraIfNeeded() }
            .onChange(of: locationManager.userLocation, handleLocationChange)
            .onChange(of: selectedSpot, handleSpotSelection)
            .onChange(of: navigationViewModel.route, handleRouteChange)
            .onChange(of: navigationViewModel.isNavigating) { _, isNavigating in
                if isNavigating, let userLocation = locationManager.userLocation {
                    // When navigation starts, immediately snap the camera to the user's location in navigation mode.
                    updateCameraForNavigation(userLocation: userLocation)
                }
            }
            .onChange(of: showClarityPopup) {
                // When the popup appears...
                if showClarityPopup {
                    // ...cancel any previous timer that might still be running...
                    popupTask?.cancel()
                    
                    // ...and start a new one.
                    popupTask = Task {
                        // Wait for 2 seconds
                        try? await Task.sleep(for: .seconds(2))
                        
                        // Now, hide the popup with an animation
                        withAnimation {
                            showClarityPopup = false
                        }
                    }
                }
            }
            .toolbar {
                // Do not show the toolbar during turn-by-turn navigation
                if !navigationViewModel.isNavigating {
                    // Title on the left
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Text("My SweetSpots")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    // Buttons on the right
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        geofenceToggleButton()
                        mapCategoryFilterMenu()
                        
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Color.themePrimary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddSpotView(isPresented: $showingAddSheet, spotToEdit: nil, prefilledURL: nil)
                    .environmentObject(spotsViewModel)
                    .environmentObject(authViewModel)
                    .environmentObject(locationManager)
                    .environmentObject(collectionViewModel)
                    .environmentObject(navigationViewModel)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(navigationViewModel.isNavigating)
            .animation(.default, value: navigationViewModel.isNavigating)
            .animation(.default, value: navigationViewModel.isCalculatingRoute)
        }
    }
    
    // MARK: - Map Content and Overlays
    @ViewBuilder
    private func geofenceClarityOverlay() -> some View {
        if showClarityPopup {
            VStack {
                Spacer() // Pushes to center
                
                HStack {
                    Image(systemName: showGeofenceRadii ? "bell.circle.fill" : "bell.circle")
                    Text(showGeofenceRadii ? "Showing Alert Zones" : "Hiding Alert Zones")
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(radius: 5)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                
                Spacer()
            }
            .padding(.bottom, 100)
            .allowsHitTesting(false)
        }
    }
    
    // This is the core Map view.
    private var coreMapView: some View {
        Map(position: $cameraPosition, selection: $selectedSpot) {
            UserAnnotation()
            
            if let route = navigationViewModel.route {
                MapPolyline(route.polyline).stroke(Color.blue.opacity(0.8), lineWidth: 6)
            }
            
            ForEach(spotsForMap) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    SpotAnnotationView(spot: spot, isSelected: spot.id == selectedSpot?.id)
                        .onTapGesture { selectedSpot = spot }
                }
                .tag(spot)
            }
            
            if showGeofenceRadii {
                ForEach(spotsWithGeofences) { spot in
                    MapCircle(center: spot.coordinate, radius: spot.notificationRadiusMeters)
                        .foregroundStyle(Color.blue.opacity(0.2)).stroke(Color.blue.opacity(0.6), lineWidth: 2)
                }
            }
        }
    }
    
    // Chain modifiers onto the core map view. This breaks up the expression.
    private var mapViewWithOverlays: some View {
        coreMapView
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all, showsTraffic: false))
            .mapControls { MapPitchToggle(); MapCompass() }
            .overlay(alignment: .bottomTrailing) {
                MapZoomControls(
                    currentRegion: $viewingRegion, // Pass the binding
                    cameraPosition: $cameraPosition
                )
                .environmentObject(locationManager)
                .padding(.trailing, 15)
                .padding(.bottom, 80)
            }
            .overlay(alignment: .topLeading) { // <<<< SINGLE .topLeading OVERLAY
                VStack(alignment: .leading, spacing: 8) { // Arrange vertically
                    // Always show route info if it exists
                    if navigationViewModel.isCalculatingRoute || navigationViewModel.route != nil || navigationViewModel.routeCalculationError != nil {
                        RouteInfoCard()
                    }

                    // Show geofence status if applicable and no route is showing
                    // Or you can decide to show both. Let's show both.
                    if globalGeofencingEnabled && !spotsWithGeofences.isEmpty {
                        geofenceStatusOverlay()
                    }
                }
            }
            .sheet(item: $selectedSpot) { spot in
                // We now initialize SpotDetailView with the ID from the selected spot.
                SpotDetailView(spotId: spot.id ?? "", presentedFrom: .map)
                    .environmentObject(authViewModel)
                    .environmentObject(spotsViewModel)
                    .environmentObject(locationManager)
                    .environmentObject(collectionViewModel)
                    .environmentObject(navigationViewModel)
                    .presentationDetents([.medium, .large])
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                self.viewingRegion = context.region
            }
            .ignoresSafeArea() // Ignores safe area for the map only
    }
    
    private func geofenceToggleButton() -> some View {
        Button {
            withAnimation {
                // Toggle the state for the blue circles
                showGeofenceRadii.toggle()
                // And separately, trigger the informational popup
                showClarityPopup = true
            }
        } label: {
            Image(systemName: showGeofenceRadii ? "bell.circle.fill" : "bell.circle")
                .foregroundStyle(showGeofenceRadii ? Color.blue : Color.themePrimary)
                .symbolEffect(.bounce, value: showGeofenceRadii)
        }
    }
    
    private func geofenceStatusOverlay() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                
                // This now correctly shows "1 Active Alert" or "X Active Alerts"
                Text("\(spotsWithGeofences.count) Active Alert\(spotsWithGeofences.count == 1 ? "" : "s")")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            if locationManager.authorizationStatus != .authorizedAlways {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    
                    Text("Need Always Permission")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 16)
        .padding(.top, 16)
    }
    
    // MARK: - Filter Menu (Enhanced)
    private func mapCategoryFilterMenu() -> some View {
        Menu {
            Section("Filter by Category") {
                Button(action: { selectedCategoryFilters.removeAll() }) {
                    Label("All Categories", systemImage: selectedCategoryFilters.isEmpty ? "checkmark.circle.fill" : "circle")
                }
                Divider()
                ForEach(SpotCategory.allCases) { category in
                    Toggle(isOn: Binding(
                        get: { selectedCategoryFilters.contains(category) },
                        set: { isSelected in
                            if isSelected { selectedCategoryFilters.insert(category) }
                            else { selectedCategoryFilters.remove(category) }
                        }
                    )) {
                        Label(category.displayName, systemImage: category.systemImageName)
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: selectedCategoryFilters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Color.themePrimary)
        }
    }
    
    // MARK: - Enhanced Location and Navigation Logic
    private func handleInitialLocationSetup() {
        if locationManager.userLocation == nil {
            locationManager.requestLocationAuthorization(aimForAlways: false)
        }
        
        if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingUserLocation()
        }
        
        if let userCoordinate = locationManager.userLocation?.coordinate, !initialCameraHasBeenSet {
            print("MapView: User location available on appear, setting initial camera.")
            let userRegion = MKCoordinateRegion(
                center: userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            cameraPosition = .region(userRegion)
            viewingRegion = userRegion
            initialCameraHasBeenSet = true
        }
    }
    
    private func handleLocationChange(_ oldLocation: CLLocation?, _ newLocation: CLLocation?) {
        // This is still the same and still crucial for the camera
        if let userCoordinate = newLocation?.coordinate, !initialCameraHasBeenSet {
            setInitialCamera(to: userCoordinate)
        }
        
        // Let NavigationViewModel handle updates. We just update the camera.
        if navigationViewModel.isNavigating, let newLocation = newLocation {
            updateCameraForNavigation(userLocation: newLocation)
        }
    }
    
    private func handleRouteChange(_ oldRoute: MKRoute?, _ newRoute: MKRoute?) {
        // This function is now just for setting the camera when a route first appears
        if let route = newRoute, !navigationViewModel.isNavigating {
            // This case should not happen in the new flow, but as a fallback:
            let rect = route.polyline.boundingMapRect
            withAnimation(.easeOut(duration: 0.7)) { cameraPosition = .rect(rect.paddedBy(factor: 1.4)) }
        } else if newRoute == nil {
            // Route was cleared (navigation ended)
            if let userLocation = locationManager.userLocation {
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(center: userLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
                }
            }
        }
    }
    
    private func handleSpotSelection() {
        if let spot = selectedSpotForAnnotation {
            selectedSpotIdForSheet = spot.id
            
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: spot.coordinate,
                    span: viewingRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
    }
    
    private func handleGeofenceNavigation(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let spotId = userInfo["spotId"] as? String else {
            return
        }
        
        print("MapView: Navigating to spot from geofence notification: \(spotId)")
        navigateToSpot(spotId: spotId)
    }
    
    private func navigateToSpot(spotId: String) {
        guard let spot = spotsViewModel.spots.first(where: { $0.id == spotId }) else {
            print("MapView: Could not find spot with ID: \(spotId)")
            return
        }
        
        selectedSpotId = spot.id
        selectedSpotIdForSheet = spotId
        
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: spot.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
        
        print("MapView: Navigated to spot '\(spot.name)'")
    }
    
    private func findSpotIdFromAlert(_ alertDetails: LocationManager.GeofenceAlertInfo) -> String? {
        let alertBody = alertDetails.body
        return spotsViewModel.spots.first { spot in
            alertBody.contains(spot.name)
        }?.id
    }
    
    // MARK: - Camera Logic
    private func setInitialCamera(to coordinate: CLLocationCoordinate2D) {
        let userRegion = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        withAnimation { cameraPosition = .region(userRegion) }
        viewingRegion = userRegion
        initialCameraHasBeenSet = true
    }

    private func updateCameraForNavigation(userLocation: CLLocation) {
        withAnimation(.linear(duration: 0.5)) {
            cameraPosition = .userLocation(
                followsHeading: true,
                fallback: .region(MKCoordinateRegion(center: userLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
            )
        }
    }
    private func fallbackInitialCameraIfNeeded() async {
        try? await Task.sleep(for: .seconds(1.5))

        if !initialCameraHasBeenSet {
            if let userCoordinate = locationManager.userLocation?.coordinate {
                print("MapView: Fallback - User location became available, setting camera.")
                let userRegion = MKCoordinateRegion(center: userCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
                withAnimation { cameraPosition = .region(userRegion) }
                viewingRegion = userRegion
                initialCameraHasBeenSet = true
            } else if let firstSpot = spotsViewModel.spots.first {
                print("MapView: Fallback - No user location, centering on first spot.")
                let firstSpotRegion = MKCoordinateRegion(center: firstSpot.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
                withAnimation { cameraPosition = .region(firstSpotRegion) }
                viewingRegion = firstSpotRegion
            } else {
                print("MapView: Fallback - No user location and no spots, using default region.")
            }
        }
    }
    
    struct RouteSelectionView: View {
        @ObservedObject var navigationViewModel: NavigationViewModel
        
        var body: some View {
            if case .selectingRoute(let routeInfo) = navigationViewModel.navigationState {
                VStack(spacing: 0) {
                    // Route Details
                    HStack {
                        VStack(alignment: .leading) {
                            Text(routeInfo.spot.name)
                                .font(.headline)
                            Text("Travel time: \(routeInfo.expectedTravelTime)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        
                        Button(action: {
                            navigationViewModel.cancelRouteSelection()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.gray, Color.gray.opacity(0.2))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    
                    Divider()

                    // Transport Type Picker
                    Picker("Transport Type", selection: $navigationViewModel.selectedTransportType) {
                        ForEach(TransportType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    // Start Navigation Button
                    Button(action: {
                        navigationViewModel.beginActualNavigation()
                    }) {
                        Label("Start Navigation", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .padding([.horizontal, .bottom])
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 5)
                .padding()
                .transition(.move(edge: .bottom))
            }
        }
    }
}

// MARK: - Enhanced Supporting Views
struct SpotAnnotationView: View {
    let spot: Spot
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: annotationSize, height: annotationSize)
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: isSelected ? 3 : 2)
                )
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            
            Image(systemName: spot.category.systemImageName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white)
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
    
    private var backgroundColor: Color {
        isSelected ? .blue : colorFromString(spot.category.associatedColor)
    }
    
    private var annotationSize: CGFloat {
        isSelected ? 40 : 32
    }
    
    private var iconSize: CGFloat {
        isSelected ? 20 : 16
    }
    
    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "blue": return .blue
        case "red": return .red
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }
}

private struct RouteInfoCard: View {
    var message: String? = nil
    var time: TimeInterval? = nil
    var distance: CLLocationDistance? = nil
    var isError: Bool = false
    var onClear: (() -> Void)? = nil
    
    private var travelTime: String? {
        guard let time = time else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: time)
    }
    
    private var travelDistance: String? {
        guard let distance = distance else { return nil }
        let formatter = LengthFormatter()
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(fromMeters: distance)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                if let time = travelTime, let distance = travelDistance {
                    Text(time).font(.title3).fontWeight(.bold)
                    Text(distance).font(.caption).foregroundStyle(.secondary)
                } else if let message = message {
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(isError ? .red : .primary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let onClear = onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray, Color.gray.opacity(0.2))
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 5)
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(), value: message)
        .animation(.spring(), value: time)
    }
}

private struct MapZoomControls: View {
    @Binding var currentRegion: MKCoordinateRegion?
    @Binding var cameraPosition: MapCameraPosition
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        VStack(spacing: 12) {
            Button {
                recenterOnUser()
            } label: {
                Image(systemName: locationManager.userLocation != nil ? "location.fill" : "location.slash")
                    .mapControlButtonLook()
                    .foregroundStyle(locationManager.userLocation != nil ? Color.blue : Color.secondary)
            }

            Button { zoom(by: 0.5) } label: {
                Image(systemName: "plus.magnifyingglass")
                    .mapControlButtonLook()
            }
            Button { zoom(by: 2.0) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .mapControlButtonLook()
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 3)
    }

    private func zoom(by factor: Double) {
        guard var region = currentRegion else { return }
        
        region.span.latitudeDelta *= factor
        region.span.longitudeDelta *= factor
        
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(region)
        }
    }
    
    private func recenterOnUser() {
        if let userCoordinate = locationManager.userLocation?.coordinate {
            let newRegion = MKCoordinateRegion(
                center: userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            
            // We update BOTH the camera and the local region state simultaneously.
            withAnimation(.easeInOut(duration: 0.5)) {
                currentRegion = newRegion
                cameraPosition = .region(newRegion)
            }
        } else {
            // Fallback logic for permissions remains the same
            locationManager.requestLocationAuthorization()
            if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                locationManager.showPermissionAlert = true
            }
        }
    }
}

private struct MapControlButtonLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title2)
            .padding(10)
            .frame(width: 44, height: 44)
            .foregroundStyle(Color.secondary)
    }
}

private extension View {
    func mapControlButtonLook() -> some View {
        self.modifier(MapControlButtonLook())
    }
}

extension MKMapRect {
    func paddedBy(factor: Double) -> MKMapRect {
        let a = self.size.width * (factor - 1)
        let b = self.size.height * (factor - 1)
        return self.insetBy(dx: -a / 2, dy: -b / 2)
    }
}

private struct TurnByTurnInstructionView: View {
    @EnvironmentObject var navigationViewModel: NavigationViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // Next step instruction
            HStack {
                // You could add an icon for the maneuver here (e.g., turn left arrow)
                Text(navigationViewModel.nextStepInstruction)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true) // Allow text to wrap
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Overall route progress
            HStack {
                Text(navigationViewModel.remainingTravelTime)
                Text("•")
                Text(navigationViewModel.remainingDistance)
                Spacer()
                Text(navigationViewModel.arrivalTime)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

private struct EndNavigationButton: View {
    @EnvironmentObject var navigationViewModel: NavigationViewModel
    
    var body: some View {
        Button(action: {
            navigationViewModel.stopNavigation()
        }) {
            Text("End")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color.red)
                .clipShape(Capsule())
                .shadow(radius: 5)
        }
    }
}
