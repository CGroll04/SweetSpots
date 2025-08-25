//
//  MainTabView.swift
//  SweetSpots
//
//  Enhanced version with better location and geofence handling
//

import SwiftUI
import CoreLocation
import FirebaseAuth
import MapKit

// MARK: - Main Tab View
struct MainTabView: View {
    // MARK: - State & Environment
    @StateObject private var spotsViewModel: SpotViewModel
    @StateObject private var locationManager: LocationManager
    @StateObject private var collectionViewModel: CollectionViewModel
    @StateObject private var navigationViewModel: NavigationViewModel
    
    @StateObject private var launchManager = LaunchManager.shared

    
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    
    @AppStorage("globalGeofencingEnabled") private var globalGeofencingSystemEnabled: Bool = true
    
    @State private var selectedTab: Int = 0
    @State private var initialDataLoadAttemptedForCurrentSession: Bool = false
    
    enum LaunchAction: Equatable {
        case navigateToSpotID(String) // We get an ID from the notification
    }
    
    enum ActiveSheet: Identifiable {
        case sharedURLAddSpot(url: URL)
        case spotDetail(spot: Spot) // Pass the whole Spot object
        
        var id: String {
            switch self {
            case .sharedURLAddSpot(let url): return "sharedURLAddSpot-\(url.absoluteString)"
            case .spotDetail(let spot): return "spotDetail-\(spot.hashValue)" // Use hashValue
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    
    // MARK: - Initialization
    init() {
        // Correct initialization for interdependent StateObjects
        let locationManager = LocationManager()
        _locationManager = StateObject(wrappedValue: locationManager)
        
        _spotsViewModel = StateObject(wrappedValue: SpotViewModel())
        _collectionViewModel = StateObject(wrappedValue: CollectionViewModel())
        _navigationViewModel = StateObject(wrappedValue: NavigationViewModel(locationManager: locationManager))
        
        configureTabBarAppearance()
    }
    
    var body: some View {
        GeometryReader { geometry in
            // The body is now clean and simple
            dataModifiers(for: tabViewContent)
            presentationModifiers(for: tabViewContent)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .onChange(of: selectedTab) { oldValue, newValue in
            // The Map tab is at index 1
            // If we are moving AWAY from the map tab...
            if oldValue == 1 && newValue != 1 {
                // ...and if navigation is currently active...
                if navigationViewModel.isNavigating {
                    // ...tell the navigation view model to stop.
                    navigationViewModel.stopNavigation()
                }
            }
        }
    }
    
    private var tabViewContent: some View {
        TabView(selection: $selectedTab) {
            spotListTab()
            mapTab()
            settingsTab()
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
            .onReceive(NotificationCenter.default.publisher(for: .handlePendingSharedURL)) { _ in checkAndHandlePendingSharedURL() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification), perform: handleAppWillEnterForeground)
            .onChange(of: navigationViewModel.navigationState) { _, newState in
                if case .selectingRoute = newState {
                    selectedTab = 1 // Switch to the Map tab
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
            .onChange(of: launchManager.launchAction) { _, newAction in
                if newAction != nil {
                }
            }
    }

    // Helper 2b: Applies presentation modifiers
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
            AddSpotView(isPresented: sheetBinding(), spotToEdit: nil, prefilledURL: url)
        case .spotDetail(let spot):
            // Initialize the detail view with the ID from the spot object
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
    
    private func mapTab() -> some View {
        MapView()
            .tabItem {
                Label("Map", systemImage: selectedTab == 1 ? "map.fill" : "map")
            }
            .tag(1)
    }
    
    private func settingsTab() -> some View {
        SettingsView()
            .tabItem {
                Label("Settings", systemImage: selectedTab == 2 ? "gearshape.fill" : "gearshape")
            }
            .tag(2)
    }
    
    // MARK: - Helper Methods
    private func executeLaunchAction(_ action: LaunchAction) {
        if case .navigateToSpotID = action {
            // This function's only job now is to set the tab.
            // The alert is responsible for showing the UI.
            selectedTab = 1
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
        print("MainTabView.onAppear triggered.")
        checkAndHandlePendingSharedURL()
        if let userId = authViewModel.userSession?.uid, !initialDataLoadAttemptedForCurrentSession {
            print("MainTabView.onAppear with existing user session (UID: \(userId)). Performing initial setup.")
            performUserSessionSetup(userId: userId)
            initialDataLoadAttemptedForCurrentSession = true
        }
    }

    private func handleUserSessionChange(oldValue: User?, newValue: User?) {
        print("MainTabView: authViewModel.userSession changed. Old UID: \(oldValue?.uid ?? "nil"), New UID: \(newValue?.uid ?? "nil")")
        if let userId = newValue?.uid {
            // Fresh login detected
            if oldValue == nil && newValue != nil && self.launchManager.launchAction == nil { // <<<< ADDED CHECK
                print("MainTabView: Fresh login detected with NO launch action, resetting to default tab.")
                selectedTab = 0
            }
            performUserSessionSetup(userId: userId)
            initialDataLoadAttemptedForCurrentSession = true
        }  else if oldValue != nil && newValue == nil {
            print("MainTabView: User session became nil (signed out). Clearing data and listeners.")
            spotsViewModel.stopListeningAndClearData()
            collectionViewModel.detachCollectionsListener()
            locationManager.stopAllGeofences()
            initialDataLoadAttemptedForCurrentSession = false
        }
    }

    private func performUserSessionSetup(userId: String) {
        print("MainTabView: Performing setup for user UID: \(userId).")
        spotsViewModel.listenForSpots(userId: userId)
        spotsViewModel.purgeExpiredSpots(for: userId)
        collectionViewModel.fetchCollections(userId: userId)
        
        // The `.onChange(of: launchAction)` now handles this automatically.
        // We just need to load data. The rest is reactive.
        
        setupLocationServices()
        Task { await attemptInitialGeofenceSync() }
    }

    private func setupLocationServices() {
        print("MainTabView: Setting up location services")
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestLocationAuthorization(aimForAlways: false)
        }
        if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            if !locationManager.isRequestingLocationUpdates {
                locationManager.startUpdatingUserLocation()
            }
        }
    }

    private func attemptInitialGeofenceSync() async {
        guard globalGeofencingSystemEnabled else { print("MainTabView: Skipping initial geofence sync - globally disabled"); return }
        let locationOK = locationManager.authorizationStatus == .authorizedAlways
        let notificationsOK = await locationManager.requestNotificationPermissionAsync()
        if locationOK && notificationsOK {
            try? await Task.sleep(for: .milliseconds(500))
            print("MainTabView: Attempting initial geofence sync. Spots count: \(spotsViewModel.spots.count)")
            locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: true)
        } else {
            print("MainTabView: Permissions not sufficient for initial geofence sync (Location Always: \(locationOK), Notifications: \(notificationsOK))")
        }
    }

    private func handleAppWillEnterForeground(_ payload: Notification) {
        guard globalGeofencingSystemEnabled, authViewModel.userSession != nil else { return }
        print("MainTabView: App entering foreground, checking permissions and syncing geofences")
        setupLocationServices()
        Task {
            let notificationsOK = await locationManager.requestNotificationPermissionAsync()
            if notificationsOK && (locationManager.authorizationStatus == .authorizedAlways) {
                locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: true)
                print("MainTabView: Foreground geofence sync completed")
            }
        }
    }

    private func handleSpotsChange(oldValue: [Spot], newValue: [Spot]) {
        guard authViewModel.userSession != nil else { return }
        print("MainTabView: spotsViewModel.spots changed, count: \(newValue.count)")
        locationManager.synchronizeGeofences(forSpots: newValue, globallyEnabled: self.globalGeofencingSystemEnabled)
    }

    private func handleGlobalGeofencingToggle(oldValue: Bool, newValue: Bool) {
        guard authViewModel.userSession != nil else { return }
        print("MainTabView: Global geofencing toggled to: \(newValue)")
        locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: newValue)
    }

    private func handleLocationAuthorizationChange(oldValue: CLAuthorizationStatus, newValue: CLAuthorizationStatus) {
        print("MainTabView: Location authorization changed from \(LocationManager.string(for: oldValue)) to \(LocationManager.string(for: newValue))")
        
        // If the user just granted "When In Use" for the first time,
        // immediately ask them to upgrade to "Always".
        if oldValue == .notDetermined && newValue == .authorizedWhenInUse {
            print("MainTabView: User granted 'When In Use'. Immediately requesting 'Always' upgrade.")
            // Give the system a fraction of a second to settle before showing the next popup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.locationManager.requestLocationAuthorization(aimForAlways: true)
            }
        }
        
        // This existing logic is still correct for starting location updates.
        if (newValue == .authorizedWhenInUse || newValue == .authorizedAlways) && !locationManager.isRequestingLocationUpdates {
            locationManager.startUpdatingUserLocation()
        }
        
        // This existing logic is still correct for syncing geofences.
        guard authViewModel.userSession != nil, globalGeofencingSystemEnabled else { return }
        locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: newValue == .authorizedAlways && globalGeofencingSystemEnabled)
    }

    private func handleSpotNotificationTap(_ notification: Notification) {
        // Step 1: Safely unwrap the spotId from the notification's user info.
        guard let userInfo = notification.userInfo,
              let spotId = userInfo["spotId"] as? String else {
            // If we can't find a spotId, print an error and stop.
            print("MainTabView: Could not handle notification tap. Spot ID was missing from the notification's userInfo.")
            return
        }
        
        // Step 2: If the guard passes, 'spotId' is a valid String.
        // We can now use it.
        print("MainTabView: Handling notification tap for spot ID: \(spotId). Setting launch action.")
        
        // This is the single trigger for the UI. It sets the state that the
        // .onChange and .alert modifiers are watching.
        self.launchManager.launchAction = .navigateToSpotID(spotId)
    }

    private func checkAndHandlePendingSharedURL() {
        guard let urlString = UserDefaults.standard.string(forKey: AppConstants.pendingSharedURLKey) else { return }
        UserDefaults.standard.removeObject(forKey: AppConstants.pendingSharedURLKey)
        if let url = URL(string: urlString) {
            activeSheet = .sharedURLAddSpot(url: url)
        }
    }
}
