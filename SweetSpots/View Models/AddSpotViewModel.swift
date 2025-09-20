//
//  AddSpotViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//

import SwiftUI
import MapKit
import FirebaseCore
import Combine
import CoreLocation

@MainActor
class AddSpotViewModel: ObservableObject {
    @Published var spotForms: [SpotFormState] = [] {
        didSet {
            subscribeToFormChanges()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()

    private func subscribeToFormChanges() {
        // First, clear out any old subscriptions to avoid memory leaks.
        cancellables.removeAll()
        
        // For each form in our array...
        spotForms.forEach { formState in
            // ...listen for its 'objectWillChange' signal...
            formState.objectWillChange
                .sink { [weak self] _ in
                    // ...and when it fires, manually trigger the parent's
                    // 'objectWillChange' signal.
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables) // Store the subscription.
        }
    }
    
    var canSaveAll: Bool {
        !spotForms.isEmpty && spotForms.allSatisfy { $0.isFormValidAndReadyToSave }
    }
}
