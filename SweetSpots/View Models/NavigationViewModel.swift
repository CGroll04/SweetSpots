//
//  NavigationViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-07-03.
//

import Foundation
import MapKit
import Combine

@MainActor
class NavigationViewModel: ObservableObject {
    // MARK: - Published Properties for UI and State
    
    // State Flags
    @Published var isCalculatingRoute = false
    @Published var isNavigating = false
    @Published var routeCalculationError: String?
    
    // Navigation Data
    @Published var route: MKRoute?
    @Published var destinationSpot: Spot?
    @Published var currentStep: MKRoute.Step?
    
    // Formatted UI Strings
    @Published var remainingTravelTime: String = ""
    @Published var remainingDistance: String = ""
    @Published var arrivalTime: String = ""
    @Published var nextStepInstruction: String = ""
    
    // MARK: - Internal State
    private var routeSteps: [MKRoute.Step] = []
    private var currentStepIndex = 0
    private var cancellables = Set<AnyCancellable>()
    
    // Dependencies
    private let locationManager: LocationManager
    
    // Formatters
    private let distanceFormatter = MKDistanceFormatter()
    private let dateFormatter = DateFormatter()
    private let timeFormatter: DateComponentsFormatter = { // <-- ADD THIS
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated // "10 min", "1 hr"
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        dateFormatter.timeStyle = .short
        
        // This subscription is the engine that drives live updates
        locationManager.$userLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.updateNavigationState(with: location)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Control Functions
    
    /// The primary entry point for starting navigation.
    func startNavigation(to destination: Spot, from userLocation: CLLocation, transportType: MKDirectionsTransportType) async {
        // 1. Set initial state: We are now in the "calculating" phase
        isCalculatingRoute = true
        isNavigating = false // Not yet navigating, just calculating
        self.destinationSpot = destination
        self.route = nil
        self.routeCalculationError = nil
        
        // 2. Build and perform the directions request
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = transportType
        
        let directions = MKDirections(request: request)
        
        do {
            let response = try await directions.calculate()
            isCalculatingRoute = false // Finished calculating
            
            guard let calculatedRoute = response.routes.first else {
                self.routeCalculationError = "No valid routes found."
                return
            }
            
            // 3. Success! Transition to the "navigating" state
            self.route = calculatedRoute
            self.routeSteps = calculatedRoute.steps.filter { !$0.instructions.isEmpty }
            self.currentStepIndex = 0
            self.currentStep = routeSteps.first
            self.isNavigating = true // <<-- THIS IS THE KEY TRANSITION
            
            print("NavigationViewModel: Route calculated. Starting turn-by-turn.")
            updateUIStringsForCurrentState()

        } catch {
            isCalculatingRoute = false
            let nsError = error as NSError
            if nsError.code == MKError.directionsNotFound.rawValue {
                self.routeCalculationError = "Directions to this location could not be found."
            } else {
                self.routeCalculationError = "Route Error: \(error.localizedDescription)"
            }
            print("NavigationViewModel: Error calculating directions - \(error.localizedDescription)")
        }
    }
    
    func stopNavigation() {
        print("NavigationViewModel: Stopping navigation.")
        // Reset all state back to idle
        self.isNavigating = false
        self.isCalculatingRoute = false
        self.route = nil
        self.destinationSpot = nil
        self.currentStep = nil
        self.routeCalculationError = nil
        self.routeSteps = []
        self.currentStepIndex = 0
    }

    // MARK: - Core Navigation Logic (The Live Engine)
    
    private func updateNavigationState(with userLocation: CLLocation) {
        guard isNavigating, let currentStep = routeSteps[safe: currentStepIndex] else { return }

        // --- Rerouting Check ---
        let rerouteThreshold: CLLocationDistance = 50 // meters
        if !isUser(userLocation, on: currentStep.polyline, within: rerouteThreshold) {
            print("NavigationViewModel: User is off-route. Requesting recalculation.")
            Task {
                if let destination = self.destinationSpot, let transportType = self.route?.transportType {
                    // Automatically recalculate with the same parameters
                    await self.startNavigation(to: destination, from: userLocation, transportType: transportType)
                }
            }
            return // Stop processing this update; wait for the new route
        }

        // --- Step Progression ---
        let stepCompletionThreshold: CLLocationDistance = 25 // meters
        // This is the CORRECT code
        let pointCount = currentStep.polyline.pointCount
        guard pointCount > 0 else { return } // Safety check
        let lastMapPoint = currentStep.polyline.points()[pointCount - 1] // Access by index
        let endOfStepLocation = CLLocation(
            latitude: lastMapPoint.coordinate.latitude,
            longitude: lastMapPoint.coordinate.longitude
        )
        let distanceToEndOfStep = userLocation.distance(from: endOfStepLocation)
        
        if distanceToEndOfStep < stepCompletionThreshold {
            advanceToNextStep()
        }
        
        // --- UI Updates ---
        updateUIStringsForCurrentState(distanceToNextStep: distanceToEndOfStep)
    }

    private func advanceToNextStep() {
        currentStepIndex += 1
        if currentStepIndex < routeSteps.count {
            print("NavigationViewModel: Advancing to step \(currentStepIndex + 1)/\(routeSteps.count)")
            self.currentStep = routeSteps[currentStepIndex]
        } else {
            print("NavigationViewModel: Arrived at destination.")
            // You can add a brief "Arrived" state here before stopping
            stopNavigation()
        }
    }
    
    // MARK: - UI Formatting & Helpers
    
    private func updateUIStringsForCurrentState(distanceToNextStep: CLLocationDistance? = nil) {
        guard let route = route, let currentStep = currentStep else {
            remainingTravelTime = ""
            remainingDistance = ""
            arrivalTime = ""
            nextStepInstruction = ""
            return
        }

        self.remainingTravelTime = timeFormatter.string(from: route.expectedTravelTime) ?? ""

        self.remainingDistance = distanceFormatter.string(fromDistance: route.distance)
        self.arrivalTime = "Arrive: \(dateFormatter.string(from: Date().addingTimeInterval(route.expectedTravelTime)))"
        
        if let distance = distanceToNextStep {
            self.nextStepInstruction = "\(distanceFormatter.string(fromDistance: distance)): \(currentStep.instructions)"
        } else {
            self.nextStepInstruction = currentStep.instructions
        }
    }
    
    private func isUser(_ userLocation: CLLocation, on polyline: MKPolyline, within tolerance: CLLocationDistance) -> Bool {
        // (This helper function remains the same as before)
        let userPoint = MKMapPoint(userLocation.coordinate)
        for i in 0..<(polyline.pointCount - 1) {
            let start = polyline.points()[i]
            let end = polyline.points()[i+1]
            let rect = MKMapRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
            let paddedRect = rect.insetBy(dx: -tolerance, dy: -tolerance)
            if paddedRect.contains(userPoint) { return true }
        }
        return false
    }
}
