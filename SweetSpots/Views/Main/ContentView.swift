//
//  ContentView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//
import SwiftUI
import TipKit

/// The root view of the application.
/// It conditionally displays either the AuthView for user authentication
/// or the MainTabView for the main application interface, based on the user's session state.
struct ContentView: View {
    // Injects the AuthViewModel from the environment.
    // This instance is provided by SweetSpotsApp and manages the user's session.
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    @AppStorage("hasShownWelcomeScreen") private var hasShownWelcomeScreen: Bool = false
    @AppStorage(TutorialKeys.hasSeenInfoButtonPDF) private var hasSeenInfoButtonPDF: Bool = false
    @State private var showInfoReminderScreen = false
    
    var body: some View {
        Group {
            if !hasShownWelcomeScreen {
                // Step 1: User's first launch, show WelcomeView
                WelcomeView {
                    // Step 2: User taps "Get Started", set flag to true
                    hasShownWelcomeScreen = true
                }
            } else if authViewModel.userSession == nil {
                AuthView()
            } else {
                MainTabView(authViewModel: authViewModel)
            }
        }
        .animation(.easeInOut, value: hasShownWelcomeScreen)
        .animation(.easeInOut, value: authViewModel.userSession)
        .onChange(of: hasShownWelcomeScreen) { _, newHasShown in
            // When the welcome screen is dismissed (and user is logged in)
            if newHasShown && authViewModel.userSession != nil {
                // ...check if we need to show the info PDF.
                if !hasSeenInfoButtonPDF {
                    // Use a delay so it doesn't appear at the exact
                    // same time as the main view.
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showInfoReminderScreen = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showInfoReminderScreen) {
            InfoButtonReminderView {
                // This is TipKit, which is fine for this *one* screen.
                // It just marks the PDF as "seen" forever.
                hasSeenInfoButtonPDF = true // Set our new flag
                                
                showInfoReminderScreen = false
                
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    
                    // Post the notification that SpotListView will be listening for.
                    NotificationCenter.default.post(name: .infoPDFDismissed, object: nil)
                }
            }
        }
    }
}
