//
//  ContentView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    var body: some View {
        Group {
            if authViewModel.userSession == nil {
                AuthView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut, value: authViewModel.userSession)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
