//
//  LaunchManager.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-07-05.
//

import Foundation
import SwiftUI // Needed for ObservableObject

@MainActor
class LaunchManager: ObservableObject {
    // The shared instance that the whole app will use.
    static let shared = LaunchManager()

    // The action the app should perform on launch.
    @Published var launchAction: MainTabView.LaunchAction?
    
    private init() {} // Private initializer to ensure it's a singleton.
}
