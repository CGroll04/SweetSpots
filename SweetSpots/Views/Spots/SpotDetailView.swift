//
//  SpotDetailView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-08.
//

import SwiftUI
import MapKit
import os.log

enum TransportType: String, CaseIterable, Hashable {
    case driving = "Driving"
    case walking = "Walking"

    // Helper to convert our simple enum to MapKit's type
    var mkType: MKDirectionsTransportType {
        switch self {
        case .driving:
            return .automobile
        case .walking:
            return .walking
        }
    }
}


enum PresentationContext {
    case list
    case map
}

struct SpotDetailAlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// A view that displays detailed information about a single spot, allowing for editing and other actions.
struct SpotDetailView: View {
    // MARK: - Environment & State
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var navigationViewModel: NavigationViewModel
    @AppStorage("globalGeofencingEnabled") private var globalGeofencingSystemEnabled: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SpotDetailView")
    
    let spotId: String
    let presentedFrom: PresentationContext

    private var spot: Spot? {
        // First, search in the active spots...
        if let activeSpot = spotsViewModel.spots.first(where: { $0.id == spotId }) {
            return activeSpot
        }
        // If not found, search in the recently deleted spots.
        if let deletedSpot = spotsViewModel.recentlyDeletedSpots.first(where: { $0.id == spotId }) {
            return deletedSpot
        }
        return nil
    }
    private var distanceUnit: String {
        // This checks if the user's region uses the metric system
        if Locale.current.measurementSystem == .metric {
            return "meters"
        } else {
            return "feet"
        }
    }
    
    // Local state for UI controls, initialized from the spot
    @State private var wantsNearbyNotification: Bool = false
    @State private var notificationRadius: Double = 200.0
    @State private var selectedRadiusPreset: SpotFormSectionView.RadiusPreset = .medium
    @State private var showingCustomRadiusField: Bool = false
    
    @State private var spotToEdit: Spot? = nil
    @State private var spotToDelete: Spot? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingWebSheet = false
    
    @State private var showingNavConflictAlert = false
    @State private var newNavigationTarget: Spot?
    
    @State private var itemToShare: ShareableContent? = nil
    
    // UI state
    @State private var isSavingChanges: Bool = false
    @State private var showSaveConfirmation: Bool = false
    @State private var alertInfo: SpotDetailAlertInfo? = nil

    // WebView State
    @StateObject private var webViewStore = WebViewStore()
    @State private var webViewIsLoading: Bool = false
    @State private var webViewError: Error? = nil
    
    // MARK: - Initialization
    init(spotId: String, presentedFrom: PresentationContext) {
        self.spotId = spotId
        self.presentedFrom = presentedFrom
    }
    
    // MARK: - Body
    var body: some View {
        if let currentSpot = spot {
            contentView(for: currentSpot)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent(for: currentSpot) }
                .alert(item: $alertInfo) { info in
                    Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
                }
                .onAppear {
                    logger.info("SpotDetailView appeared for spot: \(currentSpot.name) (ID: \(self.spotId))")
                    initializeLocalState(from: currentSpot)
                }
                .onChange(of: spotsViewModel.spots) { _, _ in
                    if let latest = spot { initializeLocalState(from: latest) }
                }
        } else {
            let _ = logger.warning("SpotDetailView loaded with an invalid or non-existent spotId: \(self.spotId)")
            ContentUnavailableView("Spot Not Found", systemImage: "questionmark.circle", description: Text("This spot may have been deleted."))
                .navigationTitle("Not Found")
        }
    }
    
    private func initializeLocalState(from spot: Spot) {
        self.wantsNearbyNotification = spot.wantsNearbyNotification
        self.notificationRadius = spot.notificationRadiusMeters
        let initialPreset = SpotFormSectionView.RadiusPreset.preset(for: spot.notificationRadiusMeters)
        self.selectedRadiusPreset = initialPreset
        self.showingCustomRadiusField = (initialPreset == .custom)
    }
        
    // MARK: - Main Content View
    private func contentView(for spot: Spot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                deletedStateBanner(for: spot)
                headerSection(for: spot)
                mapPreviewSection(for: spot)
                if let sourceURLString = spot.sourceURL, let url = URL(string: sourceURLString) {
                    webPreviewSection(url: url)
                }
                informationSection(for: spot)
                if spot.deletedAt == nil {
                    notificationSettingsSection(for: spot)
                    actionsSection(for: spot)
                }
                Spacer()
            }
            .padding()
        }
        .background(Color.themeBackground.ignoresSafeArea())
        .sheet(item: $spotToEdit) { spot in
            AddSpotView(
                isPresented: Binding(
                    get: { self.spotToEdit != nil },
                    set: { if !$0 { self.spotToEdit = nil } }
                ),
                spotToEdit: spot,
                prefilledPayload: nil,
                prefilledURL: nil
            )
        }
        .alert(
            "Delete SweetSpot",
            isPresented: $showingDeleteConfirmation,
            presenting: spotToDelete
        ) { spot in
            Button("Delete", role: .destructive) {
                spotsViewModel.deleteSpot(spot, isPermanent: false) { _ in
                    self.dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { spot in
            Text("This will move \"\(spot.name)\" to the Recently Deleted section, where it will be permanently deleted after 30 days.")
        }
        .sheet(item: $itemToShare) { item in
            ShareSheet(items: [item.text, item.url])
        }
        .alert("Start New Route?", isPresented: $showingNavConflictAlert, presenting: newNavigationTarget) { spot in
            Button("Switch Destination", role: .destructive) {
                // Stop the old navigation and start the new one
                navigationViewModel.stopNavigation()
                // We re-call getDirections, which will now succeed
                getDirections(for: spot)
            }
            Button("Cancel", role: .cancel) {}
        } message: { spot in
            Text("You are already navigating. Do you want to end your current route and start a new one to \"\(spot.name)\"?")
        }
    }
    
    // MARK: - Toolbar & Actions
    @ToolbarContentBuilder
    private func toolbarContent(for spot: Spot) -> some ToolbarContent {
        if spot.deletedAt != nil {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }.tint(Color.themeAccent)
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            HStack(spacing: 8) { // Use an HStack for consistent spacing
                // The Share Button
                Button {
                    Task { await handleShare(for: spot) }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .padding(.leading, 3)

                // The More menu
                if spot.deletedAt == nil {
                    Menu {
                        Button { self.spotToEdit = spot } label: {
                            Label("Edit Spot", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            self.spotToDelete = spot
                            self.showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Spot", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .buttonStyle(.plain) // Removes unwanted background styles from buttons within
        }
    }
    
    private func handleShare(for spot: Spot) async {
        guard let spotId = spot.id else { return }

        do {
            // This now calls the new function to generate a temporary, private link
            let url = try await SpotShareManager.makePrivateShareURL(for: .spot(id: spotId))

            let senderName = authViewModel.userSession?.displayName
            let text = senderName != nil ? "\(senderName!) shared '\(spot.name)' with you!" : "Check out '\(spot.name)' on SweetSpots!"
            itemToShare = ShareableContent(text: text, url: url)
            logger.info("Successfully created private share link for spot: \(spot.name)")
            
        } catch {
            logger.error("Failed to create share link for spot '\(spot.name)': \(error.localizedDescription)")
            alertInfo = SpotDetailAlertInfo(title: "Share Error", message: "Could not create a share link. Please try again.")
        }
    }
    
    // MARK: - View Sections
    
    private func headerSection(for spot: Spot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: spot.category.systemImageName)
                .font(.title2).foregroundStyle(Color.white)
                .frame(width: 50, height: 50)
                .background(Color.themePrimary).clipShape(Circle())
            Text(spot.name)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.themeTextPrimary)
                .lineLimit(3).minimumScaleFactor(0.75)
        }
        .padding(.top, 5)
    }

    private func mapPreviewSection(for spot: Spot) -> some View {
        let previewRegion = MKCoordinateRegion(center: spot.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        
        var nearbySpots: [Spot] = []
        if spot.deletedAt == nil {
            nearbySpots = spotsViewModel.spots.filter { otherSpot in
                guard otherSpot.id != spot.id else { return false }
                return CLLocation(latitude: spot.latitude, longitude: spot.longitude).distance(from: CLLocation(latitude: otherSpot.latitude, longitude: otherSpot.longitude)) <= 1000
            }
        }
        
        return Map(initialPosition: .region(previewRegion), interactionModes: [.pan, .zoom]) {
            Annotation(spot.name, coordinate: spot.coordinate) { SpotAnnotationView(spot: spot, isSelected: true).zIndex(1) }
                .tag(spot.id ?? "")
            ForEach(nearbySpots) { nearbySpot in
                Annotation(nearbySpot.name, coordinate: nearbySpot.coordinate) { SpotAnnotationView(spot: nearbySpot, isSelected: false).opacity(0.75) }
                    .tag(nearbySpot.id ?? "")
            }
        }
        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.themeFieldBorder.opacity(0.5), lineWidth: 1))
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
    }
    
    private func webPreviewSection(url: URL) -> some View {
        // Check if the URL is from a known problematic source like TikTok
        let host = url.host?.lowercased() ?? ""
        let isProblematicSource = host.contains("tiktok.com") || host.contains("youtube.com")
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "safari.fill").font(.headline).foregroundStyle(Color.themePrimary)
                    .frame(width: 24, alignment: .center)
                Text("Original Post Preview").font(.headline).foregroundStyle(Color.themeTextPrimary)
            }
            .padding(.top, 8)
            
            if isProblematicSource {
                // Show a button instead of the broken WebView
                Button(action: {
                    showingWebSheet = true
                }) {
                    HStack {
                        Text("Tap to view post")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Material.thin)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeFieldBorder.opacity(0.4), lineWidth: 1))
                }
            } else {
                // For other sites like Instagram, the existing WebView still works
                ZStack {
                    WebView(
                        webView: webViewStore.webView,
                        request: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad),
                        isLoading: $webViewIsLoading,
                        loadingError: $webViewError
                    )
                    .frame(height: 650)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeFieldBorder.opacity(0.4), lineWidth: 1))
                    
                    if webViewIsLoading { ProgressView().scaleEffect(1.2).tint(Color.themePrimary) }
                    else if let error = webViewError { webViewErrorContent(error: error, url: url) }
                }
            }
        }
        .padding(.bottom, 5)
        // Add this sheet modifier to present the SafariView
        .sheet(isPresented: $showingWebSheet) {
            SafariView(url: url)
        }
    }
    
    private func webViewErrorContent(error: Error, url: URL) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.title).foregroundColor(.red)
            Text("Preview Error").font(.headline)
            Text(error.localizedDescription).font(.caption).multilineTextAlignment(.center).padding(.horizontal)
            Button("Open in Browser") { UIApplication.shared.open(url) }
                .buttonStyle(.bordered).tint(Color.themeAccent).padding(.top, 5)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Material.thin)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func informationSection(for spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let sender = spot.senderName {
                DetailRow(iconName: "square.and.arrow.down.fill", title: "Imported From", content: sender)
            }
            DetailRow(iconName: "mappin.and.ellipse", title: "Address", content: spot.address)
            DetailRow(iconName: spot.category.systemImageName, title: "Category", content: spot.category.displayName, contentColor: Color.themePrimary)
            if !spot.collectionIds.isEmpty {
                let collections = collectionViewModel.collections.filter { spot.collectionIds.contains($0.id ?? "") }
                DetailRow(iconName: "tray.fill", title: "Collections") {
                    Text(collections.map { $0.name }.joined(separator: ", "))
                        .foregroundStyle(Color.themePrimary)
                }
            }
            
            if let phone = spot.phoneNumber, !phone.isEmpty {
                DetailRow(iconName: "phone.fill", title: "Phone") {
                    if let telURL = URL(string: "tel:\(phone.filter("0123456789+".contains))") {
                        Link(phone, destination: telURL).foregroundStyle(.blue)
                    } else { Text(phone).foregroundStyle(.secondary) }
                }
            }
            if let website = spot.websiteURL, let webURL = URL(string: website) {
                DetailRow(iconName: "safari.fill", title: "Website") {
                    Link(destination: webURL) { Text(webURL.host?.replacingOccurrences(of: "www.", with: "") ?? website).lineLimit(1).truncationMode(.middle) }
                        .foregroundStyle(.blue)
                }
            }
            if let source = spot.sourceURL, let sourceURL = URL(string: source), source != spot.websiteURL {
                DetailRow(iconName: "arrow.up.forward.app", title: "Original Source") {
                    Link(destination: sourceURL) { Text(sourceURL.host?.replacingOccurrences(of: "www.", with: "") ?? "View Source").lineLimit(1).truncationMode(.middle) }
                        .foregroundStyle(.blue)
                }
            }
            DetailRow(iconName: "calendar", title: "Date Added", content: spot.createdAt?.dateValue() ?? Date(), style: .date)
            
            if let notes = spot.notes, !notes.isEmpty {
                DetailRow(iconName: "note.text", title: "Notes") {
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(Color.themeTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    private func actionsSection(for spot: Spot) -> some View {
        VStack(spacing: 16) {
            Button(action: { getDirections(for: spot) }) {
                Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .fontWeight(.medium).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Color.themePrimary).controlSize(.large)
        }
        .padding(.top)
    }
    
    @ViewBuilder
    private func notificationSettingsSection(for spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Proximity Alert").font(.headline).foregroundStyle(Color.themeTextPrimary).padding(.bottom, 5)
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Notify me when nearby", isOn: $wantsNearbyNotification)
                    .tint(Color.themePrimary)
                    .disabled(!globalGeofencingSystemEnabled || isSavingChanges)
                    .onChange(of: wantsNearbyNotification) {
                        // This now saves automatically
                        saveNotificationSettings(for: spot)
                        
                        // The permission check logic remains
                        if wantsNearbyNotification {
                            if locationManager.authorizationStatus != .authorizedAlways {
                                locationManager.requestLocationAuthorization(aimForAlways: true)
                            }
                        }
                    }
                if wantsNearbyNotification && globalGeofencingSystemEnabled {
                    Picker("Notification Distance", selection: $selectedRadiusPreset) {
                        ForEach(SpotFormSectionView.RadiusPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
                    }
                    .tint(Color.themePrimary).disabled(isSavingChanges)
                    .onChange(of: selectedRadiusPreset) { _, newPreset in
                        if let presetRadius = newPreset.radiusValue {
                            notificationRadius = presetRadius; showingCustomRadiusField = false
                        } else { showingCustomRadiusField = true }
                        saveNotificationSettings(for: spot)
                    }
                    if showingCustomRadiusField {
                        HStack {
                            Text("Custom (\(distanceUnit)):")
                            Spacer()
                            TextField("e.g., 650", value: $notificationRadius, formatter: NumberFormatters.distance)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(width: 100).textFieldStyle(.roundedBorder).disabled(isSavingChanges)
                                .onChange(of: notificationRadius) {
                                    // Save when the custom radius changes
                                    saveNotificationSettings(for: spot)
                                }
                        }
                    }
                    Text(globalGeofencingSystemEnabled ? "Min: 50m, Max: 50,000m." : "Enable global proximity alerts in Settings first.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if !globalGeofencingSystemEnabled && wantsNearbyNotification {
                    Text("Global proximity alerts are disabled in Settings. This spot's alert won't be active.").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.leading, 34) // Indent content to align with DetailRow content
        }
    }
    
    @ViewBuilder
    private func deletedStateBanner(for spot: Spot) -> some View {
        if spot.deletedAt != nil {
            VStack(spacing: 8) {
                Text("This spot is in Recently Deleted.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Button {
                        spotsViewModel.restoreSpot(spot)
                        dismiss()
                    } label: {
                        Label("Restore Spot", systemImage: "arrow.uturn.backward.circle.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    
                    Button(role: .destructive) {
                        spotsViewModel.permanentlyDeleteSpot(spot)
                        dismiss()
                    } label: {
                        Label("Delete Permanently", systemImage: "trash.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.yellow.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.yellow.opacity(0.5), lineWidth: 1)
            }
        }
    }
    
    // MARK: - Action Methods

    private func getDirections(for spot: Spot) {
        // 1. Check if navigation is already active
        if navigationViewModel.isNavigating {
            // If yes, store the new spot and trigger the alert
            self.newNavigationTarget = spot
            self.showingNavConflictAlert = true
            return
        }
        
        // 2. If not navigating, proceed as normal
        guard let userLocation = locationManager.userLocation else {
            logger.info("User requested directions but location is unavailable.")
            locationManager.startUpdatingUserLocation()
            alertInfo = SpotDetailAlertInfo(title: "Finding Your Location", message: "Please wait a moment while we find your current location, then try again.")
            return
        }
        
        if presentedFrom == .map {
            dismiss()
        }
        
        Task {
            await navigationViewModel.setNavigationTarget(spot: spot, from: userLocation)
        }
    }
    
    private func saveNotificationSettings(for spot: Spot) {
        if wantsNearbyNotification && (notificationRadius < 50 || notificationRadius > 50000) {
            // Use a formatter to create a localized message
            let formatter = MeasurementFormatter()
            formatter.unitOptions = .providedUnit
            formatter.numberFormatter.maximumFractionDigits = 0

            let minDistance = Measurement(value: 50, unit: UnitLength.meters)
            let maxDistance = Measurement(value: 50000, unit: UnitLength.meters)

            let message = "Radius must be between \(formatter.string(from: minDistance)) and \(formatter.string(from: maxDistance))."
            
            alertInfo = SpotDetailAlertInfo(title: "Invalid Radius", message: message)
            return
        }
        isSavingChanges = true
        var updatedSpot = spot
        updatedSpot.wantsNearbyNotification = self.wantsNearbyNotification
        updatedSpot.notificationRadiusMeters = self.notificationRadius
        
        spotsViewModel.updateSpot(updatedSpot) { result in
            self.isSavingChanges = false
            switch result {
            case .success:
                self.logger.info("Successfully saved notification settings for spot '\(spot.name)'.")
                self.showSaveConfirmation = true
                self.locationManager.synchronizeGeofences(forSpots: self.spotsViewModel.spots, globallyEnabled: self.globalGeofencingSystemEnabled)
            case .failure(let error):
                self.logger.error("Failed to save notification settings for spot '\(spot.name)': \(error.localizedDescription)")
                self.alertInfo = SpotDetailAlertInfo(title: "Update Failed", message: "Could not save settings: \(error.localizedDescription)")
            }
        }
    }
}
