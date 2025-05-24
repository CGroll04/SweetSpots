//
//  MainTabView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0 // Default to the first tab (List)
    @StateObject private var spotsViewModel = SpotViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var locationManager = LocationManager()

    // Custom Tab Bar Appearance Configuration
    init() {
        // Configure the standard appearance for the tab bar
        let standardAppearance = UITabBarAppearance()
        standardAppearance.configureWithOpaqueBackground()

        // Tab Bar Background Color
        standardAppearance.backgroundColor = UIColor(Color.themeFieldBackground)

        // Optional: Add a subtle top border line for separation
        standardAppearance.shadowColor = UIColor(Color.themeTextSecondary.opacity(0.3))

        // --- Tab Item Colors and Text Attributes ---

        // Normal (Unselected) Tab Item
        let normalTitleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(Color.themeTextSecondary)
            // Optional: .font: UIFont.systemFont(ofSize: 10)
        ]
        standardAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color.themeTextSecondary)
        standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes = normalTitleAttributes
        // Apply to other layouts for consistency if they are ever used
        standardAppearance.inlineLayoutAppearance.normal.titleTextAttributes = normalTitleAttributes
        standardAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = normalTitleAttributes


        // Selected Tab Item
        let selectedTitleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(Color.themePrimary)
            // Optional: .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        standardAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.themePrimary) // Crucial for selected icon color
        standardAppearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedTitleAttributes
        // Apply to other layouts for consistency
        standardAppearance.inlineLayoutAppearance.selected.titleTextAttributes = selectedTitleAttributes
        standardAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = selectedTitleAttributes
        
        // Apply the configured appearance globally
        UITabBar.appearance().standardAppearance = standardAppearance
        UITabBar.appearance().scrollEdgeAppearance = standardAppearance // Important for iOS 15+ for consistency
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            SpotListView()
                .tabItem {
                    Label("List", systemImage: selectedTab == 0 ? "list.bullet.circle.fill" : "list.bullet.circle")
                }
                .tag(0)
            
            MapView()
                .tabItem {
                    Label("Map", systemImage: selectedTab == 1 ? "map.fill" : "map")
                }
                .tag(1)
            
            AddSpotView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Add", systemImage: selectedTab == 2 ? "plus.circle.fill" : "plus.circle")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: selectedTab == 3 ? "gearshape.fill" : "gearshape")
                }
                .tag(3)
        }
        // Apply the accentColor HERE to influence the tint of selected tab items (especially SF Symbols)
        .accentColor(Color.themePrimary)
        .environmentObject(locationManager)
        .environmentObject(spotsViewModel)
        .task {
            setupApp()
        }
    }
    
    private func setupApp() {
        // Request permissions
        locationManager.requestLocationPermission()
        locationManager.requestNotificationPermission { granted in
            if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied")
            }
        }
        
        // Setup geofencing
        locationManager.spotsViewModelForGeofencing = spotsViewModel
        
        // Fetch user data
        if let userId = authViewModel.userSession?.uid { // Ensure authViewModel.userSession.uid is available
            spotsViewModel.fetchData(userId: userId)
        }
    }
}

#Preview {
    // Create a mock or simple AuthViewModel for the preview.
    let previewAuthViewModel = AuthViewModel()
    return MainTabView()
        .environmentObject(previewAuthViewModel)
}
