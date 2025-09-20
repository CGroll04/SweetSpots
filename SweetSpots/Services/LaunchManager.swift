//
//  LaunchManager.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-07-05.
//

import Foundation
import SwiftUI // Needed for ObservableObject

@MainActor
final class LaunchManager: ObservableObject {
    static let shared = LaunchManager()

    /// Represents an action to be performed immediately after the app launches.
    enum LaunchAction: Equatable {
        case navigateToSpotID(String)
    }

    @Published var launchAction: MainTabView.LaunchAction?

    private init() {}
    
    /// Resets the pending launch action, ensuring it doesn't fire again.
    func reset() { launchAction = nil }
}
