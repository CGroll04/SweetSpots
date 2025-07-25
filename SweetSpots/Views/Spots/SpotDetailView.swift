//
//  SpotDetailView.swift
//  SweetSpots
//
//  Enhanced version with proper state management and geofencing
//

import SwiftUI
import MapKit

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

// Helper struct for alerts within this view
fileprivate struct SpotDetailAlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SpotDetailView: View {
    // MARK: - Environment & State
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel // ADD THIS LINE
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var navigationViewModel: NavigationViewModel
    @AppStorage("globalGeofencingEnabled") private var globalGeofencingSystemEnabled: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    // ✅ The ID is the new "source of truth" for this view.
    let spotId: String

    // ✅ This computed property ALWAYS reads the LATEST data from the ViewModel.
    private var spot: Spot? {
        spotsViewModel.spots.first { $0.id == spotId }
    }
    
    // Local state for UI controls, initialized from the spot
    @State private var wantsNearbyNotification: Bool = false
    @State private var notificationRadius: Double = 200.0
    @State private var selectedRadiusPreset: AddSpotView.RadiusPreset = .medium
    @State private var showingCustomRadiusField: Bool = false
    
    // UI state
    @State private var isSavingChanges: Bool = false
    @State private var showSaveConfirmation: Bool = false
    @State private var alertInfo: SpotDetailAlertInfo? = nil
    @State private var selectedTransportType: TransportType = .driving

    // WebView State
    @StateObject private var webViewStore = WebViewStore()
    @State private var webViewIsLoading: Bool = false
    @State private var webViewError: Error? = nil
    
    // MARK: - Body
    var body: some View {
        // If the spot exists, we show our content.
        if let currentSpot = spot {
            contentView(for: currentSpot)
                .navigationTitle(currentSpot.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent(for: currentSpot) }
                .alert(item: $alertInfo) { info in
                    Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
                }
                .onAppear {
                    initializeLocalState(from: currentSpot)
                }
                .onChange(of: spot) { _, newSpotData in
                    if let newSpot = newSpotData {
                        initializeLocalState(from: newSpot)
                    }
                }
        } else {
            // If the spot is nil (e.g., deleted), show a fallback view.
            ContentUnavailableView("Spot Not Found", systemImage: "questionmark.circle", description: Text("This spot may have been deleted."))
                .navigationTitle("Not Found")
        }
    }
    
    private func initializeLocalState(from spot: Spot) {
        // Populates our @State vars from the live spot data.
        self.wantsNearbyNotification = spot.wantsNearbyNotification
        self.notificationRadius = spot.notificationRadiusMeters
        let initialPreset = AddSpotView.RadiusPreset.preset(for: spot.notificationRadiusMeters)
        self.selectedRadiusPreset = initialPreset
        self.showingCustomRadiusField = (initialPreset == .custom)
    }
        
        // MARK: - Main Content View
        private func contentView(for spot: Spot) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection(for: spot)
                    mapPreviewSection(for: spot)
                    if let sourceURLString = spot.sourceURL, let url = URL(string: sourceURLString) {
                        webPreviewSection(url: url)
                    }
                    informationSection(for: spot)
                    notificationSettingsSection(for: spot)
                    actionsSection(for: spot)
                    Spacer()
                }
                .padding()
            }
            .background(Color.themeBackground.ignoresSafeArea())
        }

        // MARK: - Computed Properties
        private func hasNotificationChanges(for spot: Spot) -> Bool {
            // Compare our local @State vars to the live `spot` data.
            if wantsNearbyNotification != spot.wantsNearbyNotification { return true }
            if wantsNearbyNotification && !notificationRadius.isApproximately(spot.notificationRadiusMeters, tolerance: 0.1) { return true }
            return false
        }
        
        // MARK: - Toolbar & Actions
        @ToolbarContentBuilder
        private func toolbarContent(for spot: Spot) -> some ToolbarContent {
            ToolbarItem(placement: .navigationBarTrailing) {
                if hasNotificationChanges(for: spot) {
                    Button("Save") {
                        saveNotificationSettings(for: spot)
                    }
                    .disabled(isSavingChanges)
                    .fontWeight(.semibold)
                } else if showSaveConfirmation {
                    Text("Saved!")
                        .font(.caption).foregroundStyle(Color.green)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showSaveConfirmation = false
                            }
                        }
                }
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
        let nearbySpots = spotsViewModel.spots.filter { otherSpot in
            guard otherSpot.id != spot.id else { return false }
            return CLLocation(latitude: spot.latitude, longitude: spot.longitude).distance(from: CLLocation(latitude: otherSpot.latitude, longitude: otherSpot.longitude)) <= 1000
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "play.tv.fill").font(.headline).foregroundStyle(Color.themePrimary)
                    .frame(width: 24, alignment: .center)
                Text("Original Post Preview").font(.headline).foregroundStyle(Color.themeTextPrimary)
            }
            .padding(.top, 8)
            ZStack {
                WebView(
                    webView: webViewStore.webView, // Pass the persistent webView from the store
                    request: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad),
                    isLoading: $webViewIsLoading,
                    loadingError: $webViewError
                )
                .frame(height: 350)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeFieldBorder.opacity(0.4), lineWidth: 1))
                
                if webViewIsLoading { ProgressView().scaleEffect(1.2).tint(Color.themePrimary) }
                else if let error = webViewError { webViewErrorContent(error: error, url: url) }
            }
        }
        .padding(.bottom, 5)
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
            DetailRow(iconName: "mappin.and.ellipse", title: "Address", content: spot.address)
            DetailRow(iconName: spot.category.systemImageName, title: "Category", content: spot.category.displayName, contentColor: Color.themePrimary)
            // ADDED: Display the collection if the spot belongs to one
            if let collectionId = spot.collectionId,
               let collection = collectionViewModel.collections.first(where: { $0.id == collectionId }) {
                DetailRow(iconName: "tray.fill", title: "Collection", content: collection.name, contentColor: Color.themePrimary)
            }
            
            // ADDED: Display the visit count
            DetailRow(iconName: "checkmark.circle.fill", title: "Times Visited", content: "\(spot.visitCount)")

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
                        .frame(maxWidth: .infinity, alignment: .leading) // Ensure text aligns left
                }
            }
        }
    }
    
    private func actionsSection(for spot: Spot) -> some View {
        VStack(spacing: 16) {
            // 3. UPDATE THE PICKER
            Picker("Transport Type", selection: $selectedTransportType) {
                ForEach(TransportType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
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
                    .onChange(of: wantsNearbyNotification) { _, isNowEnabled in
                        // If the user just toggled it ON...
                        if isNowEnabled {
                            // ...and we don't have the required permission...
                            if locationManager.authorizationStatus != .authorizedAlways {
                                print("SpotDetailView: Notification enabled, but 'Always' permission is missing. Requesting upgrade.")
                                locationManager.requestLocationAuthorization(aimForAlways: true)
                            }
                        }
                    }
                if wantsNearbyNotification && globalGeofencingSystemEnabled {
                    Picker("Notification Distance", selection: $selectedRadiusPreset) {
                        ForEach(AddSpotView.RadiusPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
                    }
                    .tint(Color.themePrimary).disabled(isSavingChanges)
                    .onChange(of: selectedRadiusPreset) { _, newPreset in
                        if let presetRadius = newPreset.radiusValue {
                            notificationRadius = presetRadius; showingCustomRadiusField = false
                        } else { showingCustomRadiusField = true }
                    }
                    if showingCustomRadiusField {
                        HStack {
                            Text("Custom (meters):")
                            Spacer()
                            TextField("e.g., 150", value: $notificationRadius, formatter: radiusNumberFormatter())
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(width: 100).textFieldStyle(.roundedBorder).disabled(isSavingChanges)
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
    
    // MARK: - Action Methods
    
    private func getDirections(for spot: Spot) {
        guard let userLocation = locationManager.userLocation else {
            locationManager.startUpdatingUserLocation()
            alertInfo = SpotDetailAlertInfo(title: "Finding Your Location", message: "Please wait a moment while we find your current location, then try again.")
            return
        }
        
        Task {
            await navigationViewModel.startNavigation(
                to: spot,
                from: userLocation,
                // 4. USE THE HELPER TO CONVERT BACK
                transportType: selectedTransportType.mkType
            )
            dismiss()
        }
    }
    
    private func saveNotificationSettings(for spot: Spot) {
        if wantsNearbyNotification && (notificationRadius < 50 || notificationRadius > 50000) {
            alertInfo = SpotDetailAlertInfo(title: "Invalid Radius", message: "Radius must be between 50 and 50,000 meters.")
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
                self.showSaveConfirmation = true
                self.locationManager.synchronizeGeofences(forSpots: self.spotsViewModel.spots, globallyEnabled: self.globalGeofencingSystemEnabled)
            case .failure(let error):
                self.alertInfo = SpotDetailAlertInfo(title: "Update Failed", message: "Could not save settings: \(error.localizedDescription)")
            }
        }
    }
    
    private func radiusNumberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.minimum = 50; formatter.maximum = 50000; formatter.maximumFractionDigits = 0; return formatter
    }
}

// MARK: - Reusable DetailRow View & Extensions (keeping existing implementation)
private struct DetailRow<Content: View>: View {
    let iconName: String
    let title: String
    let contentBody: Content
    
    init(iconName: String, title: String, @ViewBuilder content: () -> Content) {
        self.iconName = iconName
        self.title = title
        self.contentBody = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(Color.themePrimary)
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.themeTextPrimary)
            }
            HStack {
                Spacer().frame(width: 24 + 10)
                contentBody
                    .padding(.top, 2)
                Spacer()
            }
        }
        .padding(.vertical, 6)
    }
}

extension DetailRow where Content == Text {
    init(iconName: String, title: String, content: String, contentColor: Color = Color.themeTextSecondary) {
        self.iconName = iconName
        self.title = title
        self.contentBody = Text(content).font(.body).foregroundStyle(contentColor)
    }

    init(iconName: String, title: String, content: Date, style: Text.DateStyle, contentColor: Color = Color.themeTextSecondary) {
        self.iconName = iconName
        self.title = title
        self.contentBody = Text(content, style: style).font(.body).foregroundStyle(contentColor)
    }
}
