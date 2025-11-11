//
//  MainTabView.swift
//  SweetSpots
//
//

import SwiftUI
import CoreLocation
import FirebaseAuth
import MapKit
import os.log

// MARK: - Main Tab View
struct MainTabView: View {
    // MARK: - State & Environment
    @StateObject private var spotsViewModel: SpotViewModel
    @StateObject private var locationManager: LocationManager
    @StateObject private var collectionViewModel: CollectionViewModel
    @StateObject private var navigationViewModel: NavigationViewModel
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "MainTabView")
    
    @ObservedObject private var launchManager = LaunchManager.shared
    
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    
    @AppStorage("globalGeofencingEnabled") private var globalGeofencingSystemEnabled: Bool = true
    
    @State private var selectedTab: Int = 0
    @State private var initialDataLoadAttemptedForCurrentSession: Bool = false
    
    enum LaunchAction: Equatable {
        case navigateToSpotID(String) // We get an ID from the notification
    }
    
    enum ActiveSheet: Identifiable {
        case sharedURLAddSpot(url: URL)
        case sharedPayloadAddSpot(payload: SharedSpotPayload)
        case spotDetail(spot: Spot)
        case sharedCollection(payload: SharedCollectionPayload)
        
        var id: String {
            switch self {
            case .sharedURLAddSpot(let url): return "sharedURLAddSpot-\(url.absoluteString)"
            case .sharedPayloadAddSpot(let payload): return "sharedPayloadAddSpot-\(payload.name)"
            case .sharedCollection(let payload): return "sharedCollection-\(payload.collectionName)"
            case .spotDetail(let spot): return "spotDetail-\(spot.hashValue)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    
    // MARK: - Initialization
    init(authViewModel: AuthViewModel) {
        let locationManager = LocationManager()
        self._spotsViewModel = StateObject(wrappedValue: SpotViewModel(authViewModel: authViewModel))
        self._locationManager = StateObject(wrappedValue: locationManager)
        self._collectionViewModel = StateObject(wrappedValue: CollectionViewModel())
        self._navigationViewModel = StateObject(wrappedValue: NavigationViewModel(locationManager: locationManager))
        
        configureTabBarAppearance()
    }
    
    var body: some View {
        presentationModifiers(for: dataModifiers(for: tabViewContent))
    }
    
    private var tabViewContent: some View {
        TabView(selection: $selectedTab) {
            spotListTab()
            collectionsTab()
            mapTab()
            }
            .accentColor(Color.themePrimary)
            .environmentObject(locationManager)
            .environmentObject(spotsViewModel)
            .environmentObject(collectionViewModel)
            .environmentObject(navigationViewModel)
        }
    
    @ViewBuilder
    private func dataModifiers(for content: some View) -> some View {
        content
        .onAppear(perform: handleOnAppear)
        .onChange(of: authViewModel.userSession) { oldValue, newValue in
            handleUserSessionChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: navigationViewModel.navigationState) { _, newState in
            if case .selectingRoute = newState {
                selectedTab = 2
            }
        }
        .onChange(of: spotsViewModel.spots) { oldValue, newValue in
            handleSpotsChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: globalGeofencingSystemEnabled) { oldValue, newValue in
            handleGlobalGeofencingToggle(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: locationManager.authorizationStatus) { oldValue, newValue in
            handleLocationAuthorizationChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: launchManager.launchAction) { _, _ in }
        // This is the new, correct listener for deep links
        .onChange(of: navigationCoordinator.incomingSharedURL) { _, newURL in
            if let url = newURL {
                activeSheet = .sharedURLAddSpot(url: url)
                navigationCoordinator.incomingSharedURL = nil
            }
        }
        .onChange(of: navigationCoordinator.incomingSharedPayload) { _, newPayload in
            if let payload = newPayload {
                activeSheet = .sharedPayloadAddSpot(payload: payload)
                navigationCoordinator.incomingSharedPayload = nil
            }
        }
        .onChange(of: navigationCoordinator.incomingSharedCollectionPayload) { _, newPayload in
            if let payload = newPayload {
                activeSheet = .sharedCollection(payload: payload)
                navigationCoordinator.incomingSharedCollectionPayload = nil
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }

    @ViewBuilder
    private func presentationModifiers(for content: some View) -> some View {
        content
            .alert("SweetSpot Nearby!", isPresented: .constant(launchManager.launchAction != nil), presenting: launchManager.launchAction) { action in
                if case .navigateToSpotID(let spotId) = action,
                   let spot = spotsViewModel.spots.first(where: { $0.id == spotId }) {
                    
                    Button("Navigate Now") {
                        guard let userLocation = locationManager.userLocation else { return }
                        Task {
                            await navigationViewModel.setNavigationTarget(spot: spot, from: userLocation)
                        }
                        self.launchManager.launchAction = nil
                    }
                    Button("View Details") {
                        self.activeSheet = .spotDetail(spot: spot)
                        self.launchManager.launchAction = nil
                    }
                    Button("Dismiss", role: .cancel) {
                        self.launchManager.launchAction = nil
                    }
                }
            } message: { action in
                if case .navigateToSpotID(let spotId) = action,
                   let spot = spotsViewModel.spots.first(where: { $0.id == spotId }) {
                    Text("You're near '\(spot.name)'. What would you like to do?")
                }
            }
            .sheet(item: $activeSheet) { sheetType in
                sheetView(for: sheetType)
                    .environmentObject(spotsViewModel)
                    .environmentObject(locationManager)
                    .environmentObject(authViewModel)
                    .environmentObject(collectionViewModel)
                    .environmentObject(navigationViewModel)
            }
    }
    
    // MARK: - UI Components & Tab Definitions
    @ViewBuilder
    private func sheetView(for sheetType: ActiveSheet) -> some View {
        switch sheetType {
        case .sharedURLAddSpot(let url):
            AddSpotView(isPresented: sheetBinding(), spotToEdit: nil, prefilledPayload: nil, prefilledURL: url)
        case .sharedPayloadAddSpot(let payload):
            let contextualURL = URL(string: payload.sourceURL ?? payload.websiteURL ?? "")
                AddSpotView(isPresented: sheetBinding(), spotToEdit: nil, prefilledPayload: payload, prefilledURL: contextualURL)
        case .sharedCollection(let payload):
            ImportCollectionView(isPresented: sheetBinding(), payload: payload)
        case .spotDetail(let spot):
            SpotDetailView(spotId: spot.id ?? "", presentedFrom: .map)
        }
    }
    
    private func sheetBinding() -> Binding<Bool> {
        Binding(get: { activeSheet != nil }, set: { isShowing in if !isShowing { activeSheet = nil } })
    }
    
    // MARK: - Tab Views
    
    private func spotListTab() -> some View {
        SpotListView()
            .tabItem {
                Label("List", systemImage: selectedTab == 0 ? "list.bullet.circle.fill" : "list.bullet.circle")
            }
            .tag(0)
    }
    
    private func collectionsTab() -> some View {
            // NavigationStack is crucial for allowing navigation from the gallery to the detail view.
            NavigationStack {
                CollectionsGalleryView()
            }
            .tabItem {
                Label("Collections", systemImage: selectedTab == 1 ? "square.stack.3d.up.fill" : "square.stack.3d.up")
            }
            .tag(1)
        }
    
    
    
    private func mapTab() -> some View {
        MapView()
            .tabItem {
                Label("Map", systemImage: selectedTab == 2 ? "map.fill" : "map")
            }
            .tag(2)
    }
    
    // MARK: - Helper Methods
    private func executeLaunchAction(_ action: LaunchAction) {
        if case .navigateToSpotID = action {
            // This function's only job now is to set the tab.
            // The alert is responsible for showing the UI.
            selectedTab = 2
        }
    }
    
    private func configureTabBarAppearance() {
        let standardAppearance = UITabBarAppearance()
        standardAppearance.configureWithOpaqueBackground()
        standardAppearance.backgroundColor = UIColor(Color.themeFieldBackground)
        standardAppearance.shadowImage = UIImage()
        standardAppearance.shadowColor = UIColor(Color.themeTextSecondary.opacity(0.2))
        
        let normalAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor(Color.themeTextSecondary)]
        let selectedAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor(Color.themePrimary)]
        
        [standardAppearance.stackedLayoutAppearance,
         standardAppearance.inlineLayoutAppearance,
         standardAppearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.normal.iconColor = UIColor(Color.themeTextSecondary)
            itemAppearance.normal.titleTextAttributes = normalAttributes
            itemAppearance.selected.iconColor = UIColor(Color.themePrimary)
            itemAppearance.selected.titleTextAttributes = selectedAttributes
        }
        
        UITabBar.appearance().standardAppearance = standardAppearance
        UITabBar.appearance().scrollEdgeAppearance = standardAppearance
    }
    
    private func handleOnAppear() {
        logger.info("MainTabView.onAppear triggered.")
        
        locationManager.onReprioritizationNeeded = {
            logger.info("Reprioritization needed. Re-syncing geofences with current spots.")
                // Because this closure is in MainTabView, it has access to everything it needs.
                locationManager.synchronizeGeofences(
                    forSpots: spotsViewModel.spots,
                    globallyEnabled: self.globalGeofencingSystemEnabled
                )
            }
        
        
        if let userId = authViewModel.userSession?.uid, !initialDataLoadAttemptedForCurrentSession {
            logger.info("MainTabView.onAppear with existing user session (UID: \(userId)). Performing initial setup.")
            performUserSessionSetup(userId: userId)
            initialDataLoadAttemptedForCurrentSession = true
        }
    }

    private func handleUserSessionChange(oldValue: User?, newValue: User?) {
        logger.info("authViewModel.userSession changed. Old UID: \(oldValue?.uid ?? "nil"), New UID: \(newValue?.uid ?? "nil")")
        if let userId = newValue?.uid {
            // Fresh login detected
            if oldValue == nil && newValue != nil && self.launchManager.launchAction == nil {
                logger.info("Fresh login detected with NO launch action, resetting to default tab.")
                selectedTab = 0
            }
            performUserSessionSetup(userId: userId)
            initialDataLoadAttemptedForCurrentSession = true

        }  else if oldValue != nil && newValue == nil {
            logger.info("User session became nil (signed out). Clearing data and listeners.")
            spotsViewModel.stopListeningAndClearData()
            collectionViewModel.detachCollectionsListener()
            locationManager.stopAllGeofences()
            initialDataLoadAttemptedForCurrentSession = false
        }
    }

    private func performUserSessionSetup(userId: String) {
        logger.info("Performing setup for user UID: \(userId).")
        spotsViewModel.listenForSpots(userId: userId)
        spotsViewModel.purgeExpiredSpots(for: userId)
        collectionViewModel.listenForCollections(userId: userId)
        
        setupLocationServices()
        Task { await attemptInitialGeofenceSync() }
    }

    private func setupLocationServices() {
        logger.info("Setting up location services")
        // We no longer request permission here. We only start updates if we already have it.
        if (locationManager.authorizationStatus == .authorizedWhenInUse ||
            locationManager.authorizationStatus == .authorizedAlways) &&
            !locationManager.isRequestingLocationUpdates
        {
            locationManager.startUpdatingUserLocation()
        }
    }

    private func attemptInitialGeofenceSync() async {
        guard globalGeofencingSystemEnabled else {
            logger.info("Skipping initial geofence sync - globally disabled");
            return }
        let locationOK = locationManager.authorizationStatus == .authorizedAlways
        let notificationsOK = locationManager.notificationStatus == .authorized
        if locationOK && notificationsOK {
            try? await Task.sleep(for: .milliseconds(500))
            logger.info("Attempting initial geofence sync. Spots count: \(spotsViewModel.spots.count)")
            locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: true)
        } else {
            logger.warning("Permissions not sufficient for initial geofence sync (Location Always: \(locationOK), Notifications: \(notificationsOK))")
        }
    }

    private func handleAppWillEnterForeground(_ payload: Notification) {
        guard globalGeofencingSystemEnabled, authViewModel.userSession != nil else { return }
        logger.info("App entering foreground, checking permissions and syncing geofences")
        setupLocationServices()
        Task {
            let notificationsOK = await locationManager.requestNotificationPermissionAsync()
            if notificationsOK && (locationManager.authorizationStatus == .authorizedAlways) {
                locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: true)
                logger.info("Foreground geofence sync completed")
            }
        }
    }

    private func handleSpotsChange(oldValue: [Spot], newValue: [Spot]) {
        guard authViewModel.userSession != nil else { return }
        logger.info("spotsViewModel.spots changed, count: \(newValue.count)")
        locationManager.synchronizeGeofences(forSpots: newValue, globallyEnabled: self.globalGeofencingSystemEnabled)
    }

    private func handleGlobalGeofencingToggle(oldValue: Bool, newValue: Bool) {
        guard authViewModel.userSession != nil else { return }
        logger.info("Global geofencing toggled to: \(newValue)")
        locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: newValue)
    }

    private func handleLocationAuthorizationChange(oldValue: CLAuthorizationStatus, newValue: CLAuthorizationStatus) {
        logger.info("Location authorization changed from \(LocationManager.string(for: oldValue)) to \(LocationManager.string(for: newValue))")
    
        
        // This existing logic is still correct for starting location updates.
        if (newValue == .authorizedWhenInUse || newValue == .authorizedAlways) && !locationManager.isRequestingLocationUpdates {
            locationManager.startUpdatingUserLocation()
        }
        
        // This existing logic is still correct for syncing geofences.
        guard authViewModel.userSession != nil, globalGeofencingSystemEnabled else { return }
        locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: newValue == .authorizedAlways && globalGeofencingSystemEnabled)
    }
}
