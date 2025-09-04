//
//  LocationManager.swift
//  SweetSpots
//
//  Enhanced version with edge case handling
//

import SwiftUI
import CoreLocation
import UserNotifications

/// Manages location services, including user location updates, permission handling, and geofencing.
@MainActor
class LocationManager: NSObject, ObservableObject {
    private let clManager = CLLocationManager()
    private static let monitoredSpotDetailsKey = "monitoredSpotDetailsKey"
    private static let recentNotificationsKey = "recentNotificationsKey"
    private static let maxGeofences = 20
    private static let notificationCooldownMinutes: TimeInterval = 120 * 60 // 30 minutes
    private static let significantLocationChangeThreshold: CLLocationDistance = 1000 // 1km
    
    // MARK: - Published Properties
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var isRequestingLocationUpdates: Bool = false
    @Published var geofenceTriggeredAlert: GeofenceAlertInfo? = nil
    
    @Published var showPermissionAlert = false
    
    // MARK: - Private Properties
    private var _monitoredSpotDetails: [String: String] = [:]
    private var monitoredSpotDetails: [String: String] {
        get { _monitoredSpotDetails }
        set {
            _monitoredSpotDetails = newValue
            saveMonitoredSpotDetails()
        }
    }
    
    // Track recent notifications to prevent spam
    private var recentNotifications: [String: Date] = [:]
    
    // Track last location used for geofence prioritization
    private var lastGeofencePrioritizationLocation: CLLocation?
    
    // Pending synchronization flag to prevent multiple simultaneous syncs
    private var isSynchronizing = false
    
    struct GeofenceAlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }
    
    // MARK: - Initialization
    override init() {
        self.authorizationStatus = clManager.authorizationStatus
        super.init()
        
        loadPersistedData()
        setupLocationManager()
        setupAppStateObservers()
    }
    
    private func setupLocationManager() {
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        clManager.pausesLocationUpdatesAutomatically = true
        clManager.distanceFilter = 50 // Only update location when user moves 50m
        updateBackgroundLocationCapability(for: self.authorizationStatus)
    }
    
    private func setupAppStateObservers() {
        // Remove the old observer and add these new ones with proper concurrency handling:
        NotificationCenter.default.addObserver(
            forName: .applicationWillEnterForeground,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppWillEnterForeground()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .applicationDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppDidBecomeActive()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .applicationDidEnterBackground,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppDidEnterBackground()
            }
        }
        
        // Listen for geofence notification taps
        NotificationCenter.default.addObserver(
            forName: .geofenceNotificationTapped,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleGeofenceNotificationTapped(notification)
            }
        }
    }
    
    func setupGeofencingWithPermissions(forSpots spots: [Spot], globallyEnabled: Bool) async {
        guard globallyEnabled else {
            print("LM: Geofencing disabled globally")
            stopAllGeofences()
            return
        }
        
        // First ensure we have location permission
        if authorizationStatus != .authorizedAlways {
            print("LM: Requesting Always location permission for geofencing")
            requestLocationAuthorization(aimForAlways: true)
            
            // Wait a bit for the permission dialog
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            guard authorizationStatus == .authorizedAlways else {
                print("LM: Always location permission required for geofencing")
                return
            }
        }
        
        // Then ensure we have notification permission
        let notificationGranted = await requestNotificationPermissionAsync()
        guard notificationGranted else {
            print("LM: Notification permission required for geofencing alerts")
            // You might still want to set up geofences without notifications
            // or show a warning to the user
            return
        }
        
        // Finally set up the geofences
        synchronizeGeofences(forSpots: spots, globallyEnabled: globallyEnabled)
    }
    
    private func handleAppWillEnterForeground() {
        // Clean up expired notification records
        cleanupExpiredNotifications()
        
        // Request a fresh location to potentially re-prioritize geofences
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            clManager.requestLocation()
        }
    }
    
    private func handleAppDidBecomeActive() {
        // Clean up expired notification records
        cleanupExpiredNotifications()
        
        // Clear any existing in-app alerts
        geofenceTriggeredAlert = nil
        
        // Request fresh location if we have permission
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            clManager.requestLocation()
        }
    }
    
    private func handleAppDidEnterBackground() {
        // App entered background - good time to clean up resources
        // The geofences will continue working in background with Always permission
        print("LM: App entered background, geofences remain active")
    }
    
    private func handleGeofenceNotificationTapped(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let spotId = userInfo["spotId"] as? String else {
            return
        }
        
        print("LM: Geofence notification tapped for spot: \(spotId)")
        
        // You might want to delegate this to your main view controller
        // or post another notification that your UI layer can handle
        NotificationCenter.default.post(
            name: .shouldNavigateToSpot,
            object: nil,
            userInfo: ["spotId": spotId, "source": "geofenceNotification"]
        )
    }
    
    // MARK: - Persistence
    private func loadPersistedData() {
        // Load monitored spot details
        if let savedDetails = UserDefaults.standard.dictionary(forKey: Self.monitoredSpotDetailsKey) as? [String: String] {
            _monitoredSpotDetails = savedDetails
        }
        
        // Load recent notifications
        if let savedNotifications = UserDefaults.standard.dictionary(forKey: Self.recentNotificationsKey) as? [String: Date] {
            recentNotifications = savedNotifications
            cleanupExpiredNotifications()
        }
    }
    
    private func saveMonitoredSpotDetails() {
        UserDefaults.standard.set(_monitoredSpotDetails, forKey: Self.monitoredSpotDetailsKey)
    }
    
    private func saveRecentNotifications() {
        UserDefaults.standard.set(recentNotifications, forKey: Self.recentNotificationsKey)
    }
    
    private func cleanupExpiredNotifications() {
        let cutoffTime = Date().addingTimeInterval(-Self.notificationCooldownMinutes)
        let expiredKeys = recentNotifications.compactMap { key, date in
            date < cutoffTime ? key : nil
        }
        
        for key in expiredKeys {
            recentNotifications.removeValue(forKey: key)
        }
        
        if !expiredKeys.isEmpty {
            saveRecentNotifications()
        }
    }
    
    // MARK: - Permission Management
    func requestLocationAuthorization(aimForAlways: Bool = false) {
        print("Requesting location authorization. Current status: \(LocationManager.string(for: authorizationStatus)). Aiming for Always: \(aimForAlways)")

        switch authorizationStatus {
        case .notDetermined:
            // First time request. We can only ask for "When In Use".
            clManager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse:
            // User has granted basic permission. If our goal is "Always", request the upgrade.
            if aimForAlways {
                clManager.requestAlwaysAuthorization()
            }

        case .denied, .restricted:
            // User has denied permission. We cannot show a popup and must guide them to Settings.
            self.showPermissionAlert = true
            
        case .authorizedAlways:
            // We already have full permission. Do nothing.
            break

        @unknown default:
            print("Unknown location authorization status.")
        }
    }
    
    func requestNotificationPermission(completion: @escaping (_ granted: Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func requestNotificationPermissionCoordinated(completion: @escaping (Bool) -> Void) {
        // Get the app delegate to handle notification permissions consistently
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            // Fallback to direct request if needed
            requestNotificationPermission(completion: completion)
            return
        }
        
        appDelegate.requestNotificationPermissionIfNeeded(completion: completion)
    }

    
    func requestNotificationPermissionAsync() async -> Bool {
        await withCheckedContinuation { continuation in
            requestNotificationPermissionCoordinated { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func updateBackgroundLocationCapability(for status: CLAuthorizationStatus) {
        clManager.allowsBackgroundLocationUpdates = (status == .authorizedAlways)
    }
    
    // MARK: - Location Updates
    func startUpdatingUserLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationAuthorization(aimForAlways: false)
            return
        }
        
        clManager.startUpdatingLocation()
        isRequestingLocationUpdates = true
    }
    
    func stopUpdatingUserLocation() {
        clManager.stopUpdatingLocation()
        isRequestingLocationUpdates = false
    }
    
    public func requestWhenInUseAuthorization() {
        if authorizationStatus == .notDetermined {
            clManager.requestWhenInUseAuthorization()
        }
    }
    
    // MARK: - Geofencing Management
    private func startGeofence(for spot: Spot) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("LM Error: Geofencing not supported on this device.")
            return
        }
        
        guard let spotId = spot.id else {
            print("LM Error: Spot ID is nil for '\(spot.name)'. Cannot start geofence.")
            return
        }
        
        guard spot.notificationRadiusMeters >= 50 && spot.notificationRadiusMeters <= 50000 else {
            print("LM Error: Invalid radius \(spot.notificationRadiusMeters) for spot '\(spot.name)'. Must be 50-50000m.")
            return
        }
        
        // Stop existing geofence first to ensure clean state
        stopGeofence(forSpotId: spotId)
        
        let region = CLCircularRegion(center: spot.coordinate, radius: spot.notificationRadiusMeters, identifier: spotId)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        
        // Update monitoring details atomically
        var updatedDetails = _monitoredSpotDetails
        updatedDetails[spotId] = spot.name
        monitoredSpotDetails = updatedDetails
        
        clManager.startMonitoring(for: region)
    }
    
    private func stopGeofence(forSpotId spotId: String) {
        let regionsToStop = clManager.monitoredRegions.filter { $0.identifier == spotId }
        for region in regionsToStop {
            clManager.stopMonitoring(for: region)
        }
        
        if _monitoredSpotDetails.removeValue(forKey: spotId) != nil {
            saveMonitoredSpotDetails()
        }
    }
    
    func stopAllGeofences() {
        guard !clManager.monitoredRegions.isEmpty || !_monitoredSpotDetails.isEmpty else {
            return
        }
        
        for region in clManager.monitoredRegions {
            clManager.stopMonitoring(for: region)
        }
        
        if !_monitoredSpotDetails.isEmpty {
            _monitoredSpotDetails.removeAll()
            saveMonitoredSpotDetails()
        }
        
        print("LM: All geofences stopped.")
    }
    
    var activeGeofenceIDs: Set<String> {
        Set(clManager.monitoredRegions.map { $0.identifier })
    }
    
    // MARK: - Enhanced Synchronization
    func synchronizeGeofences(forSpots spots: [Spot], globallyEnabled: Bool) {
        // Prevent multiple simultaneous synchronizations
        guard !isSynchronizing else {
            print("LM: Synchronization already in progress, skipping")
            return
        }
        
        isSynchronizing = true
        defer { isSynchronizing = false }
        
        print("LM: Synchronizing geofences. Global enabled: \(globallyEnabled), Spots count: \(spots.count)")
        
        guard globallyEnabled else {
            print("LM: Global geofencing disabled, stopping all geofences")
            stopAllGeofences()
            return
        }
        
        guard authorizationStatus == .authorizedAlways else {
            print("LM: 'Always' location permission required for geofencing")
            if !activeGeofenceIDs.isEmpty {
                stopAllGeofences()
            }
            return
        }
        
        let validSpots = spots.filter { spot in
            guard spot.wantsNearbyNotification,
                  let spotId = spot.id,
                  !spotId.isEmpty,
                  spot.notificationRadiusMeters >= 50,
                  spot.notificationRadiusMeters <= 50000 else {
                return false
            }
            return true
        }
        
        let spotsToMonitor = prioritizeSpots(validSpots)
        let desiredSpotIDs = Set(spotsToMonitor.compactMap { $0.id })
        let currentSystemMonitoredIDs = activeGeofenceIDs
        
        // Add/Update geofences
        for spot in spotsToMonitor {
            startGeofence(for: spot)
        }
        
        // Remove unwanted geofences
        let idsToRemove = currentSystemMonitoredIDs.subtracting(desiredSpotIDs)
        for idToRemove in idsToRemove {
            stopGeofence(forSpotId: idToRemove)
        }
        
        print("LM: Geofence sync complete. Active: \(activeGeofenceIDs.count), Desired: \(desiredSpotIDs.count)")
    }
    
    private func prioritizeSpots(_ spots: [Spot]) -> [Spot] {
        var prioritizedSpots = spots
        
        // If we have too many spots and user location is available, prioritize by distance
        if spots.count > Self.maxGeofences, let userLoc = userLocation {
            prioritizedSpots = spots.sorted { spot1, spot2 in
                let dist1 = userLoc.distance(from: CLLocation(latitude: spot1.latitude, longitude: spot1.longitude))
                let dist2 = userLoc.distance(from: CLLocation(latitude: spot2.latitude, longitude: spot2.longitude))
                return dist1 < dist2
            }
            
            lastGeofencePrioritizationLocation = userLoc
            print("LM: Prioritized spots by distance from user location")
        }
        
        return Array(prioritizedSpots.prefix(Self.maxGeofences))
    }
    
    // MARK: - Location-based Re-prioritization
    func checkForGeofenceReprioritization() {
        guard let currentLocation = userLocation,
              let lastLocation = lastGeofencePrioritizationLocation else {
            return
        }
        
        let distanceMoved = currentLocation.distance(from: lastLocation)
        guard distanceMoved > Self.significantLocationChangeThreshold else {
            return
        }
        
        print("LM: User moved \(distanceMoved)m, checking if geofence reprioritization needed")
        // This would need to be called with current spots from your data source
        // Consider adding a callback or delegate pattern here
    }
    
    // MARK: - Enhanced Geofence Event Handling
    private func handleGeofenceEvent(for region: CLRegion, eventType: String) {
        guard let spotName = _monitoredSpotDetails[region.identifier] else {
            print("LM Warning: No spot name found for region \(region.identifier)")
            return
        }
        
        // Check notification cooldown
        if let lastNotificationTime = recentNotifications[region.identifier] {
            let timeSinceLastNotification = Date().timeIntervalSince(lastNotificationTime)
            if timeSinceLastNotification < Self.notificationCooldownMinutes {
                print("LM: Skipping notification for '\(spotName)' - within cooldown period")
                return
            }
        }
        
        // Record this notification
        recentNotifications[region.identifier] = Date()
        saveRecentNotifications()
        
        scheduleLocalNotificationForGeofence(spotId: region.identifier, spotName: spotName, eventType: eventType)
        
        // Show in-app alert only if app is active
        if UIApplication.shared.applicationState == .active {
            self.geofenceTriggeredAlert = GeofenceAlertInfo(
                title: "Nearby SweetSpot!",
                body: "You're near \(spotName)."
            )
        }
    }
    
    private func scheduleLocalNotificationForGeofence(spotId: String, spotName: String, eventType: String) {
        let content = UNMutableNotificationContent()
        content.title = "SweetSpot Nearby!"
        content.body = "You're near \(spotName). Check it out!"
        content.sound = .default
        content.userInfo = ["spotId": spotId, "geofenceEvent": eventType]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        // Use consistent identifier to replace previous notifications for same spot
        let requestIdentifier = "geofence_\(spotId)"
        
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("LM: Error scheduling geofence notification: \(error.localizedDescription)")
            } else {
                print("LM: Successfully scheduled notification for '\(spotName)'")
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        Task { @MainActor [weak self] in
            let oldLocation = self?.userLocation
            self?.userLocation = newLocation
            
            // Check if we need to reprioritize geofences
            if let oldLoc = oldLocation {
                let distanceMoved = newLocation.distance(from: oldLoc)
                if distanceMoved > Self.significantLocationChangeThreshold {
                    self?.checkForGeofenceReprioritization()
                }
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LM: Location manager failed with error: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.isRequestingLocationUpdates = false
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let oldStatus = self.authorizationStatus
            self.authorizationStatus = newStatus
            print("LM: Authorization changed from \(LocationManager.string(for: oldStatus)) to \(LocationManager.string(for: newStatus))")
            
            self.updateBackgroundLocationCapability(for: newStatus)
            
            // Handle permission downgrades
            if oldStatus == .authorizedAlways && newStatus != .authorizedAlways {
                print("LM: Lost 'Always' permission, stopping all geofences")
                self.stopAllGeofences()
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor [weak self] in
            print("LM: Entered region: \(region.identifier)")
            self?.handleGeofenceEvent(for: region, eventType: "Entered")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let regionID = region?.identifier ?? "unknown"
        print("LM: Geofence monitoring failed for region ID \(regionID): \(error.localizedDescription)")
        
        if let regionIdentifier = region?.identifier {
            Task { @MainActor [weak self] in
                if self?._monitoredSpotDetails.removeValue(forKey: regionIdentifier) != nil {
                    self?.saveMonitoredSpotDetails()
                }
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    }
}

// MARK: - Helper Extension
extension LocationManager {
    static func string(for status: CLAuthorizationStatus) -> String {
        // (Helper function for logging)
        switch status {
            case .notDetermined: return "Not Determined"
            case .restricted: return "Restricted"
            case .denied: return "Denied"
            case .authorizedAlways: return "Authorized Always"
            case .authorizedWhenInUse: return "Authorized When In Use"
            @unknown default: return "Unknown"
        }
    }
}
