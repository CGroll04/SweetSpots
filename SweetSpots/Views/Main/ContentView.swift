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
    
    var body: some View {
        // Group allows for conditional view switching without requiring a common parent container
        // that might interfere with full-screen presentations like sheets or navigation.
        Group {
            if authViewModel.userSession == nil {
                // If no user is currently signed in, present the authentication flow.
                AuthView()
            } else {
                // If a user session exists (user is signed in), present the main application interface.
                MainTabView(authViewModel: authViewModel)
            }
        }
        // Apply a fade-in/out animation when switching between AuthView and MainTabView
        // triggered by changes in the userSession state.
        .animation(.easeInOut, value: authViewModel.userSession)
    }
}
