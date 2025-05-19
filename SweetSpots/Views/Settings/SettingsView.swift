//
//  SettingsView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var spotsViewModel: SpotViewModel // To clear data on sign out
    @EnvironmentObject var locationManager: LocationManager // To stop geofencing on sign out

    @State private var showingSignOutAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account")) {
                    if let email = authViewModel.userSession?.email {
                        LabeledContent("Email", value: email)
                    } else {
                        Text("Not logged in")
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showingSignOutAlert = true
                    }
                }
                
                Section(header: Text("Location & Notifications"), footer: Text("SweetSpots uses background location to notify you when you're near a saved spot. You can manage permissions in your iPhone's Settings app.")) {
                    // Could add toggles here for enabling/disabling geofencing globally if desired
                    // e.g., @AppStorage("geofencingEnabled") var geofencingEnabled = true
                    // Toggle("Enable Proximity Notifications", isOn: $geofencingEnabled)
                    //     .onChange(of: geofencingEnabled) { enabled in
                    //         if enabled {
                    //             locationManager.requestLocationPermission() // Ensure permissions
                    //             locationManager.requestNotificationPermission { _ in }
                    //             spotsViewModel.spots.forEach { locationManager.startMonitoring(spot: $0) }
                    //         } else {
                    //             locationManager.stopAllMonitoring()
                    //         }
                    //     }
                    
                    Button("Request Location Permission") {
                        locationManager.requestLocationPermission()
                    }
                    Button("Request Notification Permission") {
                        locationManager.requestNotificationPermission { _ in }
                    }
                }
                
                Section(header: Text("About")) {
                    LabeledContent("App Version", value: appVersion())
                }
            }
            .navigationTitle("Settings")
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private func signOut() {
        locationManager.stopAllMonitoring() // Stop geofences before signing out
        spotsViewModel.clearData()          // Clear local spot data
        authViewModel.signOut()             // Firebase sign out
        // The ContentView will automatically switch to AuthView due to userSession becoming nil
    }
    
    private func appVersion() -> String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AuthViewModel())
            .environmentObject(SpotViewModel())
            .environmentObject(LocationManager())
    }
}
