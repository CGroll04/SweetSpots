//
//  CollectionDetailView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-08.
//

import SwiftUI
import MapKit

struct CollectionDetailView: View {
    // MARK: - Environment
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    
    
    // MARK: - State
    let collectionID: String
    
    // Note 2: We'll use the exact same SortOrder enum from your SpotListView
    enum SortOrder: String, CaseIterable, Identifiable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case nameAscending = "Name (A-Z)"
        case nameDescending = "Name (Z-A)"
        case categoryAscending = "Category (A-Z)"
        case distanceAscending = "Distance (Nearest)"
        var id: String { self.rawValue }
    }
    
    // Note 2: State for sorting and filtering, matching SpotListView
    @State private var currentSortOrder: SortOrder = .dateDescending
    @State private var selectedCategoryFilters: Set<SpotCategory> = []
    @State private var isShowingFilterSheet = false
    
    // State for view presentation
    @State private var selectedTab: Int = 0 // 0 for List, 1 for Map
    @State private var isShowingEditCollectionSheet = false // Was isShowingEditSheet
    @State private var isShowingManageSpotsSheet = false
    @State private var isShowingDeleteConfirmation = false
    @State private var itemToShare: ShareableContent? = nil
    
    @State private var spotToEdit: Spot? = nil
    @State private var spotToDelete: Spot? = nil
    @State private var showingDeleteConfirmationForSpot = false // Use a new name to avoid conflicts
    
    // --- STATE FOR MAP VIEW ---
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedMapSpot: Spot? = nil // For pin selection
    
    private var isShowingEditSpotSheet: Binding<Bool> {
            Binding(
                get: { spotToEdit != nil },
                set: { isShowing in
                    if !isShowing {
                        spotToEdit = nil
                    }
                }
            )
        }

    
    // MARK: - Computed Properties
    private var liveCollection: SpotCollection? {
        collectionViewModel.collections.first { $0.id == collectionID }
    }
    
    // The 'displayedSpots' property now includes your sorting and filtering logic
    private var displayedSpots: [Spot] {
        guard let collectionId = liveCollection?.id else { return [] }
        
        var workingSpots = spotsViewModel.spots.filter { $0.collectionIds.contains(collectionId) }
        
        // Apply category filters
        if !selectedCategoryFilters.isEmpty {
            workingSpots = workingSpots.filter { selectedCategoryFilters.contains($0.category) }
        }

        // Apply sorting
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
            guard let userLocation = locationManager.userLocation else { break }
            let clUserLocation = CLLocation(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude)
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
        if let collection = liveCollection {
            VStack(spacing: 0) {
                // The large header buttons have been removed as requested.
                headerView(for: collection)
                
                Picker("View Mode", selection: $selectedTab) {
                    Text("List").tag(0)
                    Text("Map").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    listView(for: collection)
                } else {
                    mapView
                }
            }
            .background(Color.themeBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    sortMenu
                    filterButton
                    moreMenu(for: collection)
                }
            }
            .sheet(item: $selectedMapSpot) { spot in
                SpotDetailView(spotId: spot.id ?? "", presentedFrom: .map)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $spotToEdit) { spot in
                // Because we use .sheet(item:), SwiftUI guarantees `spot` is not nil here.
                // We pass our computed binding to the AddSpotView.
                AddSpotView(isPresented: isShowingEditSpotSheet, spotToEdit: spot,prefilledPayload: nil, prefilledURL: nil)
                // EnvironmentObjects are passed down automatically to sheets
            }
            .confirmationDialog(
                "Delete Spot",
                isPresented: $showingDeleteConfirmationForSpot,
                presenting: spotToDelete
            ) { spot in
                Button("Delete Spot", role: .destructive) {
                    spotsViewModel.deleteSpot(spot) { _ in }
                }
            } message: { spot in
                Text("This will move \"\(spot.name)\" to Recently Deleted.")
            }
            .sheet(isPresented: $isShowingEditCollectionSheet) { EditCollectionView(collection: collection) }
            .sheet(isPresented: $isShowingManageSpotsSheet) { ManageSpotsInCollectionView(collection: collection) }
            .sheet(item: $itemToShare) { item in ShareSheet(items: [item.text, item.url]) }
            .confirmationDialog("Delete '\(collection.name)'?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
                deleteButtons(for: collection)
            }
        } else {
            ContentUnavailableView("Collection Not Found", systemImage: "questionmark.folder")
        }
    }
    
    // MARK: - Subviews
    
    private func headerView(for collection: SpotCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // This is the new, larger title
            Text(collection.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            // The description will now appear below the title
            if let description = collection.descriptionText, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
        }
        .padding(.top) // Give the whole header some vertical space
    }
    
    private func listView(for collection: SpotCollection) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(displayedSpots) { spot in
                    // NavigationLink now wraps the fully interactive SpotCardView
                    NavigationLink(destination: SpotDetailView(spotId: spot.id ?? "", presentedFrom: .list)) {
                        SpotCardView(
                            spot: spot,
                            userLocation: locationManager.userLocation,
                            onEdit: { editSpot(spot) },
                            onDelete: { requestDeleteConfirmation(for: spot) },
                            onShare: { Task { await handleShare(for: spot) } }
                            // Since we removed visit tracking, we don't need the other closures
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var mapView: some View {
        Map(position: $cameraPosition, selection: $selectedMapSpot) {
            UserAnnotation()
            
            ForEach(displayedSpots) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    SpotAnnotationView(spot: spot, isSelected: spot.id == selectedMapSpot?.id)
                        .onTapGesture {
                            // Tapping an annotation selects it
                            selectedMapSpot = spot
                        }
                }
                .tag(spot) // Tag is important for the `selection` binding to work
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { MapPitchToggle(); MapCompass() }
        .onAppear(perform: setInitialCameraPosition)
        // This resets the selection when the user switches away from the map tab
        .onChange(of: selectedTab) {
            if selectedTab != 1 {
                selectedMapSpot = nil
            }
        }
    }
    
    private func setInitialCameraPosition() {
        Task {
            if !displayedSpots.isEmpty {
                let coordinates = displayedSpots.map { $0.coordinate }
                
                // 1. Create a bounding box that contains all the spots
                let mapRect = MKMapRect(containing: coordinates)
                
                // 2. Convert that box into a map region
                var region = MKCoordinateRegion(mapRect)
                
                // 3. Add 40% padding so the pins aren't on the very edge of the screen
                region.span.latitudeDelta *= 1.4
                region.span.longitudeDelta *= 1.4
                
                // 4. Set the camera to this new, padded region
                withAnimation(.easeOut) {
                    cameraPosition = .region(region)
                }
            }
        }
    }

    
    // MARK: - Toolbar Items
    
    private var filterButton: some View {
        Button { isShowingFilterSheet = true } label: {
            let isFilterActive = !selectedCategoryFilters.isEmpty
            Label("Filter", systemImage: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .popover(isPresented: $isShowingFilterSheet) {
            FilterMenuView(
                collectionFilterState: .constant(.all), // We don't use this here, so pass a constant
                selectedCategoryFilters: $selectedCategoryFilters,
                showCollectionFilterOptions: false // Tell the menu to hide the collection options
            )
            .presentationCompactAdaptation(.popover) // Ensures it looks good on iPhone
        }
    }
    
    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $currentSortOrder) {
                ForEach(SortOrder.allCases) { order in Text(order.rawValue).tag(order) }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down.circle")
        }
    }
    
    private func moreMenu(for collection: SpotCollection) -> some View {
        Menu {
            // Note 3: Edit & Share moved here
            Button { isShowingEditCollectionSheet = true } label: { Label("Edit Details", systemImage: "pencil") }
            Button { Task { await handleShareCollection(for: collection) } } label: { Label("Share Collection", systemImage: "square.and.arrow.up") }
            Divider()
            // Note 4: Missing options added
            Button { isShowingManageSpotsSheet = true } label: { Label("Edit Spots in Collection", systemImage: "checklist") }
            Button(role: .destructive) { isShowingDeleteConfirmation = true } label: { Label("Delete Collection", systemImage: "trash") }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }
    
    /// The buttons for the delete confirmation dialog.
    @ViewBuilder
    private func deleteButtons(for collection: SpotCollection) -> some View {
        Button("Delete Collection & Spots", role: .destructive) {
            deleteCollection(collection, mode: .collectionAndSpots)
        }
        Button("Remove Collection Only", role: .destructive) {
            deleteCollection(collection, mode: .collectionOnly)
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Action Handlers
    private func editSpot(_ spot: Spot) {
            self.spotToEdit = spot
        }

    private func requestDeleteConfirmation(for spot: Spot) {
        self.spotToDelete = spot
        self.showingDeleteConfirmationForSpot = true
    }
    
    private func handleShare(for spot: Spot) async {
        guard let userId = authViewModel.userSession?.uid else { return }

        // You can add a @State var for a loading spinner here if desired

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
            print("SpotListView: Failed to create share link: \(error)")
            // Optionally, show an error alert here
        }
    }
    
    private func deleteCollection(_ collection: SpotCollection, mode: CollectionViewModel.DeletionMode) {
        collectionViewModel.deleteCollection(
            collection,
            mode: mode,
            allSpots: spotsViewModel.spots
        ) { result in
            if case .success = result {
                dismiss() // Go back to the gallery if deletion is successful
            }
            // You can handle the error case here, e.g., show an alert
        }
    }
    
    private func handleShareCollection(for collection: SpotCollection) async {
        let url = try? await SpotShareManager.makePublicCollectionShareURL(for: collection)
        if let url = url {
            let senderName = authViewModel.userSession?.displayName ?? "A friend"
            let text = "\(senderName) shared the '\(collection.name)' collection with you!"
            itemToShare = ShareableContent(text: text, url: url)
        }
    }
}

fileprivate extension MKMapRect {
    init(containing coordinates: [CLLocationCoordinate2D]) {
        self = coordinates.reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate)
            return rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
    }
}
