//
//  ContentView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if authViewModel.userSession == nil {
                AuthView()
                    .environmentObject(authViewModel)
            } else {
                MainTabView()
                    .environmentObject(authViewModel)
            }
        }
    }
}
