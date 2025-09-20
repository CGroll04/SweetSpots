//
//  SpotListView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI
import CoreLocation
import os.log

/// The main view displaying a filterable, sortable list of the user's spots.
struct SpotListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var navigationViewModel: NavigationViewModel

    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SpotListView")
    
    // MARK: - UI State
    @State private var searchText = ""
    @State private var showingAddSheet: Bool = false
    @State private var spotToEdit: Spot? = nil
    @State private var collectionToEdit: SpotCollection? = nil
    @State private var spotToDelete: Spot? = nil
    @State private var showingDeleteConfirmation = false
//    @State private var selectedTab: SpotTab = .notVisited
    
    @State private var itemToShare: ShareableContent? = nil
    


    // MARK: - Filtering & Sorting State
    @State private var selectedCategoryFilters: Set<SpotCategory> = []
    @State private var currentSortOrder: SortOrder = .distanceAscending
    @State private var selectedCollectionFilterId: String? = nil
    @State private var showingFilterPopover: Bool = false
    @State private var collectionFilterState: CollectionFilterState = .all
    
    // State to control side menu presentation
    @State private var showingSettingsSheet: Bool = false
    
    // MARK: - Geofencing State
    @State private var hasInitializedGeofences = false
    @AppStorage("globalGeofencingEnabled") private var geofencingGloballyEnabled: Bool = true
    
    private var isShowingEditSheet: Binding<Bool> {
        Binding(
            get: { spotToEdit != nil },
            set: { if !$0 { spotToEdit = nil } }
        )
    }
    
//    private var notVisitedSpots: [Spot] {
//        displayedSpots.filter { $0.visitCount == 0 }
//    }
//
//    private var visitedSpots: [Spot] {
//        displayedSpots.filter { $0.visitCount > 0 }
//    }
    
//    enum SpotTab {
//        case notVisited
//        case visited
//    }
    
    enum CollectionFilterState: String, CaseIterable {
        case all = "All Spots"
        case inCollection = "In Collections"
        case notInCollection = "Not in a Collection"
    }

    private var displayedSpots: [Spot] {
        var workingSpots = spotsViewModel.spots

        if let collectionId = selectedCollectionFilterId {
            // Find spots whose collectionIds array CONTAINS the selected ID
            workingSpots = workingSpots.filter { $0.collectionIds.contains(collectionId) }
        } else {
            // This logic updates the popover filter
            switch collectionFilterState {
            case .all:
                break // Do nothing
            case .inCollection:
                // Find spots that are in AT LEAST ONE collection
                workingSpots = workingSpots.filter { !$0.collectionIds.isEmpty }
            case .notInCollection:
                // Find spots that are in NO collections
                workingSpots = workingSpots.filter { $0.collectionIds.isEmpty }
            }
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
                logger.info("Cannot sort by distance, user location not available.")
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
            // This is STAGE 2. It takes the view from the property below
            // and adds the final alert and lifecycle modifiers.
            baseContentWithModifiers
                .alert(
                    "Delete SweetSpot",
                    isPresented: $showingDeleteConfirmation,
                    presenting: spotToDelete
                ) { spot in
                    Button("Delete", role: .destructive) {
                        spotsViewModel.deleteSpot(spot) { result in
                            if case .failure(let error) = result {
                                spotsViewModel.errorMessage = "Failed to delete: \(error.localizedDescription)"
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { spot in
                    Text("This will move \"\(spot.name)\" to the Recently Deleted section, where it will be permanently deleted after 30 days.")
                }
                .onAppear {
                    initialLoadTasks()
                }
                .onChange(of: collectionViewModel.collections) {
                    if let currentId = selectedCollectionFilterId {
                        if !collectionViewModel.collections.contains(where: { $0.id == currentId }) {
                            selectedCollectionFilterId = nil
                        }
                    }
                }
                .onChange(of: spotsViewModel.spots) { oldSpots, newSpots in
                    logger.info("spotsViewModel.spots changed. Count: \(newSpots.count)")
                    
                    // Check if any spot's notification setting changed
                    let oldNotificationSpots = Set(oldSpots.filter { $0.wantsNearbyNotification }.compactMap { $0.id })
                    let newNotificationSpots = Set(newSpots.filter { $0.wantsNearbyNotification }.compactMap { $0.id })
                    
                    if oldNotificationSpots != newNotificationSpots {
                        logger.info("Spot notification settings changed, updating geofences")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            syncGeofencesIfReady()
                        }
                    }
                }
                .onChange(of: locationManager.userLocation) { _, newLocation in
                    if currentSortOrder == .distanceAscending && newLocation != nil {
                        logger.info("User location changed, spots will re-sort automatically.")
                    }
                }
                .onChange(of: locationManager.authorizationStatus) { _, newStatus in
                    logger.info("Location authorization status changed to: \(LocationManager.string(for: newStatus))")
                    
                    if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                        if !locationManager.isRequestingLocationUpdates {
                            logger.info("Permission granted, starting location updates.")
                            locationManager.startUpdatingUserLocation()
                        }
                        
                        if newStatus == .authorizedAlways {
                            logger.info("Got Always permission, syncing geofences")
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        syncGeofencesIfReady()
                    }
                }
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
        VStack(spacing: 0) {
            Spacer().frame(height: 1)
            coreZStackContent
        }
        .navigationTitle(currentNavigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.themeBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { navigationToolbarItems() }
        .searchable(text: $searchText, prompt: "Search spots...")
        .navigationDestination(for: Spot.self) { spot in
            SpotDetailView(spotId: spot.id ?? "", presentedFrom: .list)
                .environmentObject(spotsViewModel)
                .environmentObject(locationManager)
                .environmentObject(navigationViewModel)
                .environmentObject(collectionViewModel)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSpotView(isPresented: $showingAddSheet, spotToEdit: nil,prefilledPayload: nil, prefilledURL: nil)
                .environmentObject(spotsViewModel)
                .environmentObject(authViewModel)
                .environmentObject(locationManager)
                .environmentObject(collectionViewModel)
                .environmentObject(navigationViewModel)
        }
        .sheet(isPresented: isShowingEditSheet, onDismiss: {
            logger.info("Edit Spot sheet dismissed. Real-time listener will handle updates.")
        }) {
            if let spot = spotToEdit {
                AddSpotView(isPresented: isShowingEditSheet, spotToEdit: spot,prefilledPayload: nil, prefilledURL: nil)
                    .environmentObject(spotsViewModel)
                    .environmentObject(authViewModel)
                    .environmentObject(locationManager)
                    .environmentObject(collectionViewModel)
                    .environmentObject(navigationViewModel)
            }
        }
        .sheet(item: $itemToShare) { item in
            ShareSheet(items: [item.text, item.url])
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView(onDismiss: { showingSettingsSheet = false })
        }
    }

    // MARK: - View Content Logic
    @ViewBuilder
    private func contentView() -> some View {
        if spotsViewModel.isLoading && spotsViewModel.spots.isEmpty {
            loadingStateView()
        } else if displayedSpots.isEmpty && spotsViewModel.spots.isEmpty && !spotsViewModel.isLoading {
             emptyStateView(description: "Looks a bit empty here! Tap the '+' button to add your first SweetSpot.")
        } else if displayedSpots.isEmpty {
            emptyStateView(description: emptyStateDescriptionForFilters())
        } else {
            Spacer()
            spotList(for: displayedSpots)
//            spotsScrollView()
        }
    }

    private func loadingStateView() -> some View {
        VStack {
            Spacer()
            ProgressView().scaleEffect(1.5).tint(Color.themePrimary)
            Text("Loading your SweetSpots...").font(.headline).foregroundStyle(Color.themeTextSecondary).padding(.top)
            Spacer()
        }
    }
    
    private func emptyStateView(description: String) -> some View {
        ThemedContentUnavailableView(
            title: "No SweetSpots",
            systemImage: "sparkle.magnifyingglass",
            description: description
        )
    }
    
//    private func spotsScrollView() -> some View {
//        VStack(spacing: 0) {
//            // 1. The Top Menu Bar (Segmented Picker)
//            Picker("Spots", selection: $selectedTab.animation()) {
//                Text("Bucket List (\(notVisitedSpots.count))").tag(SpotTab.notVisited)
//                Text("Visited (\(visitedSpots.count))").tag(SpotTab.visited)
//            }
//            .pickerStyle(.segmented)
//            .padding()
//
//            // 2. The TabView that holds the lists
//            TabView(selection: $selectedTab) {
//                spotList(for: notVisitedSpots)
//                    .tag(SpotTab.notVisited)
//
//                spotList(for: visitedSpots)
//                    .tag(SpotTab.visited)
//            }
//            .tabViewStyle(.page(indexDisplayMode: .never))
//        }
//    }

    // Helper view to avoid duplicating the list code
    @ViewBuilder
    private func spotList(for spots: [Spot]) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(spots) { spot in
                    NavigationLink(value: spot) {
                        SpotCardView(
                            spot: spot,
                            userLocation: locationManager.userLocation,
                            onEdit: { editSpot(spot) },
                            onDelete: { requestDeleteConfirmation(for: spot) },
//                            onIncrement: { handleIncrement(for: spot) }, // Updated
//                            onDecrement: { spotsViewModel.decrementVisitCount(for: spot) },
//                            onReset: {
//                                    withAnimation {
//                                        selectedTab = .notVisited
//                                    }
//                                    spotsViewModel.resetVisitCount(for: spot)
//                                },
                            
                            
                            onShare: {
                                Task {
                                    await handleShare(for: spot)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    struct SectionHeader: View {
        let title: String
        let icon: String
        let count: Int

        var body: some View {
            HStack {
                Image(systemName: icon).foregroundStyle(Color.themeAccent)
                Text(title).font(.headline)
                Spacer()
                Text("(\(count))").foregroundStyle(.secondary).font(.subheadline)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func handleShare(for spot: Spot) async {
        guard let userId = authViewModel.userSession?.uid else { return }

        do {
            let senderName = authViewModel.userSession?.displayName

            let url = try await SpotShareManager.makeShareURL(
                from: spot,
                collectionName: nil, // We pass nil as a spot can be in many collections
                senderName: senderName,
                userId: userId
            )

            let text = senderName != nil ? "\(senderName!) shared '\(spot.name)' with you!" : "Check out '\(spot.name)' on SweetSpots!"
            itemToShare = ShareableContent(text: text, url: url)

        } catch {
            logger.error("Failed to create share link: \(error)")
            // Optionally, show an error alert here
        }
    }
    
//    private func handleIncrement(for spot: Spot) {
//        // Check if this is the FIRST visit
//        if spot.visitCount == 0 {
//            // If so, switch to the "Visited" tab with an animation
//            withAnimation {
//                selectedTab = .visited
//            }
//        }
//        // Then, call the ViewModel to increment the count as before
//        spotsViewModel.incrementVisitCount(for: spot)
//    }
    
    // MARK: - Toolbar
    @ToolbarContentBuilder
    private func navigationToolbarItems() -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            
            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Color.themePrimary)
            }
            
            sortMenu()
            
            Button {
                showingFilterPopover = true
            } label: {
                let isFilterActive = collectionFilterState != .all || !selectedCategoryFilters.isEmpty
                Label("Filter", systemImage: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(Color.themePrimary)
            }
            .popover(isPresented: $showingFilterPopover) {
                FilterMenuView(
                    collectionFilterState: $collectionFilterState,
                    selectedCategoryFilters: $selectedCategoryFilters,
                    showCollectionFilterOptions: true
                )
                .presentationCompactAdaptation(.popover)
            }
            
            Button {
                showingSettingsSheet = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(Color.themePrimary)
            }
        }
    }

    // MARK: - Data & State Management
    private func initialLoadTasks() {
        if let userId = authViewModel.userSession?.uid,
           collectionViewModel.collections.isEmpty && !collectionViewModel.isLoading {
            collectionViewModel.listenForCollections(userId: userId)
        }

        // Handle Location Permission Request
        if locationManager.userLocation == nil {
            logger.info("Default sort is distance. Requesting location.")
            locationManager.requestLocationAuthorization(aimForAlways: false)
        } else if !locationManager.isRequestingLocationUpdates &&
                  (locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways) {
            logger.info("Location available from previous session, ensuring updates are active.")
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
        
        logger.info("Navigating to spot from geofence notification: \(spotId)")
        
        if let spot = spotsViewModel.spots.first(where: { $0.id == spotId }) {
            // Could implement scroll-to-spot functionality here
            logger.info("Found spot to navigate to: \(spot.name)")
        }
    }
    
    private func initializeGeofencesIfNeeded() {
        guard !hasInitializedGeofences else { return }
        
        logger.info("Initializing geofences...")
        hasInitializedGeofences = true
        
        // Sync geofences with current spots
        syncGeofencesIfReady()
    }
    
    private func syncGeofencesIfReady() {
        guard geofencingGloballyEnabled else {
            logger.info("Geofencing disabled globally")
            locationManager.stopAllGeofences()
            return
        }
        
        // Check if we have the necessary permissions
        guard locationManager.authorizationStatus == .authorizedAlways else {
            logger.info("Need 'Always' location permission for geofencing")
            
            // If user has 'When In Use', we could prompt them to upgrade
            if locationManager.authorizationStatus == .authorizedWhenInUse {
                promptForAlwaysLocationPermission()
            }
            return
        }
        
        // Sync geofences with current spots
        let spotsWithNotifications = spotsViewModel.spots.filter { $0.wantsNearbyNotification }
        logger.info("Syncing geofences for \(spotsWithNotifications.count) spots with notifications enabled")
        
        locationManager.synchronizeGeofences(
            forSpots: spotsViewModel.spots,
            globallyEnabled: geofencingGloballyEnabled
        )
    }
    
    private func promptForAlwaysLocationPermission() {
        // This could show a custom alert explaining why Always permission is needed
        logger.info("Could show alert explaining Always permission benefits")
        
        locationManager.requestLocationAuthorization(aimForAlways: true)
    }
    
    private func toggleGeofencingGlobally() {
        geofencingGloballyEnabled.toggle()
        
        // Update geofences immediately
        syncGeofencesIfReady()
    }


    // MARK: - Action Handlers & Dynamic UI
    private func editSpot(_ spot: Spot) {
        logger.debug("Setting spotToEdit: '\(spot.name)' (ID: \(spot.id ?? "nil")) - wantsNotification: \(spot.wantsNearbyNotification)")
        
        // Get the latest spot data before editing
        if let spotId = spot.id,
           let latestSpot = spotsViewModel.spots.first(where: { $0.id == spotId }) {
            logger.debug("Using latest spot data - wantsNotification: \(latestSpot.wantsNearbyNotification)")
            self.spotToEdit = latestSpot
        } else {
            logger.debug("Using original spot data (fallback)")
            self.spotToEdit = spot
        }
    }

    private func requestDeleteConfirmation(for spot: Spot) {
        self.spotToDelete = spot
        self.showingDeleteConfirmation = true
    }
    
    private var currentNavigationTitle: String {
        // 1. If a specific collection is selected from the side menu, use its name.
        if let id = selectedCollectionFilterId, let coll = collectionViewModel.collections.first(where: { $0.id == id }) {
            return coll.name
        }
        
        // 2. Otherwise, use the state from our new filter popover.
        switch collectionFilterState {
        case .all:
            return "My SweetSpots" // Default title
        case .inCollection:
            return "In Collections"
        case .notInCollection:
            return "Not in a Collection"
        }
    }
    
    private func emptyStateDescriptionForFilters() -> String {
        if !searchText.isEmpty {
            return "No spots match your search. Try different keywords or clear filters."
        }
        // Check for side menu filter first
        if selectedCollectionFilterId != nil {
            return "This collection is empty. Add some spots to it!"
        }
        
        switch collectionFilterState {
        case .inCollection:
            return "None of your spots are in a collection."
        case .notInCollection:
            return "All of your spots are currently in a collection."
        case .all:
            // If it's ".all", we fall through to the category check
            break
        }
        
        if !selectedCategoryFilters.isEmpty {
            return "No spots match your selected categories. Try different ones or clear filters!"
        }
        
        return "No spots match the current filters."
    }

    // MARK: - Menus

    @ViewBuilder private func categoryFilterButtons() -> some View {
        Button(action: { selectedCategoryFilters.removeAll() }) {
            Label {
                // This is the text part of the label
                Text("All Categories")
            } icon: {
                Image(systemName: selectedCategoryFilters.isEmpty ? "checkmark.circle.fill" : "circle")
                    .font(.callout)
            }
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
