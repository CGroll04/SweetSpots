//
//  LocationManager.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI
import CoreLocation
import UserNotifications // For notification permissions

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus

    // For geofencing
    @Published var geofenceAlert: (title: String, body: String)? = nil
    @Published var showGeofenceAlert = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // manager.startUpdatingLocation() // Start only when needed or after permission
    }

    func requestLocationPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization() // Or requestAlwaysAuthorization for geofencing
        case .restricted, .denied:
            // Potentially show an alert guiding user to settings
            print("Location access denied or restricted.")
            break
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization() // Ask for Always if we have WhenInUse for geofencing
            manager.startUpdatingLocation()
        case .authorizedAlways:
            manager.startUpdatingLocation()
        @unknown default:
            break
        }
    }
    
    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.first
        // Consider stopping updates if only needed once: manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get user location: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        } else {
            // Handle cases where permission is not granted
        }
    }

    // --- Geofencing ---
    func startMonitoring(spot: Spot) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("Geofencing is not supported on this device.")
            return
        }
        guard authorizationStatus == .authorizedAlways else {
            print("Need 'Always' location authorization for geofencing.")
            // Optionally prompt user or guide them to settings
            return
        }
        guard let spotId = spot.id else {
            print("Spot ID is nil, cannot monitor.")
            return
        }

        let region = CLCircularRegion(
            center: spot.coordinate,
            radius: 200, // meters - adjust as needed
            identifier: spotId
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false // Or true if you want exit notifications

        manager.startMonitoring(for: region)
        print("Started monitoring region: \(spot.name) (\(spotId))")
    }

    func stopMonitoring(spot: Spot) {
        guard let spotId = spot.id else { return }
        for region in manager.monitoredRegions {
            if region.identifier == spotId {
                manager.stopMonitoring(for: region)
                print("Stopped monitoring region: \(spot.name) (\(spotId))")
            }
        }
    }
    
    func stopAllMonitoring() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        print("Stopped monitoring all regions.")
    }
    
    // Called when user enters a region
    // Inside LocationManager.swift

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // Switch to the main actor to safely access SpotsViewModel.spots
        // and update any @Published properties that might trigger UI changes.
        Task { @MainActor in
            guard let viewModel = self.spotsViewModelForGeofencing else {
                print("DEBUG: spotsViewModelForGeofencing is nil in didEnterRegion.")
                return
            }
            guard let spot = viewModel.spots.first(where: { $0.id == region.identifier }) else {
                print("DEBUG: Entered region (\(region.identifier)) but could not find matching spot in viewModel.")
                return
            }

            print("Entered region: \(spot.name)")
            self.sendLocalNotification(spot: spot) // Assuming this is safe to call from main or is internally handled

            // Update @Published properties that will cause UI changes on the main actor
            self.geofenceAlert = (title: "Nearby SweetSpot!", body: "You're near \(spot.name). Check it out!")
            self.showGeofenceAlert = true
        }
    }
    
    // A bit of a hack to access spotsViewModel from here.
    // Ideally, geofencing logic would be more decoupled or use IDs and fetch details.
    // For simplicity in this MVP:
    weak var spotsViewModelForGeofencing: SpotViewModel?

    private func sendLocalNotification(spot: Spot) {
        let content = UNMutableNotificationContent()
        content.title = "SweetSpot Nearby!"
        content.body = "You're near \(spot.name). Why not check it out?"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false) // Deliver immediately
        let request = UNNotificationRequest(identifier: spot.id ?? UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending local notification: \(error.localizedDescription)")
            } else {
                print("Local notification scheduled for \(spot.name)")
            }
        }
    }
    
    // Required for UNUserNotificationCenterDelegate in AppDelegate if you want foreground notifications
    // But for simple background geofencing alerts, this isn't strictly needed in LocationManager.
    // You would set UNUserNotificationCenter.current().delegate = self in AppDelegate.
}
