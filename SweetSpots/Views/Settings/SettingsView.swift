//
//  SettingsView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var collectionViewModel: CollectionViewModel

    // State for alerts
    @State private var showingSignOutAlert = false
    @State private var alertInfo: AlertInfo? = nil
    @State private var showingBulkAlertConfirmation: BulkAlertActionType? = nil
    @State private var isProcessingBulkUpdate: Bool = false

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
                bulkSpotAlertsSection()
                aboutSection()
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

            // ✅ IMPROVEMENT: Show current permission status
            currentPermissionStatusView()

            if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
                Button("Manage App Permissions in Settings") {
                    UIApplication.shared.open(appSettingsURL)
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    // ✅ NEW: Show current permission status
    @ViewBuilder
    private func currentPermissionStatusView() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(locationPermissionColor)
                Text("Location: \(locationPermissionText)")
                    .font(.caption)
                    .foregroundColor(locationPermissionColor)
            }
            
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(.secondary)
                Text("Notifications: Check in Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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

    @ViewBuilder
    private func aboutSection() -> some View {
        Section(header: Text("About")) {
            LabeledContent("App Version", value: currentAppVersion())
            // ✅ IMPROVEMENT: Add debug info for development
            #if DEBUG
            LabeledContent("Active Geofences", value: "\(locationManager.activeGeofenceIDs.count)")
            LabeledContent("Total Spots", value: "\(spotsViewModel.spots.count)")
            LabeledContent("Spots with Alerts", value: "\(spotsViewModel.spots.filter { $0.wantsNearbyNotification }.count)")
            #endif
        }
    }

    @ViewBuilder
    private func accountActionsSection() -> some View {
        Section {
            Button("Sign Out", role: .destructive, action: { showingSignOutAlert = true })
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    @ViewBuilder
    private func bulkSpotAlertsSection() -> some View {
        Section(header: Text("Individual Spot Alerts")) {
            // ✅ IMPROVEMENT: Show current status
            let spotsWithAlerts = spotsViewModel.spots.filter { $0.wantsNearbyNotification }.count
            let totalSpots = spotsViewModel.spots.count
            
            if totalSpots > 0 {
                Text("\(spotsWithAlerts) of \(totalSpots) spots have alerts enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button("Enable Alerts for All Spots") {
                guard self.globalGeofencingSystemEnabled else {
                    alertInfo = AlertInfo(title: "System Disabled", message: "Please enable the 'Proximity Alerts System' toggle first to manage individual spot alerts.")
                    return
                }
                guard totalSpots > 0 else {
                    alertInfo = AlertInfo(title: "No Spots", message: "You don't have any spots yet. Add some spots first!")
                    return
                }
                showingBulkAlertConfirmation = .enableAll
            }
            .disabled(isProcessingBulkUpdate || totalSpots == 0)
            .tint(Color.accentColor)
            
            Button("Disable Alerts for All Spots", role: .destructive) {
                guard self.globalGeofencingSystemEnabled else {
                    alertInfo = AlertInfo(title: "System Disabled", message: "Please enable the 'Proximity Alerts System' toggle first.")
                    return
                }
                guard totalSpots > 0 else {
                    alertInfo = AlertInfo(title: "No Spots", message: "You don't have any spots yet.")
                    return
                }
                showingBulkAlertConfirmation = .disableAll
            }
            .disabled(isProcessingBulkUpdate || totalSpots == 0)
        }
    }

    // MARK: - Helper Functions & Actions
    private func performSignOut() {
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
                print("SettingsView: All necessary permissions granted. Enabling global geofencing and synchronizing.")
                self.locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: true)
            }
        } else {
            // If the user toggles OFF, just disable all geofences.
            print("SettingsView: Global geofencing toggle turned OFF. Disabling all geofences.")
            self.locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: false)
        }
    }
    
    private func checkAndRequestCorePermissions() async -> Bool {
        // 1. Check for 'Always' Location permission.
        if locationManager.authorizationStatus != .authorizedAlways {
            print("SettingsView: 'Always' location permission is required. Requesting...")
            locationManager.requestLocationAuthorization(aimForAlways: true)
            
            // Give the system a moment and re-check.
            // This is a simple way to wait for the user's response to the popup.
            try? await Task.sleep(for: .seconds(1))
            
            // If we still don't have it, fail.
            guard locationManager.authorizationStatus == .authorizedAlways else {
                print("SettingsView: Failed to obtain 'Always' location permission.")
                // The LocationManager will have shown the "Go to Settings" alert if needed.
                return false
            }
        }
        
        // 2. Check for Notification permission.
        let notificationsGranted = await locationManager.requestNotificationPermissionAsync()
        if !notificationsGranted {
            print("SettingsView: Notification permission is required but was not granted.")
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

    // ✅ IMPROVED: Better bulk update with proper async handling
    private func performBulkSpotNotificationUpdate(enable: Bool) {
        guard self.authViewModel.userSession != nil else { return }
        
        let spotsToModify = self.spotsViewModel.spots.filter { $0.wantsNearbyNotification != enable }
        
        if spotsToModify.isEmpty {
            self.alertInfo = AlertInfo(title: "No Changes Needed", message: "All spots already have this alert preference.")
            return
        }
        
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
                                case .failure:
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
                    alertInfo = AlertInfo(
                        title: "Partial Update",
                        message: "Updated \(successCount) spots successfully. \(failureCount) spots failed to update. Please try again."
                    )
                } else {
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

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let authVM = AuthViewModel()
        let spotVM = SpotViewModel()
        let locationManager = LocationManager()
        let collectionVM = CollectionViewModel()

        return SettingsView()
            .environmentObject(authVM)
            .environmentObject(spotVM)
            .environmentObject(locationManager)
            .environmentObject(collectionVM)
    }
}
