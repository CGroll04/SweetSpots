//
//  SettingsView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI
import SafariServices
import os.log

/// A view that provides app settings, account management, and other administrative actions.
struct SettingsView: View {
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SettingsView")
    
    let onDismiss: () -> Void

    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @EnvironmentObject private var navigationViewModel: NavigationViewModel

    // State for alerts
    @State private var showingSignOutAlert = false
    @State private var alertInfo: AlertInfo? = nil
    @State private var showingBulkAlertConfirmation: BulkAlertActionType? = nil
    @State private var isProcessingBulkUpdate: Bool = false
    @State private var showingPermissionAlert = false
    
    @State private var showingDeleteAlert = false
    
    @State private var isTrashExpanded: Bool = false
    @State private var spotToShowDetails: Spot? = nil
    
    private let privacyURL = URL(string: "https://thesweetspotsapp.com/SweetSpots_Privacy_Policy.pdf")!
    private let termsURL   = URL(string: "https://thesweetspotsapp.com/SweetSpots_Terms_and_Conditions.pdf")!

    @AppStorage("globalGeofencingEnabled") private var globalGeofencingSystemEnabled: Bool = true
    
    // For confirming bulk actions
    enum BulkAlertActionType: Identifiable {
        case enableAll, disableAll
        var id: String { self == .enableAll ? "enableAll" : "disableAll" }
        var alertTitle: String { self == .enableAll ? "Enable for All Spots?" : "Disable for All Spots?" }
        var alertMessage: String { self == .enableAll ? "This will turn on proximity alerts for all your saved spots." : "This will turn off proximity alerts for all your saved spots." }
        var confirmButtonText: String { self == .enableAll ? "Enable All" : "Disable All" }
    }

    // Helper struct for alerts
    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            Form {
                userProfileSection()
                notificationsAndLocationSection()
                aboutSection()
                supportSection()
                recentlyDeletedSection()
                accountActionsSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .alert(item: $alertInfo) { info in
                Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) { performSignOut() }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Permanently Delete Account?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        await performAccountDeletion()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All of your spots and collections will be permanently removed. This action is irreversible. Are you sure you want to continue?")
            }
            .alert(item: $showingBulkAlertConfirmation) { actionType in
                Alert(
                    title: Text(actionType.alertTitle),
                    message: Text(actionType.alertMessage),
                    primaryButton: .default(Text(actionType.confirmButtonText)) {
                        self.performBulkSpotNotificationUpdate(enable: actionType == .enableAll)
                    },
                    secondaryButton: .cancel()
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }.tint(Color.themeAccent)
                }
            }
            .sheet(item: $spotToShowDetails) { spot in
                // This sheet for viewing deleted spot details remains useful
                SpotDetailView(spotId: spot.id ?? "", presentedFrom: .list)
            }
            .overlay {
                if isProcessingBulkUpdate {
                    ProcessingOverlayView(message: "Updating spots...")
                }
            }
        }
    }

    // MARK: - View Sections
    @ViewBuilder
    private func userProfileSection() -> some View {
        Section(header: Text("My Profile")) {
            if let user = authViewModel.userSession {
                LabeledContent("Username", value: user.displayName ?? "Not Set")
                LabeledContent("Email", value: user.email ?? "N/A")

                NavigationLink("Change Password") {
                    ChangePasswordView()
                }
                .foregroundStyle(Color.accentColor)
            } else {
                Text("Not logged in").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func notificationsAndLocationSection() -> some View {
        Section(header: Text("Proximity Alerts System")) {
            Toggle("Enable Nearby Spot Notifications", isOn: self.$globalGeofencingSystemEnabled)
                .tint(Color.themePrimary)
                .onChange(of: self.globalGeofencingSystemEnabled) { oldValue, newValue in
                    self.handleGlobalSystemGeofencingToggleChange(isEnabled: newValue)
                }
            
            Text("This master switch enables or disables all proximity alerts. Individual spot alert settings are respected when this is on.")
                .font(.caption).foregroundStyle(.secondary)

            currentPermissionStatusView()

            if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
                Button("Manage App Permissions in Settings") {
                    UIApplication.shared.open(appSettingsURL)
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }
    
    @ViewBuilder
    private func supportSection() -> some View {
        Section(header: Text("Support")) {
            Button(action: openEmail) {
                Label("Contact Us & Feedback", systemImage: "envelope.fill")
            }
            .foregroundStyle(Color.accentColor) // Matches the style of your other links
        }
    }

    @ViewBuilder
    private func currentPermissionStatusView() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // This logic now checks the status to decide if it should be a button
            if locationManager.authorizationStatus == .authorizedWhenInUse {
                Button(action: {
                    showingPermissionAlert = true
                }) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(locationPermissionColor)
                        Text("Location: \(locationPermissionText)")
                            .font(.caption)
                            .foregroundColor(locationPermissionColor)
                    }
                }
            } else {
                // For all other statuses, it remains plain text
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(locationPermissionColor)
                    Text("Location: \(locationPermissionText)")
                        .font(.caption)
                        .foregroundColor(locationPermissionColor)
                }
            }
            
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(notificationPermissionColor)
                Text("Notifications: \(notificationPermissionText)")
                    .font(.caption)
                    .foregroundColor(notificationPermissionColor)
            }
        }
        .padding(.vertical, 4)
        .alert("Proximity Alerts Disabled", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To get notifications when you're near a spot, SweetSpots needs 'Always' location access. Your location data is never stored or shared.")
        }
    }
    
    private func openEmail() {
        let supportEmail = "getsweetspots@gmail.com"
        let subject = "SweetSpots App Feedback v\(currentAppVersion())"
        
        // Add helpful info for the user to fill out
        let body = """
        
        
        -------------------
        App Version: \(currentAppVersion())
        iOS Version: \(UIDevice.current.systemVersion)
        Device Model: \(UIDevice.current.model)
        """
        
        // Create the mailto URL
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
    
    private var locationPermissionText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Always (Required)"
        case .authorizedWhenInUse: return "When In Use (Upgrade Needed)"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }
    
    private var locationPermissionColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return .green
        case .authorizedWhenInUse: return .orange
        case .denied, .restricted: return .red
        case .notDetermined: return .blue
        @unknown default: return .gray
        }
    }
    
    
    private var notificationPermissionText: String {
        switch locationManager.notificationStatus {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not Set"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private var notificationPermissionColor: Color {
        switch locationManager.notificationStatus {
        case .authorized: return .green
        case .denied: return .red
        case .notDetermined: return .blue
        default: return .gray
        }
    }
    
    /// Section for viewing and managing recently deleted spots.
    @ViewBuilder
    private func recentlyDeletedSection() -> some View {
        if !spotsViewModel.recentlyDeletedSpots.isEmpty {
            Section(header: Text("Recently Deleted")) {
                DisclosureGroup(isExpanded: $isTrashExpanded) {
                    ForEach(spotsViewModel.recentlyDeletedSpots) { spot in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(spot.name)
                                    .foregroundStyle(.primary)
                                
                                if let days = daysRemaining(for: spot) {
                                    Text("Permanently deleted in \(days) day\(days == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                spotToShowDetails = spot
                            }
                            
                            Spacer(minLength: 8)
                            
                            Menu {
                                Button {
                                    spotsViewModel.restoreSpot(spot)
                                } label: {
                                    Label("Restore Spot", systemImage: "arrow.uturn.backward.circle.fill")
                                }
                                
                                Button(role: .destructive) {
                                    spotsViewModel.permanentlyDeleteSpot(spot)
                                } label: {
                                    Label("Delete Permanently", systemImage: "trash.fill")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.body)
                            }
                            .tint(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                } label: {
                    // This is the main row for the disclosure group
                    HStack {
                         Image(systemName: "trash")
                             .font(.callout)
                             .frame(width: 20, alignment: .center)
                             .foregroundStyle(.secondary)

                         Text("Trash")
                             .foregroundStyle(.primary)
                         
                         Spacer()
                         
                         Text("\(spotsViewModel.recentlyDeletedSpots.count)")
                             .font(.caption.weight(.medium))
                             .padding(.horizontal, 8)
                             .padding(.vertical, 4)
                             .background(Color.secondary.opacity(0.1))
                             .clipShape(Capsule())
                    }
                }
            }
        }
    }
    
    private func daysRemaining(for spot: Spot) -> Int? {
        guard let deletedDate = spot.deletedAt?.dateValue() else { return nil }
        let calendar = Calendar.current
        let expirationDate = calendar.date(byAdding: .day, value: 30, to: deletedDate) ?? deletedDate
        let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
        return max(0, components.day ?? 0)
    }

    @ViewBuilder
    private func aboutSection() -> some View {
        Section(header: Text("About")) {
            LabeledContent("App Version", value: currentAppVersion())
            
            Button("Privacy Policy") {
                UIApplication.shared.open(privacyURL)
            }
            .foregroundStyle(Color.accentColor)

            Button("Terms & Conditions") {
                UIApplication.shared.open(termsURL)
            }
            .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func accountActionsSection() -> some View {
        Section {
            Button("Sign Out", role: .destructive, action: { showingSignOutAlert = true })
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.accentColor) // Make sign out blue to distinguish from delete
            
            Button("Delete Account", role: .destructive, action: {
                showingDeleteAlert = true
            })
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private func performAccountDeletion() async {
            isProcessingBulkUpdate = true // Reuse this for a loading spinner
            await authViewModel.deleteAccount()
            isProcessingBulkUpdate = false
            
            // If an error occurred (like needing a recent sign-in), show it
            if let error = authViewModel.errorMessage {
                self.alertInfo = AlertInfo(title: "Deletion Failed", message: error)
            }
            // On success, the user will be logged out automatically, dismissing this view.
        }

    // MARK: - Helper Functions & Actions
    /// Signs the user out and clears all local data and listeners.
    private func performSignOut() {
        logger.info("User initiated sign out.")
        locationManager.stopAllGeofences()
        spotsViewModel.stopListeningAndClearData()
        collectionViewModel.detachCollectionsListener()
        authViewModel.signOut()
    }
    
    private func currentAppVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "N/A"
        return "\(version) (\(build))"
    }

    private func handleGlobalSystemGeofencingToggleChange(isEnabled: Bool) {
        if isEnabled {
            // When the user toggles ON, we kick off the permission check.
            Task {
                let permissionsGranted = await checkAndRequestCorePermissions()
                
                // If permissions were not successfully granted, revert the toggle.
                guard permissionsGranted else {
                    // The `checkAndRequestCorePermissions` function will have already
                    // prompted the user or shown an alert. We just need to flip the switch back.
                    self.globalGeofencingSystemEnabled = false
                    return
                }
                
                // If we get here, all permissions are good. Sync the geofences.
                logger.info("All necessary permissions granted. Enabling global geofencing and synchronizing.")
                self.locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: true)
            }
        } else {
            // If the user toggles OFF, just disable all geofences.
            logger.info("Global geofencing toggle turned OFF. Disabling all geofences.")
            self.locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: false)
        }
    }
    
    private func checkAndRequestCorePermissions() async -> Bool {
        // 1. Check for 'Always' Location permission.
        if locationManager.authorizationStatus != .authorizedAlways {
            logger.info("'Always' location permission is required. Requesting...")
            locationManager.requestLocationAuthorization(aimForAlways: true)
            
            // Give the system a moment and re-check.
            // This is a simple way to wait for the user's response to the popup.
            try? await Task.sleep(for: .seconds(1))
            
            // If we still don't have it, fail.
            guard locationManager.authorizationStatus == .authorizedAlways else {
                logger.warning("Failed to obtain 'Always' location permission.")
                // The LocationManager will have shown the "Go to Settings" alert if needed.
                return false
            }
        }
        
        // 2. Check for Notification permission.
        let notificationsGranted = await locationManager.requestNotificationPermissionAsync()
        if !notificationsGranted {
            logger.info("Notification permission is required but was not granted.")
            // Show an alert to the user explaining why it's needed.
            self.alertInfo = AlertInfo(
                title: "Notifications Required",
                message: "To receive alerts for nearby spots, please enable notifications for SweetSpots in your iPhone's Settings."
            )
            return false
        }
        
        // 3. If we've passed both checks, we're good to go.
        return true
    }

    private func performBulkSpotNotificationUpdate(enable: Bool) {
        guard self.authViewModel.userSession != nil else { return }
        
        let spotsToModify = self.spotsViewModel.spots.filter { $0.wantsNearbyNotification != enable }
        
        if spotsToModify.isEmpty {
            self.alertInfo = AlertInfo(title: "No Changes Needed", message: "All spots already have this alert preference.")
            return
        }
        
        logger.info("User initiated bulk update to \(enable ? "enable" : "disable") notifications for \(spotsToModify.count) spots.")
        
        self.isProcessingBulkUpdate = true
        
        Task {
            var successCount = 0
            var failureCount = 0
            
            await withTaskGroup(of: Bool.self) { group in
                for var spot in spotsToModify {
                    spot.wantsNearbyNotification = enable
                    group.addTask { @MainActor in
                        await withCheckedContinuation { continuation in
                            self.spotsViewModel.updateSpot(spot) { result in
                                // Check the case of the Result instead of using a non-existent property
                                switch result {
                                case .success:
                                    continuation.resume(returning: true)
                                case .failure(let error):
                                    self.logger.error("Bulk update failed for spot \(spot.id ?? "N/A"): \(error.localizedDescription)")
                                    continuation.resume(returning: false)
                                }
                                // ---------------------
                            }
                        }
                    }
                }
                
                for await success in group {
                    if success {
                        successCount += 1
                    } else {
                        failureCount += 1
                    }
                }
            }
            
            await MainActor.run {
                self.isProcessingBulkUpdate = false
                
                if failureCount > 0 {
                    logger.warning("Bulk update finished with \(failureCount) failures and \(successCount) successes.")
                    alertInfo = AlertInfo(
                        title: "Partial Update",
                        message: "Updated \(successCount) spots successfully. \(failureCount) spots failed to update. Please try again."
                    )
                } else {
                    logger.info("Bulk update finished successfully for \(successCount) spots.")
                    alertInfo = AlertInfo(
                        title: "Success",
                        message: "Alert preferences updated for \(successCount) spots."
                    )
                }
                
                // Re-synchronize geofences after updates
                self.locationManager.synchronizeGeofences(
                    forSpots: self.spotsViewModel.spots,
                    globallyEnabled: self.globalGeofencingSystemEnabled
                )
            }
        }
    }
}

// Simple overlay for processing state
struct ProcessingOverlayView: View {
   let message: String
   var body: some View {
       ZStack {
           Color.black.opacity(0.1).ignoresSafeArea()
           VStack {
               ProgressView()
               Text(message).font(.caption).padding(.top, 8)
           }
           .padding(20)
           .background(.regularMaterial)
           .clipShape(RoundedRectangle(cornerRadius: 12))
           .shadow(radius: 10)
       }
   }
}
