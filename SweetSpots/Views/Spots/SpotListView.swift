//
//  SpotListView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI
import CoreLocation // Needed for CLLocation and CLLocationCoordinate2D

struct SpotListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var navigationViewModel: NavigationViewModel

    // MARK: - UI State
    @State private var searchText = ""
    @State private var spotToEdit: Spot? = nil
    @State private var collectionToEdit: SpotCollection? = nil

    // MARK: - Filtering & Sorting State
    @State private var selectedCategoryFilters: Set<SpotCategory> = []
    @State private var currentSortOrder: SortOrder = .distanceAscending
    @State private var selectedCollectionFilterId: String? = nil
    @State private var showOnlyUncategorized: Bool = false
    
    // State to control side menu presentation
    @State private var showingSideMenu: Bool = false
    
    // MARK: - Geofencing State
    @State private var hasInitializedGeofences = false
    @State private var geofencingGloballyEnabled = true

    private var isShowingEditSheet: Binding<Bool> {
        Binding(
            get: { spotToEdit != nil },
            set: { if !$0 { spotToEdit = nil } }
        )
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case nameAscending = "Name (A-Z)"
        case nameDescending = "Name (Z-A)"
        case categoryAscending = "Category (A-Z)"
        case distanceAscending = "Distance (Nearest)"
        var id: String { self.rawValue }
    }

    // ✅ FIXED: Computed property instead of @State for displayedSpots
    private var displayedSpots: [Spot] {
        var workingSpots = spotsViewModel.spots

        if showOnlyUncategorized {
            workingSpots = workingSpots.filter { $0.collectionId == nil }
        } else if let collectionId = selectedCollectionFilterId {
            workingSpots = workingSpots.filter { $0.collectionId == collectionId }
        }
        
        if !selectedCategoryFilters.isEmpty {
            workingSpots = workingSpots.filter { selectedCategoryFilters.contains($0.category) }
        }

        if !searchText.isEmpty {
            let lowercasedSearchText = searchText.lowercased()
            workingSpots = workingSpots.filter { spot in
                spot.name.lowercased().contains(lowercasedSearchText) ||
                spot.address.lowercased().contains(lowercasedSearchText) ||
                spot.category.displayName.lowercased().contains(lowercasedSearchText)
            }
        }

        switch currentSortOrder {
        case .dateDescending:
            workingSpots.sort { ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast) }
        case .dateAscending:
            workingSpots.sort { ($0.createdAt?.dateValue() ?? .distantFuture) < ($1.createdAt?.dateValue() ?? .distantFuture) }
        case .nameAscending:
            workingSpots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            workingSpots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .categoryAscending:
            workingSpots.sort { $0.category.displayName.localizedCaseInsensitiveCompare($1.category.displayName) == .orderedAscending }
        case .distanceAscending:
            guard let userCurrentLocation = locationManager.userLocation else {
                print("SpotListView: Cannot sort by distance, user location not available.")
                break
            }
            let clUserLocation = CLLocation(latitude: userCurrentLocation.coordinate.latitude, longitude: userCurrentLocation.coordinate.longitude)
            workingSpots.sort { spot1, spot2 in
                let loc1 = CLLocation(latitude: spot1.latitude, longitude: spot1.longitude)
                let loc2 = CLLocation(latitude: spot2.latitude, longitude: spot2.longitude)
                return loc1.distance(from: clUserLocation) < loc2.distance(from: clUserLocation)
            }
        }
        
        return workingSpots
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            baseContentWithModifiers
        }
    }
    
    // Layer 1: The core ZStack content
    private var coreZStackContent: some View {
        ZStack {
            Color.themeBackground.ignoresSafeArea()
            contentView()
        }
    }

    // Layer 2: Apply modifiers in stages
    private var baseContentWithModifiers: some View {
            let navigationConfiguredContent = coreZStackContent
                .navigationTitle(currentNavigationTitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Color.themeBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar { navigationToolbarItems() }
                .searchable(text: $searchText, prompt: "Search spots...")
                .navigationDestination(for: Spot.self) { spot in
                    // ✅ STEP 2: PASS THE ENVIRONMENT OBJECTS
                    SpotDetailView(spotId: spot.id ?? "")
                        .environmentObject(spotsViewModel)
                        .environmentObject(locationManager)
                        .environmentObject(navigationViewModel)
                }
                .sheet(isPresented: isShowingEditSheet, onDismiss: {
                    print("SpotListView: Edit Spot sheet dismissed. Real-time listener will handle updates.")
                }) {
                    if let spot = spotToEdit {
                        // This sheet also needs the environment objects
                        AddSpotView(isPresented: isShowingEditSheet, spotToEdit: spot, prefilledURL: nil)
                            .environmentObject(spotsViewModel)
                            .environmentObject(authViewModel)
                            .environmentObject(locationManager)
                            .environmentObject(collectionViewModel)
                            .environmentObject(navigationViewModel)
                    }
                }
                .sheet(isPresented: $showingSideMenu) {
                    SideMenuView(
                        selectedCollectionFilterId: $selectedCollectionFilterId,
                        showOnlyUncategorized: $showOnlyUncategorized,
                        onDismiss: { showingSideMenu = false }
                    )
                    .environmentObject(collectionViewModel)
                    .environmentObject(spotsViewModel)
                    .environmentObject(authViewModel)
                    .environmentObject(locationManager)
                    .environmentObject(navigationViewModel)
                }

        // Stage 2: Apply lifecycle and onChange modifiers
        let finalContent = navigationConfiguredContent
            .onAppear {
                // Load geofencing setting from UserDefaults
                geofencingGloballyEnabled = UserDefaults.standard.object(forKey: "GeofencingGloballyEnabled") as? Bool ?? true
                initialLoadTasks()
            }
            .onChange(of: spotsViewModel.spots) { oldSpots, newSpots in
                print("SpotListView: spotsViewModel.spots changed. Count: \(newSpots.count)")
                
                // Check if any spot's notification setting changed
                let oldNotificationSpots = Set(oldSpots.filter { $0.wantsNearbyNotification }.compactMap { $0.id })
                let newNotificationSpots = Set(newSpots.filter { $0.wantsNearbyNotification }.compactMap { $0.id })
                
                if oldNotificationSpots != newNotificationSpots {
                    print("SpotListView: Spot notification settings changed, updating geofences")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        syncGeofencesIfReady()
                    }
                }
            }
            .onChange(of: locationManager.userLocation) { _, newLocation in
                if currentSortOrder == .distanceAscending && newLocation != nil {
                    print("SpotListView: User location changed, spots will re-sort automatically.")
                }
            }
            .onChange(of: locationManager.authorizationStatus) { _, newStatus in
                print("SpotListView: Location authorization status changed to: \(LocationManager.string(for: newStatus))")
                
                if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                    if !locationManager.isRequestingLocationUpdates {
                        print("SpotListView: Permission granted, starting location updates.")
                        locationManager.startUpdatingUserLocation()
                    }
                    
                    // If we now have Always permission, sync geofences
                    if newStatus == .authorizedAlways {
                        print("SpotListView: Got Always permission, syncing geofences")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            syncGeofencesIfReady()
                        }
                    }
                } else if newStatus == .denied || newStatus == .restricted {
                    // Stop geofences if permission was revoked
                    locationManager.stopAllGeofences()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shouldNavigateToSpot)) { notification in
                handleGeofenceNavigation(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .applicationDidBecomeActive)) { _ in
                // Re-sync geofences when app becomes active
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    syncGeofencesIfReady()
                }
            }
        
        return finalContent
    }

    // MARK: - View Content Logic
    @ViewBuilder
    private func contentView() -> some View {
        if spotsViewModel.isLoading && spotsViewModel.spots.isEmpty {
            loadingStateView()
        } else if displayedSpots.isEmpty && spotsViewModel.spots.isEmpty && !spotsViewModel.isLoading {
             emptyStateView(description: "Looks a bit empty here! Tap the '+' button to add your first memorable SweetSpot.")
        } else if displayedSpots.isEmpty {
            emptyStateView(description: emptyStateDescriptionForFilters())
        } else {
            spotsScrollView()
        }
    }

    private func loadingStateView() -> some View {
        VStack {
            Spacer()
            ProgressView().scaleEffect(1.5).tint(Color.themePrimary)
            Text("Loading your Sweet Spots...").font(.headline).foregroundStyle(Color.themeTextSecondary).padding(.top)
            Spacer()
        }
    }
    
    private func emptyStateView(description: String) -> some View {
        ThemedContentUnavailableView(
            title: "No Sweet Spots",
            systemImage: "sparkle.magnifyingglass",
            description: description
        )
    }

    private func spotsScrollView() -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let errorMessage = spotsViewModel.errorMessage, !errorMessage.isEmpty {
                    ErrorBannerView(message: errorMessage)
                        .padding(.horizontal)
                }
                ForEach(displayedSpots) { spot in
                    NavigationLink(value: spot) {
                        SpotCardView(
                            spot: spot,
                            userLocation: locationManager.userLocation,
                            onEdit: { editSpot(spot) },
                            onDelete: { deleteSpot(spot) }
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
    }
    
    // MARK: - Toolbar
    @ToolbarContentBuilder
    private func navigationToolbarItems() -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button {
                showingSideMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Color.themePrimary)
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            sortMenu()
            categoryFilterMenuForList()
        }
    }

    // MARK: - Data & State Management
    private func initialLoadTasks() {
        if let userId = authViewModel.userSession?.uid,
           collectionViewModel.collections.isEmpty && !collectionViewModel.isLoading {
            collectionViewModel.fetchCollections(userId: userId)
        }

        // Handle Location Permission Request
        if locationManager.userLocation == nil {
            print("SpotListView: Default sort is distance. Requesting location.")
            locationManager.requestLocationAuthorization(aimForAlways: false)
        } else if !locationManager.isRequestingLocationUpdates &&
                  (locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways) {
            print("SpotListView: Location available from previous session, ensuring updates are active.")
            locationManager.startUpdatingUserLocation()
        }
        
        // Initialize geofences after a brief delay to ensure spots are loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            initializeGeofencesIfNeeded()
        }
    }
    
    // MARK: - Geofencing Management
    private func handleGeofenceNavigation(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let spotId = userInfo["spotId"] as? String else {
            return
        }
        
        print("SpotListView: Navigating to spot from geofence notification: \(spotId)")
        
        // You might want to navigate directly or highlight the spot
        // For now, just scroll to the spot if it's visible
        if let spot = spotsViewModel.spots.first(where: { $0.id == spotId }) {
            // Could implement scroll-to-spot functionality here
            print("Found spot to navigate to: \(spot.name)")
        }
    }
    
    private func initializeGeofencesIfNeeded() {
        guard !hasInitializedGeofences else { return }
        
        print("SpotListView: Initializing geofences...")
        hasInitializedGeofences = true
        
        // Sync geofences with current spots
        syncGeofencesIfReady()
    }
    
    private func syncGeofencesIfReady() {
        guard geofencingGloballyEnabled else {
            print("SpotListView: Geofencing disabled globally")
            locationManager.stopAllGeofences()
            return
        }
        
        // Check if we have the necessary permissions
        guard locationManager.authorizationStatus == .authorizedAlways else {
            print("SpotListView: Need 'Always' location permission for geofencing")
            
            // If user has 'When In Use', we could prompt them to upgrade
            if locationManager.authorizationStatus == .authorizedWhenInUse {
                promptForAlwaysLocationPermission()
            }
            return
        }
        
        // Sync geofences with current spots
        let spotsWithNotifications = spotsViewModel.spots.filter { $0.wantsNearbyNotification }
        print("SpotListView: Syncing geofences for \(spotsWithNotifications.count) spots with notifications enabled")
        
        locationManager.synchronizeGeofences(
            forSpots: spotsViewModel.spots,
            globallyEnabled: geofencingGloballyEnabled
        )
    }
    
    private func promptForAlwaysLocationPermission() {
        // This could show a custom alert explaining why Always permission is needed
        print("SpotListView: Could show alert explaining Always permission benefits")
        
        // For now, just request the permission
        locationManager.requestLocationAuthorization(aimForAlways: true)
    }
    
    private func toggleGeofencingGlobally() {
        geofencingGloballyEnabled.toggle()
        
        // Save to UserDefaults
        UserDefaults.standard.set(geofencingGloballyEnabled, forKey: "GeofencingGloballyEnabled")
        
        // Update geofences immediately
        syncGeofencesIfReady()
    }

    // ✅ REMOVED: updateDisplayedSpots() method since we're using computed property

    // MARK: - Action Handlers & Dynamic UI
    private func editSpot(_ spot: Spot) {
        print("SPOT_LIST_VIEW_EDIT_SPOT: Setting spotToEdit: '\(spot.name)' (ID: \(spot.id ?? "nil")) - wantsNotification: \(spot.wantsNearbyNotification)")
        
        // Get the latest spot data before editing
        if let spotId = spot.id,
           let latestSpot = spotsViewModel.spots.first(where: { $0.id == spotId }) {
            print("SPOT_LIST_VIEW_EDIT_SPOT: Using latest spot data - wantsNotification: \(latestSpot.wantsNearbyNotification)")
            self.spotToEdit = latestSpot
        } else {
            print("SPOT_LIST_VIEW_EDIT_SPOT: Using original spot data (fallback)")
            self.spotToEdit = spot
        }
    }

    private func deleteSpot(_ spot: Spot) {
        spotsViewModel.deleteSpot(spot) { result in
            if case .failure(let error) = result {
                spotsViewModel.errorMessage = "Failed to delete spot: \(error.localizedDescription)"
            }
        }
    }

    private var currentNavigationTitle: String {
        if showOnlyUncategorized { return "Uncategorized" }
        if let id = selectedCollectionFilterId, let coll = collectionViewModel.collections.first(where: { $0.id == id }) { return coll.name }
        return "My Sweet Spots"
    }
    
    private func emptyStateDescriptionForFilters() -> String {
        if !searchText.isEmpty { return "No spots match your search. Try different keywords or clear filters." }
        if showOnlyUncategorized { return "You have no spots that aren't in a collection." }
        if selectedCollectionFilterId != nil { return "This collection is empty. Add some spots to it!" }
        if !selectedCategoryFilters.isEmpty { return "No spots match your selected categories. Try different ones or clear filters!"}
        return "No spots match the current filters."
    }

    // MARK: - Menus
    private func categoryFilterMenuForList() -> some View {
        Menu {
            if !SpotCategory.allCases.isEmpty {
                categoryFilterButtons()
            } else {
                Text("No Categories Available")
            }
        } label: {
            Label("Categories", systemImage: selectedCategoryFilters.isEmpty ? "tag.circle" : "tag.circle.fill")
                .foregroundStyle(Color.themePrimary)
        }
    }

    @ViewBuilder private func categoryFilterButtons() -> some View {
        Button(action: { selectedCategoryFilters.removeAll() }) {
            Label("All Categories", systemImage: selectedCategoryFilters.isEmpty ? "checkmark.circle.fill" : "circle")
        }
        Divider()
        ForEach(SpotCategory.allCases) { category in
            Toggle(isOn: Binding(
                get: { selectedCategoryFilters.contains(category) },
                set: { if $0 { selectedCategoryFilters.insert(category) } else { selectedCategoryFilters.remove(category) } }
            )) {
                Label(category.displayName, systemImage: category.systemImageName)
            }
        }
    }

    private func sortMenu() -> some View {
        Menu {
            Picker("Sort By", selection: $currentSortOrder) {
                ForEach(SortOrder.allCases) { order in Text(order.rawValue).tag(order) }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down.circle").foregroundStyle(Color.themePrimary)
        }
    }
}

// MARK: - SpotCardView
struct SpotCardView: View {
    let spot: Spot
    let userLocation: CLLocation?
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var distanceString: String {
        guard let userLoc = userLocation else { return "" }
        let spotLoc = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let distanceInMeters = userLoc.distance(from: spotLoc)
        
        let formatter = LengthFormatter()
        formatter.numberFormatter.maximumFractionDigits = 1
        
        if Locale.current.measurementSystem == .us {
            let distanceInFeet = distanceInMeters * 3.28084
            if distanceInFeet < 528 {
                formatter.numberFormatter.maximumFractionDigits = 0
                return formatter.string(fromValue: distanceInFeet, unit: .foot)
            } else {
                let distanceInMiles = distanceInMeters / 1609.34
                return formatter.string(fromValue: distanceInMiles, unit: .mile)
            }
        } else {
            if distanceInMeters < 100 {
                 formatter.numberFormatter.maximumFractionDigits = 0
                return formatter.string(fromValue: distanceInMeters, unit: .meter)
            } else {
                let distanceInKilometers = distanceInMeters / 1000
                return formatter.string(fromValue: distanceInKilometers, unit: .kilometer)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: spot.category.systemImageName)
                .font(.system(size: 20)).foregroundStyle(Color.white)
                .frame(width: 40, height: 40).background(Color.themePrimary).clipShape(Circle())
                .padding(.leading, 16).padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name).font(.headline).fontWeight(.semibold).foregroundStyle(Color.themeTextPrimary).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "mappin").font(.caption).foregroundStyle(Color.themeAccent)
                    Text(spot.address).font(.caption).foregroundStyle(Color.themeTextSecondary).lineLimit(1)
                }
                if userLocation != nil, !distanceString.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.fill").font(.caption2).foregroundStyle(Color.themeAccent)
                        Text(distanceString).font(.caption2).foregroundStyle(Color.themeTextSecondary)
                    }
                }
            }
            .padding(.vertical, 10)
            Spacer()
            HStack(spacing: 10) {
                actionButton(systemName: "pencil", backgroundColor: .themePrimary, action: onEdit)
                actionButton(systemName: "trash", backgroundColor: .themeError, action: onDelete)
            }
            .padding(.trailing, 8)
            Image(systemName: "chevron.right").font(.callout).foregroundStyle(Color.themeTextSecondary.opacity(0.6)).padding(.trailing, 16)
        }
        .frame(minHeight: 80).padding(.vertical, 6).background(Material.thin).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.themeTextSecondary.opacity(0.1), lineWidth: 1))
    }

    private func actionButton(systemName: String, backgroundColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 16)).foregroundStyle(Color.white)
                .frame(width: 28, height: 28).background(backgroundColor).clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - ThemedContentUnavailableView
struct ThemedContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage).font(.system(size: 48, weight: .light)).foregroundStyle(Color.themePrimary.opacity(0.7))
            Text(title).font(.title2).fontWeight(.semibold).foregroundStyle(Color.themePrimary)
            if let description = description, !description.isEmpty {
                Text(description).font(.callout).foregroundStyle(Color.themeTextSecondary).multilineTextAlignment(.center).padding(.horizontal, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

// MARK: - ErrorBannerView
struct ErrorBannerView: View {
    let message: String
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.white)
            Text(message).font(.footnote).fontWeight(.medium).foregroundStyle(Color.white)
            Spacer()
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .background(Color.themeError.opacity(0.9)).clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
