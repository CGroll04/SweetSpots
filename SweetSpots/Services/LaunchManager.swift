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

    enum LaunchAction: Equatable {
        case navigateToSpotID(String)
        // add more actions in future if needed
    }

    @Published var launchAction: LaunchAction?

    private init() {}

    func reset() { launchAction = nil }
}
