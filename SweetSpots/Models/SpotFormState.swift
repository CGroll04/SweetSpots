//
//  SpotFormState.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//

import SwiftUI
import MapKit
import FirebaseCore
import Combine
import CoreLocation

// MARK: - Step 1: Create the SpotFormState Class
/// This class holds all the data and state for a single, collapsible spot form.
/// It is an ObservableObject to allow SwiftUI views to react to its changes.
@MainActor
class SpotFormState: ObservableObject, Identifiable {
    let id = UUID() // Needed for ForEach loops

    // MARK: - Form Data Properties (Moved from AddSpotView)
    @Published var spotName: String = ""
    @Published var spotAddress: String = ""
    @Published var spotCoordinates: CLLocationCoordinate2D?
    @Published var spotSourceURLInput: String = "Manually Added"
    @Published var selectedCategory: SpotCategory? = nil
    @Published var spotPhoneNumber: String = ""
    @Published var spotWebsiteURLInput: String = ""
    @Published var selectedCollectionIds: Set<String> = []
    @Published var spotNotes: String = ""
    @Published var senderName: String = ""
    @Published var isFromShare: Bool = false

    // MARK: - Notification Setting Properties (Moved from AddSpotView)
    @Published var wantsNearbyNotificationForThisSpot: Bool = false
    @Published var notificationRadiusForThisSpot: Double = 200.0
    @Published var selectedRadiusPreset: SpotFormSectionView.RadiusPreset = .medium
    @Published var showingCustomRadiusTextField: Bool = false
    @Published var customRadiusText: String = ""

    // MARK: - Individual Form UI State
    @Published var isExpanded: Bool = true
    @Published var searchCompleterVM = SearchCompleterViewModel()
    
    private var originalSpot: Spot? // To track changes in edit mode
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializers
    init() {
        // Creates a blank form for "Add New Manual" mode.
        setupSearchCompleterSubscription()
    }

    init(sourceURL: String, collectionIds: [String] = []) {
        self.spotSourceURLInput = sourceURL
        self.selectedCollectionIds = Set(collectionIds)
        self.isFromShare = true
        setupSearchCompleterSubscription()

    }
    
    init(spot: Spot) {
        self.originalSpot = spot
        
        // Populate all fields from the existing spot object
        self.spotName = spot.name
        self.spotAddress = spot.address
        self.searchCompleterVM.queryFragment = spot.address
        self.spotCoordinates = spot.coordinate
        self.spotSourceURLInput = spot.sourceURL ?? "Manually Added"
        self.selectedCategory = spot.category
        self.spotPhoneNumber = spot.phoneNumber ?? ""
        self.spotWebsiteURLInput = spot.websiteURL ?? ""
        self.selectedCollectionIds = Set(spot.collectionIds)
        self.spotNotes = spot.notes ?? ""
        self.senderName = spot.senderName ?? ""
        self.wantsNearbyNotificationForThisSpot = spot.wantsNearbyNotification

        let validRadius = max(50.0, min(50000.0, spot.notificationRadiusMeters))
        self.notificationRadiusForThisSpot = validRadius
        self.selectedRadiusPreset = SpotFormSectionView.RadiusPreset.preset(for: validRadius)

        if self.selectedRadiusPreset == .custom {
            self.customRadiusText = String(Int(validRadius))
            self.showingCustomRadiusTextField = true
        }
        
        self.isFromShare = false
        setupSearchCompleterSubscription()

    }
    
    init(payload: SharedSpotPayload) {
        self.spotName = payload.name
        self.spotAddress = payload.address
        self.searchCompleterVM.queryFragment = payload.address
        self.spotCoordinates = CLLocationCoordinate2D(latitude: payload.latitude, longitude: payload.longitude)
        self.selectedCategory = SpotCategory(rawValue: payload.category) ?? .other
        self.spotPhoneNumber = payload.phoneNumber ?? ""
        self.spotWebsiteURLInput = payload.websiteURL ?? ""
        self.selectedCollectionIds = [] // Imported spots start with no collections, user adds them
        self.spotNotes = payload.notes ?? ""
        self.spotSourceURLInput = payload.sourceURL ?? "Manually Added"
        self.isFromShare = true
        self.senderName = payload.senderName ?? ""
        setupSearchCompleterSubscription()
    }
    
    private func setupSearchCompleterSubscription() {
            searchCompleterVM.objectWillChange
                .sink { [weak self] _ in
                    // When the inner VM is about to change,
                    // we manually trigger the outer class's change notification.
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

    // MARK: - Computed Validation Properties (Moved from AddSpotView)
    var isValidSpotName: Bool { !spotName.trimmedSafe().isEmpty && spotName.trimmedSafe().count <= 100 }
    var isValidAddress: Bool { spotCoordinates != nil && !spotAddress.trimmedSafe().isEmpty }
    var isValidSourceURL: Bool {
        let trimmed = spotSourceURLInput.trimmedSafe()
        return trimmed.isEmpty || trimmed == "Manually Added" || trimmed.isValidURL
    }
    var isValidPhoneNumber: Bool { spotPhoneNumber.trimmedSafe().isEmpty || ValidationUtils.isValidPhoneNumber(spotPhoneNumber.trimmedSafe()) }
    var isValidWebsiteURL: Bool { spotWebsiteURLInput.trimmedSafe().isEmpty || spotWebsiteURLInput.trimmedSafe().isValidURL }
    var isValidCustomRadius: Bool {
        if selectedRadiusPreset != .custom { return true }
        guard let radius = Double(customRadiusText) else { return false }
        return radius >= 50 && radius <= 50000
    }
    
    var hasChanges: Bool {
        guard let original = originalSpot else { return true } // Always has "changes" for new spots
        if spotName != original.name { return true }
        if spotAddress != original.address { return true }
        if spotSourceURLInput.trimmedSafe() != (original.sourceURL ?? "Manually Added") { return true }
        if selectedCategory != original.category { return true }
        if spotPhoneNumber.trimmedSafe() != (original.phoneNumber ?? "") { return true }
        if spotWebsiteURLInput.trimmedSafe() != (original.websiteURL ?? "") { return true }
        if selectedCollectionIds != Set(original.collectionIds) { return true }
        if spotNotes.trimmedSafe() != (original.notes ?? "") { return true }
        if wantsNearbyNotificationForThisSpot != original.wantsNearbyNotification { return true }
        if !notificationRadiusForThisSpot.isApproximately(original.notificationRadiusMeters) { return true }
        return false
    }
    var validationErrors: [String] {
        var errors: [String] = []
        if !isValidSpotName { errors.append("Spot Name is required.") }
        if !isValidAddress { errors.append("A valid Address is required.") }
        if selectedCategory == nil { errors.append("A Category is required.") }
        if !hasChanges && originalSpot != nil { errors.append("No changes have been made.") }
        // You can add more checks for other fields if you like
        return errors
    }

    var isFormValidAndReadyToSave: Bool {
        // Check the main required fields first
        let hasRequiredFields = isValidSpotName && isValidAddress && selectedCategory != nil
        
        // Check all optional fields
        let hasValidOptionalFields = isValidSourceURL && isValidPhoneNumber && isValidWebsiteURL && isValidCustomRadius
        
        // In edit mode, we also require that there are changes
        if originalSpot != nil { // This implies edit mode
            return hasRequiredFields && hasValidOptionalFields && hasChanges
        }
        
        // In add mode, we don't require changes (it's all new)
        return hasRequiredFields && hasValidOptionalFields
    }
    
    // MARK: - Model Conversion
    /// Builds a `Spot` model object from the current form state.
    func buildSpotModel(with userId: String) -> Spot? {
        guard let coords = spotCoordinates, let category = selectedCategory else { return nil }
        
        let finalSourceURL = (spotSourceURLInput.trimmedSafe() == "Manually Added" || spotSourceURLInput.trimmedSafe().isEmpty) ? nil : spotSourceURLInput.trimmedSafe()
        let finalPhoneNumber = spotPhoneNumber.trimmedSafe().isEmpty ? nil : spotPhoneNumber.trimmedSafe()
        let finalWebsiteURL: String? = {
            let trimmed = spotWebsiteURLInput.trimmedSafe()
            if trimmed.isEmpty { return nil }
            return (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? trimmed : "https://\(trimmed)"
        }()
        let finalNotes = spotNotes.trimmedSafe().isEmpty ? nil : spotNotes.trimmedSafe()
        
        // Use the validated radius value
        var finalRadiusInMeters = self.notificationRadiusForThisSpot
        if selectedRadiusPreset == .custom, let customRadiusValue = Double(customRadiusText) {
            // If the user's system is not metric, they entered feet. Convert to meters.
            if Locale.current.measurementSystem != .metric {
                finalRadiusInMeters = Measurement(value: customRadiusValue, unit: UnitLength.feet).converted(to: .meters).value
            } else {
                // Otherwise, they entered meters.
                finalRadiusInMeters = customRadiusValue
            }
        }
        
        return Spot(
            id: originalSpot?.id,
            userId: userId,
            name: spotName.trimmedSafe(),
            address: spotAddress.trimmedSafe(),
            latitude: coords.latitude,
            longitude: coords.longitude,
            sourceURL: finalSourceURL,
            category: category,
            phoneNumber: finalPhoneNumber,
            websiteURL: finalWebsiteURL,
            collectionIds: Array(self.selectedCollectionIds),
            wantsNearbyNotification: wantsNearbyNotificationForThisSpot,
            notificationRadiusMeters: finalRadiusInMeters,
            notes: finalNotes,
            senderName: self.senderName
        )
    }
}
