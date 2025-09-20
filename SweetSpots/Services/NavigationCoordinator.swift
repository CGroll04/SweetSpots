//
//  NavigationCoordinator.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-11.
//

import Foundation
import SwiftUI
import FirebaseFirestore

final class NavigationCoordinator: ObservableObject {
    @Published var incomingSharedPayload: SharedSpotPayload? = nil
    @Published var incomingSharedCollectionPayload: SharedCollectionPayload? = nil
    @Published var incomingSharedURL: URL? = nil
}
