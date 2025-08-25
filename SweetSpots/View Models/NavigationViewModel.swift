//
//  NavigationViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-07-03.
//

import SwiftUI
import Foundation
import MapKit
import Combine

@MainActor
class NavigationViewModel: ObservableObject {
    
    struct RouteInfo {
        let spot: Spot
        let route: MKRoute
        var expectedTravelTime: String {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.hour, .minute]
            return formatter.string(from: route.expectedTravelTime) ?? ""
        }
    }

    enum NavigationState: Equatable {
        static func == (lhs: NavigationViewModel.NavigationState, rhs: NavigationViewModel.NavigationState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.selectingRoute(let lhsInfo), .selectingRoute(let rhsInfo)): return lhsInfo.spot.id == rhsInfo.spot.id && lhsInfo.route == rhsInfo.route
            default: return false
            }
        }
        
        case idle
        case selectingRoute(info: RouteInfo)
    }
    
    @Published var navigationState: NavigationState = .idle
    @Published var selectedTransportType: TransportType = .driving {
        didSet {
            // Re-fetch the route when the transport type changes
            if case .selectingRoute(let info) = navigationState, let userLocation = locationManager.userLocation {
                Task {
                    await setNavigationTarget(spot: info.spot, from: userLocation)
                }
            }
        }
    }
    
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
    func setNavigationTarget(spot: Spot, from userLocation: CLLocation) async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: spot.coordinate))
        request.transportType = selectedTransportType.mkType

        let directions = MKDirections(request: request)
        do {
            if let routeResponse = try? await directions.calculate() {
                if let route = routeResponse.routes.first {
                    let info = RouteInfo(spot: spot, route: route)
                    self.navigationState = .selectingRoute(info: info)
                } else {
                    // Handle the case where a response was received but had no routes
                    print("Error: No routes found.")
                    self.navigationState = .idle
                }
            } else {
                // Handle the case where calculate() returned nil
                print("Error: Route calculation returned nil.")
                self.navigationState = .idle
            }
        }
    }

    // 3. CREATE A FUNCTION TO START THE ACTUAL NAVIGATION
    func beginActualNavigation() {
        // 1. Make sure we have a route selected
        guard case .selectingRoute(let info) = navigationState else { return }

        print("NavigationViewModel: Starting in-app navigation.")

        // 2. Set up all the state properties for turn-by-turn mode
        self.route = info.route
        self.destinationSpot = info.spot
        self.routeSteps = info.route.steps.filter { !$0.instructions.isEmpty }
        self.currentStepIndex = 0
        self.currentStep = self.routeSteps.first
        self.isNavigating = true // This shows the turn-by-turn UI
        self.isCalculatingRoute = false
        self.routeCalculationError = nil

        // 3. Update the UI text for the first step
        updateUIStringsForCurrentState()

        // 4. Hide the route selection card
        withAnimation {
            self.navigationState = .idle
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
    
    func cancelRouteSelection() {
        print("NavigationViewModel: Route selection cancelled.")
        withAnimation {
            self.navigationState = .idle
        }
    }

    // MARK: - Core Navigation Logic (The Live Engine)
    
    private func updateNavigationState(with userLocation: CLLocation) {
        guard isNavigating, let currentStep = routeSteps[safe: currentStepIndex] else { return }

        // --- Rerouting Check ---
        let rerouteThreshold: CLLocationDistance = 50 // meters
        if !isUser(userLocation, on: currentStep.polyline, within: rerouteThreshold) {
            print("NavigationViewModel: User is off-route. Requesting recalculation.")
            Task {
                if let destination = self.destinationSpot, let _ = self.route?.transportType {
                    // Automatically recalculate with the same parameters
                    await self.setNavigationTarget(spot: destination, from: userLocation)
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
