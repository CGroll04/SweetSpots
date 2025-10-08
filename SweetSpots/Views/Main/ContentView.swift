//
//  ContentView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import SwiftUI

/// The root view of the application.
/// It conditionally displays either the AuthView for user authentication
/// or the MainTabView for the main application interface, based on the user's session state.
struct ContentView: View {
    // Injects the AuthViewModel from the environment.
    // This instance is provided by SweetSpotsApp and manages the user's session.
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    @AppStorage("hasShownInitialTutorial") private var hasShownInitialTutorial: Bool = false
    @State private var showTutorial = false
    @State private var showTutorialReminder = false

    
    var body: some View {
        // MARK: - 2. Wrap in a ZStack for the popup overlay
        ZStack {
            Group {
                if authViewModel.userSession == nil {
                    AuthView()
                } else {
                    MainTabView(authViewModel: authViewModel)
                }
            }
            .animation(.easeInOut, value: authViewModel.userSession)
            
            // The reminder popup overlay
            if showTutorialReminder {
                ReminderPopupView()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1) // Ensure it's on top of everything
            }
        }
        // MARK: - 3. Add Modifiers to Trigger the Tutorial
        .onReceive(authViewModel.$userSession.dropFirst()) { userSession in
            // When a new user logs in for the first time...
            if userSession != nil && !hasShownInitialTutorial {
                // ...wait 2 seconds before showing the tutorial.
                Task {
                    // This delay gives time for system popups like notifications/location to appear first
                    try? await Task.sleep(for: .seconds(2))
                    showTutorial = true
                }
            }
        }
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView {
                // This code runs when the tutorial is dismissed
                hasShownInitialTutorial = true // Mark tutorial as seen so it doesn't show again
                showTutorial = false
                
                // Show the reminder popup
                withAnimation {
                    showTutorialReminder = true
                }
                
                // Hide the reminder after 3 seconds
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation {
                        showTutorialReminder = false
                    }
                }
            }
        }
    }
}

struct ReminderPopupView: View {
    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                Text("You can find the tutorial again in Settings.")
                    .font(.footnote)
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .shadow(radius: 10)
            
            Spacer()
        }
        .padding()
    }
}
