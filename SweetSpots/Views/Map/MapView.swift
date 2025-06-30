//
//  MapView.swift
//  SweetSpots
//
//  Enhanced production-ready version with improved performance, accessibility, and error handling
//

import SwiftUI
import MapKit
import CoreLocation
import os.log

struct MapView: View {
    
    // MARK: - Logger
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SweetSpots", category: "MapView")
    
    // MARK: - Environment Objects
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var appCoordinator: AppCoordinator


    // MARK: - State Variables
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    ))
    @State private var viewingRegion: MKCoordinateRegion? = nil
    
    @State private var selectedSpotIdForSheet: String? = nil
    @State private var selectedSpotForAnnotation: Spot? = nil
    @State private var previousSelectedSpot: Spot? = nil

    @State private var selectedCategoryFilters: Set<SpotCategory> = []
    @State private var initialCameraHasBeenSetByLocation = false
    @State private var isInitialized = false
    
    // MARK: - Geofencing Display Options
    @State private var showGeofenceRadii: Bool = false
    @AppStorage(UserDefaultsKeys.globalGeofencingEnabledKey)
    private var globalGeofencingEnabled: Bool = true
    
    // MARK: - Performance & Error Handling
    @State private var alertConfig: AlertConfig?
    @State private var isLocationLoading = false
    @State private var mapInteractionTask: Task<Void, Never>?
    @State private var cameraUpdateTask: Task<Void, Never>?
    @State private var lastGeofenceSync = Date.distantPast
    // Add these properties to the struct
    @State private var locationLoadingTask: Task<Void, Never>?
    @State private var geofenceValidationTask: Task<Void, Never>?
    
    // MARK: - Alert Configuration
    struct AlertConfig: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let primaryAction: AlertAction?
        let secondaryAction: AlertAction?

        struct AlertAction {
            let title: String
            let role: ButtonRole?
            let action: () -> Void
        }
    }
    
    // MARK: - Computed Properties
    private var spotsForMap: [Spot] {
        let filteredSpots: [Spot]
        if selectedCategoryFilters.isEmpty {
            filteredSpots = spotsViewModel.spots
        } else {
            filteredSpots = spotsViewModel.spots.filter { selectedCategoryFilters.contains($0.category) }
        }
        
        logger.debug("Displaying \(filteredSpots.count) spots on map")
        return filteredSpots
    }
    
    private var spotsWithGeofences: [Spot] {
        spotsForMap.filter { $0.wantsNearbyNotification && globalGeofencingEnabled }
    }
    
    private var isShowingSpotSheet: Binding<Bool> {
        $selectedSpotIdForSheet.isNotNil()
    }
    
    private var hasActiveFilters: Bool {
        !selectedCategoryFilters.isEmpty
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    mapContentWithOverlays
                    
                    // Loading overlay for location operations
                    if isLocationLoading {
                        loadingOverlay
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .onAppear {
                handleViewAppeared()
            }
            .onChange(of: locationManager.userLocation) { _, newLocation in
                handleUserLocationChanged(newLocation)
            }
            .onChange(of: selectedSpotForAnnotation) { _, newSpot in
                handleSpotSelectionChanged(to: newSpot)
            }
            .onChange(of: appCoordinator.pendingLaunchContent) { _, newContent in
                handleLaunchContent(newContent)
            }
            .onReceive(NotificationCenter.default.publisher(for: .applicationDidBecomeActive)) { _ in
                handleAppBecameActive()
            }
            .alert(item: $alertConfig) { config in
                createAlert(from: config)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Map view showing \(spotsForMap.count) spots")
        }
        .onDisappear {
            cleanupTasks()
        }
    }
    
    // MARK: - Map Content and Overlays
    private var mapContentWithOverlays: some View {
        Map(position: $cameraPosition, selection: $selectedSpotForAnnotation) {
            // User location annotation
            UserAnnotation()

            // Spot annotations with enhanced accessibility
            ForEach(spotsForMap) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    SpotAnnotationView(
                        spot: spot,
                        isSelected: spot.id == selectedSpotForAnnotation?.id,
                        hasGeofence: spot.wantsNearbyNotification && globalGeofencingEnabled
                    )
                    .onTapGesture {
                        handleSpotAnnotationTapped(spot)
                    }
                    .accessibilityLabel(spotAccessibilityLabel(for: spot))
                    .accessibilityHint("Double tap to view details")
                    .accessibilityAddTraits(.isButton)
                }
                .tag(spot)
            }
            
            // Geofence radius overlays
            if showGeofenceRadii {
                ForEach(spotsWithGeofences) { spot in
                    MapCircle(center: spot.coordinate, radius: spot.notificationRadiusMeters)
                        .foregroundStyle(Color.blue.opacity(0.15))
                        .stroke(Color.blue.opacity(0.6), lineWidth: 2)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            if #available(iOS 17.0, *) {
                MapPitchToggle()
            }
            MapCompass()
                .mapControlVisibility(.visible)
        }
        .overlay(alignment: .bottomTrailing) {
            MapZoomControls(
                currentRegion: $viewingRegion,
                cameraPosition: $cameraPosition
            )
            .environmentObject(locationManager)
            .padding(.trailing, 15)
            .padding(.bottom, 80)
        }
        .overlay(alignment: .topLeading) {
            mapStatusOverlays
        }
        .overlay(alignment: .bottom) {
            if hasActiveFilters {
                activeFiltersIndicator
                    .padding(.bottom, 100)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            // This is called automatically when the user stops interacting with the map.
            self.viewingRegion = context.region
        }
        .sheet(isPresented: isShowingSpotSheet) {
            spotDetailSheet
        }
        .alert(item: $locationManager.geofenceTriggeredAlert) { alertDetails in
            geofenceAlert(alertDetails)
        }
    }
    
    // MARK: - Overlay Views
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.2)
                
                Text("Updating location...")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(UIUtils.cardShadow)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading location")
    }
    
    @ViewBuilder
    private var mapStatusOverlays: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Geofence status
            if globalGeofencingEnabled && !spotsWithGeofences.isEmpty {
                GeofenceStatusView(
                    activeGeofencesCount: spotsWithGeofences.count,
                    authorizationStatus: locationManager.authorizationStatus
                )
            }
            
            // Location status
            if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                LocationPermissionWarningView {
                    promptForLocationPermission()
                }
            }
        }
        .padding(.leading, 16)
        .padding(.top, 16)
    }
    
    private var activeFiltersIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundColor(.blue)
            
            Text("\(selectedCategoryFilters.count) filter\(selectedCategoryFilters.count == 1 ? "" : "s") active")
                .font(.caption)
                .fontWeight(.medium)
            
            Button("Clear") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedCategoryFilters.removeAll()
                }
                UIUtils.hapticFeedback(.light)
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(UIUtils.lightShadow)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
    
    @ViewBuilder
    private var spotDetailSheet: some View {
        if let spotId = selectedSpotIdForSheet {
            SpotDetailView(spotId: spotId)
                .environmentObject(authViewModel)
                .environmentObject(spotsViewModel)
                .environmentObject(locationManager)
                .environmentObject(collectionViewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showGeofenceRadii.toggle()
                }
                UIUtils.hapticFeedback(.light)
            } label: {
                Image(systemName: showGeofenceRadii ? "circle.dashed" : "circle.dashed.inset.filled")
                    .foregroundStyle(showGeofenceRadii ? Color.blue : Color.secondary)
            }
            .accessibilityLabel(showGeofenceRadii ? "Hide geofence zones" : "Show geofence zones")
            .disabled(spotsWithGeofences.isEmpty)
            
            mapCategoryFilterMenu()
        }
        
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button {
                recenterOnUserLocation()
            } label: {
                Image(systemName: locationManager.userLocation != nil ? "location.fill" : "location.slash")
                    .foregroundStyle(locationManager.userLocation != nil ? Color.blue : Color.secondary)
            }
            .accessibilityLabel("Center on current location")
            .disabled(locationManager.userLocation == nil)
        }
    }
    
    // MARK: - Filter Menu
    private func mapCategoryFilterMenu() -> some View {
        Menu {
            Section("Filter by Category") {
                Button(action: {
                    selectedCategoryFilters.removeAll()
                    UIUtils.hapticFeedback(.light)
                }) {
                    Label("All Categories", systemImage: selectedCategoryFilters.isEmpty ? "checkmark.circle.fill" : "circle")
                }
                
                Divider()
                
                ForEach(SpotCategory.allCases) { category in
                    let spotCount = spotsViewModel.spots.filter { $0.category == category }.count
                    let isSelected = selectedCategoryFilters.contains(category)
                    
                    Button(action: {
                        toggleCategoryFilter(category)
                    }) {
                        HStack {
                            Label(category.displayName, systemImage: category.systemImageName)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                            Text("(\(spotCount))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if globalGeofencingEnabled && !spotsWithGeofences.isEmpty {
                Section("Proximity Alerts") {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showGeofenceRadii.toggle()
                        }
                        UIUtils.hapticFeedback(.light)
                    }) {
                        Label(
                            showGeofenceRadii ? "Hide Alert Zones" : "Show Alert Zones",
                            systemImage: showGeofenceRadii ? "eye.slash" : "eye"
                        )
                    }
                    
                    Button(action: {
                        Task {
                            await validateGeofenceStatus()
                        }
                    }) {
                        Label("Refresh Alerts", systemImage: "arrow.clockwise")
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: selectedCategoryFilters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Color.blue)
        }
        .accessibilityLabel("Map filters and options")
    }
    
    // MARK: - Lifecycle Methods
    private func handleViewAppeared() {
        guard !isInitialized else { return }
        
        logger.info("MapView appeared")
        
        Task {
            await performInitialSetup()
            await MainActor.run {
                isInitialized = true
            }
        }
    }
    
    private func performInitialSetup() async {
        await MainActor.run {
            setupInitialLocationHandling()
        }
        
        // Validate geofence status after setup
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            await validateGeofenceStatus()
        } catch {
            logger.debug("Initial setup sleep interrupted")
        }
    }
    
    private func setupInitialLocationHandling() {
        // Request location permission if not determined
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestLocationAuthorization(aimForAlways: false)
        }
        
        // Start location updates if authorized
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
           locationManager.authorizationStatus == .authorizedAlways {
            if !locationManager.isRequestingLocationUpdates {
                locationManager.startUpdatingUserLocation()
            }
        }
        
        // Set initial camera position
        setInitialCameraPosition()
    }
    
    private func setInitialCameraPosition() {
        if let userCoordinate = locationManager.userLocation?.coordinate {
            logger.info("Setting initial camera to user location")
            let userRegion = MKCoordinateRegion(
                center: userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            cameraPosition = .region(userRegion)
            viewingRegion = userRegion
            initialCameraHasBeenSetByLocation = true
        } else if let firstSpot = spotsViewModel.spots.first {
            logger.info("Setting initial camera to first spot")
            let spotRegion = MKCoordinateRegion(
                center: firstSpot.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            cameraPosition = .region(spotRegion)
            viewingRegion = spotRegion
        }
    }
    
    // MARK: - Event Handlers
    private func handleUserLocationChanged(_ newLocation: CLLocation?) {
        guard let userCoordinate = newLocation?.coordinate,
              !initialCameraHasBeenSetByLocation else { return }
        
        logger.info("User location updated, setting camera")
        let userRegion = MKCoordinateRegion(
            center: userCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .region(userRegion)
        }
        viewingRegion = userRegion
        initialCameraHasBeenSetByLocation = true
    }
    
    private func handleSpotSelectionChanged(to newSpot: Spot?) {
        guard let spot = newSpot else { return }
        
        // Animate the camera to the selected spot
        animateToSpot(spot)
        
        // Open the detail sheet
        selectedSpotIdForSheet = spot.id
    }
    
    private func handleCameraChanged(_ context: MapCameraUpdateContext) {
        // Debounce region updates
        mapInteractionTask?.cancel()
        mapInteractionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 second delay
                guard !Task.isCancelled else { return }
                viewingRegion = context.region
            } catch {
                logger.debug("Map interaction task cancelled")
            }
        }
    }
    
    private func handleSpotAnnotationTapped(_ spot: Spot) {
        logger.info("Spot annotation tapped: \(spot.name)")
        selectedSpotForAnnotation = spot
        UIUtils.hapticFeedback(.light)
    }
    
    private func handleLaunchContent(_ content: LaunchContent?) {
        guard let content else { return }
        
        switch content {
        case .spot(let id):
            navigateToSpot(spotId: id)
        case .sharedURL:
            // MapView probably doesn't need to handle this, but you could if desired.
            // For example, by showing a sheet.
            break
        }
        
        // Clear the content so it doesn't trigger again.
        appCoordinator.clearPendingLaunchContent()
    }
    
    private func handleAppBecameActive() {
        logger.debug("App became active, refreshing map state")
        
        Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                await validateGeofenceStatus()
            } catch {
                logger.debug("App active validation sleep interrupted")
            }
        }
    }
    
    // MARK: - Navigation Methods
    private func animateToSpot(_ spot: Spot) {
        let spotRegion = MKCoordinateRegion(
            center: spot.coordinate,
            span: viewingRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(spotRegion)
        }
    }
    
    private func navigateToSpot(spotId: String) async {
        guard let spot = spotsViewModel.spots.first(where: { $0.id == spotId }) else {
            logger.error("Could not find spot with ID: \(spotId)")
            await MainActor.run {
                showError("Spot not found", message: "The requested spot could not be located.")
            }
            return
        }
        
        await MainActor.run {
            // Set the selected spot and show sheet
            selectedSpotForAnnotation = spot
            selectedSpotIdForSheet = spotId
            
            // Animate to the spot location with tighter zoom
            let spotRegion = MKCoordinateRegion(
                center: spot.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
            
            withAnimation(.easeInOut(duration: 0.8)) {
                cameraPosition = .region(spotRegion)
            }
            
            logger.info("Navigated to spot '\(spot.name)'")
        }
    }
    
    private func recenterOnUserLocation() {
        guard let userCoordinate = locationManager.userLocation?.coordinate else {
            requestLocationWithFeedback()
            return
        }
        
        logger.info("Recentering on user location")
        
        let userRegion = MKCoordinateRegion(
            center: userCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(userRegion)
        }
        
        UIUtils.hapticFeedback(.light)
    }
    
    private func requestLocationWithFeedback() {
        // Cancel any existing task
        locationLoadingTask?.cancel()
        
        isLocationLoading = true
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestLocationAuthorization {
                DispatchQueue.main.async {
                    self.isLocationLoading = false
                }
            }
            
        case .restricted, .denied:
            isLocationLoading = false
            promptForLocationPermission()
            
        case .authorizedWhenInUse, .authorizedAlways:
            if !locationManager.isRequestingLocationUpdates {
                locationManager.startUpdatingUserLocation()
            }
            
            // Auto-dismiss loading after 5 seconds
            locationLoadingTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { return }
                    
                    await MainActor.run {
                        isLocationLoading = false
                    }
                } catch {
                    // Task was cancelled
                }
            }
            
        @unknown default:
            isLocationLoading = false
            logger.error("Unknown location authorization status")
        }
    }
    
    // MARK: - Filter Methods
    private func toggleCategoryFilter(_ category: SpotCategory) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if selectedCategoryFilters.contains(category) {
                selectedCategoryFilters.remove(category)
            } else {
                selectedCategoryFilters.insert(category)
            }
        }
        UIUtils.hapticFeedback(.light)
    }
    
    // MARK: - Geofence Validation
    private func validateGeofenceStatus() async {
        guard globalGeofencingEnabled else { return }
        
        // Cancel any existing validation
        geofenceValidationTask?.cancel()
        
        // Rate limit geofence validation
        let now = Date()
        guard now.timeIntervalSince(lastGeofenceSync) > 5.0 else {
            logger.debug("Geofence validation rate limited")
            return
        }
        
        geofenceValidationTask = Task {
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                lastGeofenceSync = now
                
                let spotsWithNotifications = spotsViewModel.spots.filter { $0.wantsNearbyNotification }
                let activeGeofenceIds = locationManager.activeGeofenceIDs
                let expectedIds = Set(spotsWithNotifications.compactMap { $0.id })
                
                if activeGeofenceIds != expectedIds {
                    logger.info("Geofence sync needed: Active(\(activeGeofenceIds.count)) vs Expected(\(expectedIds.count))")
                    
                    locationManager.synchronizeGeofences(
                        forSpots: spotsViewModel.spots,
                        globallyEnabled: globalGeofencingEnabled
                    )
                }
            }
        }
    }
    
    // MARK: - Alert Methods
    private func geofenceAlert(_ alertDetails: LocationManager.GeofenceAlertInfo) -> Alert {
        Alert(
            title: Text(alertDetails.title),
            message: Text(alertDetails.body),
            primaryButton: .default(Text("View Spot")) {
                if let spotId = findSpotIdFromAlert(alertDetails) {
                    Task {
                        await navigateToSpot(spotId: spotId)
                    }
                }
            },
            secondaryButton: .cancel()
        )
    }
    
    private func findSpotIdFromAlert(_ alertDetails: LocationManager.GeofenceAlertInfo) -> String? {
        return spotsViewModel.spots.first { spot in
            alertDetails.body.contains(spot.name) || alertDetails.spotId == spot.id
        }?.id
    }
    
    private func promptForLocationPermission() {
        alertConfig = AlertConfig(
            title: "Location Access Required",
            message: "To show your location on the map and enable proximity alerts, please grant location access in Settings.",
            primaryButton: "Settings",
            secondaryButton: "Cancel",
            actionType: .openSettings
        )
    }
    
    private func showError(_ title: String, message: String) {
        alertConfig = AlertConfig(
            title: title,
            message: message
        )
    }
    
    private func createAlert(from config: AlertConfig) -> Alert {
        let primaryButton: Alert.Button
        if let primary = config.primaryAction {
            primaryButton = .default(Text(primary.title), action: primary.action)
        } else {
            primaryButton = .default(Text("OK"))
        }

        let secondaryButton: Alert.Button
        if let secondary = config.secondaryAction {
            secondaryButton = .cancel(Text(secondary.title), action: secondary.action)
        } else {
            secondaryButton = .cancel()
        }

        return Alert(title: Text(config.title), message: Text(config.message), primaryButton: primaryButton, secondaryButton: secondaryButton)
    }

    private func handleAlertAction(_ actionType: AlertConfig.ActionType?) {
        guard let actionType = actionType else { return }
        
        switch actionType {
        case .openSettings:
            UIUtils.openAppSettings()
        case .navigateToSpot(let spotId):
            Task {
                await navigateToSpot(spotId: spotId)
            }
        case .custom:
            // Handle any custom actions
            break
        }
    }
    
    // MARK: - Accessibility Helpers
    private func spotAccessibilityLabel(for spot: Spot) -> String {
        var label = "\(spot.name), \(spot.category.displayName)"
        
        if spot.wantsNearbyNotification && globalGeofencingEnabled {
            label += ", has proximity alert"
        }
        
        if let userLocation = locationManager.userLocation {
            let distance = spot.distance(from: userLocation)
            let distanceString = DistanceFormatter.shared.formatDistance(distance)
            label += ", \(distanceString) away"
        }
        
        return label
    }
    
    // MARK: - Cleanup
    private func cleanupTasks() {
        mapInteractionTask?.cancel()
        cameraUpdateTask?.cancel()
        locationLoadingTask?.cancel()
        geofenceValidationTask?.cancel()
        logger.info("MapView tasks cleaned up")
    }
}

// MARK: - Enhanced Supporting Views

struct SpotAnnotationView: View {
    let spot: Spot
    let isSelected: Bool
    let hasGeofence: Bool
    
    var body: some View {
        ZStack {
            // Main annotation circle
            Circle()
                .fill(backgroundColor)
                .frame(width: annotationSize, height: annotationSize)
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: strokeWidth)
                )
                .shadow(color: .black.opacity(0.3), radius: shadowRadius, x: 0, y: 2)
            
            // Category icon
            Image(systemName: spot.category.systemImageName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white)
            
            // Geofence indicator
            if hasGeofence && !isSelected {
                Circle()
                    .stroke(Color.orange, lineWidth: 2)
                    .frame(width: annotationSize + 8, height: annotationSize + 8)
                    .opacity(0.8)
            }
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        }
        
        switch spot.category {
        case .food: return .orange
        case .nature: return .green
        case .shopping: return .purple
        case .sights: return .blue
        case .activities: return .red
        case .other: return .gray
        }
    }
    
    private var annotationSize: CGFloat {
        isSelected ? 44 : 36
    }
    
    private var iconSize: CGFloat {
        isSelected ? 22 : 18
    }
    
    private var strokeWidth: CGFloat {
        isSelected ? 3 : 2
    }
    
    private var shadowRadius: CGFloat {
        isSelected ? 4 : 3
    }
    
    private func colorFromString(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "blue": return .blue
        case "red": return .red
        case "gray": return .gray
        default: return .blue
        }
    }
}

// MARK: - Geofence Status View
struct GeofenceStatusView: View {
    let activeGeofencesCount: Int
    let authorizationStatus: CLAuthorizationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                
                Text("\(activeGeofencesCount) proximity alert\(activeGeofencesCount == 1 ? "" : "s")")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            if authorizationStatus != .authorizedAlways {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    
                    Text("Need Always permission")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(UIUtils.lightShadow)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Proximity alerts status: \(activeGeofencesCount) active. \(authorizationStatus != .authorizedAlways ? "Always permission needed." : "")")
    }
}

// MARK: - Location Permission Warning View
struct LocationPermissionWarningView: View {
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash")
                .foregroundColor(.red)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Location Access Denied")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Tap to enable in Settings")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            action()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Location access denied. Tap to enable in Settings.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Enhanced Zoom Controls
struct MapZoomControls: View {
    @Binding var currentRegion: MKCoordinateRegion?
    @Binding var cameraPosition: MapCameraPosition
    @EnvironmentObject private var locationManager: LocationManager
    
    // MARK: - Constants
    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 20
    private let zoomFactor = 0.5
    private let maxZoomOut = 2.0
    private let minDelta = 0.0001
    private let maxDelta = 180.0
    
    var body: some View {
        VStack(spacing: 8) {
            // Location center button
            Button {
                recenterOnUser()
            } label: {
                Image(systemName: locationIcon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(locationColor)
                    .frame(width: buttonSize, height: buttonSize)
            }
            .accessibilityLabel("Center on current location")
            .accessibilityHint(locationAccessibilityHint)
            .disabled(!canRecenter)

            Divider()
                .frame(height: 1)
                .background(.secondary.opacity(0.3))

            // Zoom in button
            Button {
                zoom(by: zoomFactor)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.secondary)
                    .frame(width: buttonSize, height: buttonSize)
            }
            .accessibilityLabel("Zoom in")
            .disabled(!canZoomIn)
            
            // Zoom out button
            Button {
                zoom(by: maxZoomOut)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.secondary)
                    .frame(width: buttonSize, height: buttonSize)
            }
            .accessibilityLabel("Zoom out")
            .disabled(!canZoomOut)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(UIUtils.cardShadow)
    }
    
    // MARK: - Computed Properties
    private var locationIcon: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationManager.userLocation != nil ? "location.fill" : "location"
        case .denied, .restricted:
            return "location.slash"
        case .notDetermined:
            return "location"
        @unknown default:
            return "location"
        }
    }
    
    private var locationColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationManager.userLocation != nil ? .blue : .secondary
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .secondary
        }
    }
    
    private var locationAccessibilityHint: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationManager.userLocation != nil ? "Centers map on your current location" : "Requests your current location"
        case .denied, .restricted:
            return "Location access denied. Opens Settings to enable."
        case .notDetermined:
            return "Requests location permission"
        @unknown default:
            return "Location status unknown"
        }
    }
    
    private var canRecenter: Bool {
        locationManager.authorizationStatus != .restricted
    }
    
    private var canZoomIn: Bool {
        guard let region = currentRegion else { return true }
        return region.span.latitudeDelta > minDelta && region.span.longitudeDelta > minDelta
    }
    
    private var canZoomOut: Bool {
        guard let region = currentRegion else { return true }
        return region.span.latitudeDelta < maxDelta && region.span.longitudeDelta < maxDelta
    }

    // MARK: - Methods
    private func zoom(by factor: Double) {
        guard var region = currentRegion else { return }
        
        let newLatDelta = max(minDelta, min(region.span.latitudeDelta * factor, maxDelta))
        let newLonDelta = max(minDelta, min(region.span.longitudeDelta * factor, maxDelta))
        
        // Only update if there's a meaningful change
        guard abs(newLatDelta - region.span.latitudeDelta) > minDelta * 10 ||
              abs(newLonDelta - region.span.longitudeDelta) > minDelta * 10 else {
            return
        }
        
        region.span.latitudeDelta = newLatDelta
        region.span.longitudeDelta = newLonDelta
        
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(region)
        }
        
        UIUtils.hapticFeedback(.light)
    }
    
    private func recenterOnUser() {
        UIUtils.hapticFeedback(.light)
        
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let userCoordinate = locationManager.userLocation?.coordinate {
                let userRegion = MKCoordinateRegion(
                    center: userCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
                
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .region(userRegion)
                }
            } else {
                // Request location update
                if !locationManager.isRequestingLocationUpdates {
                    locationManager.startUpdatingUserLocation()
                }
            }
            
        case .denied, .restricted:
            // Open Settings
            UIUtils.openAppSettings()
            
        case .notDetermined:
            // Request permission
            locationManager.requestLocationAuthorization(aimForAlways: false)
            
        @unknown default:
            break
        }
    }
}



// MARK: - Preview
#Preview("MapView - Default") {
    let mockSpotsVM = SpotViewModel()
    let mockLocationManager = LocationManager()
    let mockAuthVM = AuthViewModel()
    let mockCollectionVM = CollectionViewModel()
    
    // Add mock data
    mockSpotsVM.spots = [
        Spot(
            userId: "user1",
            name: "Cafe Central",
            address: "123 Main St, San Francisco, CA",
            latitude: 37.7749,
            longitude: -122.4194,
            category: .food,
            wantsNearbyNotification: true,
            notificationRadiusMeters: 200
        ),
        Spot(
            userId: "user1",
            name: "Golden Gate Park",
            address: "Golden Gate Park, San Francisco, CA",
            latitude: 37.7694,
            longitude: -122.4862,
            category: .nature,
            wantsNearbyNotification: false
        ),
        Spot(
            userId: "user1",
            name: "Union Square",
            address: "Union Square, San Francisco, CA",
            latitude: 37.7880,
            longitude: -122.4074,
            category: .shopping,
            wantsNearbyNotification: true,
            notificationRadiusMeters: 150
        )
    ]

    return NavigationStack {
        MapView()
            .environmentObject(mockSpotsVM)
            .environmentObject(mockLocationManager)
            .environmentObject(mockAuthVM)
            .environmentObject(mockCollectionVM)
    }
}

#Preview("MapView - Empty State") {
    let mockSpotsVM = SpotViewModel()
    let mockLocationManager = LocationManager()
    let mockAuthVM = AuthViewModel()
    let mockCollectionVM = CollectionViewModel()

    return NavigationStack {
        MapView()
            .environmentObject(mockSpotsVM)
            .environmentObject(mockLocationManager)
            .environmentObject(mockAuthVM)
            .environmentObject(mockCollectionVM)
    }
}
