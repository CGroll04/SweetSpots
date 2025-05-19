//
//  MainTabView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var spotsViewModel = SpotViewModel() // Create and own it here
    @EnvironmentObject var authViewModel: AuthViewModel // Get the logged-in user
    @StateObject private var locationManager = LocationManager()


    var body: some View {
        TabView(selection: $selectedTab) {
            SpotListView()
                .tabItem {
                    Label("List", systemImage: "list.bullet")
                }
                .tag(0)

            MapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(1)

            AddSpotView(selectedTab: $selectedTab) // Pass binding to switch tab after adding
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .environmentObject(locationManager) // Provide to child views
        .environmentObject(spotsViewModel) // Provide to child views
        .onAppear {
            // Fetch data when the MainTabView appears (i.e., user is logged in)
            if let userId = authViewModel.userSession?.uid {
                spotsViewModel.fetchData(userId: userId)
            }
            locationManager.requestLocationPermission()
                locationManager.requestNotificationPermission { granted in
                    print("Notification permission granted: \(granted)")
                }
            locationManager.spotsViewModelForGeofencing = spotsViewModel

        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AuthViewModel())
            .environmentObject(SpotViewModel())
    }
}
