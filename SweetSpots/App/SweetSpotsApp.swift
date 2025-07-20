//
//  SweetSpotsApp.swift
//  SweetSpots
//
//  Enhanced version with better notification coordination
//

import SwiftUI
import FirebaseCore
import UserNotifications

@main
struct SweetSpotsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .onOpenURL { incomingURL in
                    handleIncomingURL(incomingURL)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "sweetspotsapp", url.host == "addSpot" else {
            return
        }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        if let sourceURLString = components?.queryItems?.first(where: { $0.name == "sourceURL" })?.value,
           let decodedURLString = sourceURLString.removingPercentEncoding {
            
            UserDefaults.standard.set(decodedURLString, forKey: AppConstants.pendingSharedURLKey)
            NotificationCenter.default.post(name: .handlePendingSharedURL, object: nil)
        }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Track notification permission state to coordinate with LocationManager
    private var hasRequestedNotificationPermission = false
    private var notificationPermissionGranted = false
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        setupNotificationCenter()
        setupRemoteNotifications(for: application)
        
        // Handle deep links if the app is launched via a URL
        if let url = launchOptions?[.url] as? URL {
            handleDeepLinkAtLaunch(url)
        }
        
        return true
    }
    
    private func setupNotificationCenter() {
        UNUserNotificationCenter.current().delegate = self
        
        // Check current notification authorization status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationPermissionGranted = settings.authorizationStatus == .authorized
                self.hasRequestedNotificationPermission = settings.authorizationStatus != .notDetermined
            }
        }
    }

    private func handleDeepLinkAtLaunch(_ url: URL) {
        guard url.scheme == "sweetspotsapp", url.host == "addSpot" else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let sourceURLString = components?.queryItems?.first(where: { $0.name == "sourceURL" })?.value,
           let decodedURLString = sourceURLString.removingPercentEncoding {
            UserDefaults.standard.set(decodedURLString, forKey: AppConstants.pendingSharedURLKey)
        }
    }
    
    // MARK: - Remote Notifications Setup
    private func setupRemoteNotifications(for application: UIApplication) {
        // Request authorization only if not already requested
        // Let LocationManager handle the permission request in context
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            case .notDetermined:
                // Don't automatically request - let the user flow handle this
                break
            case .denied, .provisional, .ephemeral:
                // User has made a decision, respect it
                break
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - App Lifecycle
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Clear badge when app becomes active
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("Failed to clear badge: \(error)")
            }
        }
        
        // Notify other parts of the app that we're active
        NotificationCenter.default.post(name: .applicationDidBecomeActive, object: nil)
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // App is about to become inactive
        NotificationCenter.default.post(name: .applicationWillResignActive, object: nil)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // App entered background
        NotificationCenter.default.post(name: .applicationDidEnterBackground, object: nil)
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // App will enter foreground
        NotificationCenter.default.post(name: .applicationWillEnterForeground, object: nil)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        
        // Check if this is a geofence notification
        if let geofenceEvent = userInfo["geofenceEvent"] as? String,
           let spotId = userInfo["spotId"] as? String {
            
            // For geofence notifications in foreground, show banner and sound
            // The LocationManager will handle in-app alerts separately
            completionHandler([.banner, .sound])
            
            // Post notification for other parts of app to handle
            NotificationCenter.default.post(
                name: .geofenceTriggeredInForeground,
                object: nil,
                userInfo: ["spotId": spotId, "geofenceEvent": geofenceEvent]
            )
        } else {
            // For other notifications (remote, etc.), show normally
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        
        _ = response.notification.request.content.userInfo
        
        handleNotificationTap(response)
        
        // Update badge count
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("Failed to clear badge: \(error)")
            }
        }
        
        completionHandler()
    }
    
    private func handleNotificationTap(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle geofence notifications
        if let spotId = userInfo["spotId"] as? String{
            LaunchManager.shared.launchAction = .navigateToSpotID(spotId)
            return
        }
        
        // Handle regular spot notifications
        if let spotId = userInfo["spotId"] as? String {
            NotificationCenter.default.post(
                name: .spotNotificationTapped,
                object: nil,
                userInfo: ["spotId": spotId]
            )
            return
        }
        
        // Handle test notifications or other types
        if let aps = userInfo["aps"] as? [String: AnyObject],
           let alert = aps["alert"] as? [String: AnyObject],
           let title = alert["title"] as? String {
            
            if title == "Test Notification" {
                // Handle test notification
                NotificationCenter.default.post(
                    name: .testNotificationTapped,
                    object: nil,
                    userInfo: userInfo
                )
            }
        }
    }

    // MARK: - Remote Notification Registration
    func application(_ application: UIApplication,
                    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
        // Convert token to string for debugging/logging
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs device token: \(tokenString)")
        
        // Store the token for potential future use
        UserDefaults.standard.set(tokenString, forKey: "APNSToken")
        
        // Post notification that device token was received
        NotificationCenter.default.post(
            name: .deviceTokenReceived,
            object: nil,
            userInfo: ["deviceToken": deviceToken, "tokenString": tokenString]
        )
    }

    func application(_ application: UIApplication,
                    didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
        
        NotificationCenter.default.post(
            name: .deviceTokenRegistrationFailed,
            object: nil,
            userInfo: ["error": error]
        )
    }
    
    // MARK: - Public Methods for LocationManager Coordination
    func requestNotificationPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                DispatchQueue.main.async {
                    completion(true)
                }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("Notification authorization error: \(error.localizedDescription)")
                    }
                    
                    DispatchQueue.main.async {
                        self.notificationPermissionGranted = granted
                        self.hasRequestedNotificationPermission = true
                        
                        if granted {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                        
                        completion(granted)
                    }
                }
            case .denied, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    completion(false)
                }
            @unknown default:
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
}

// MARK: - Notification Name Extensions
extension Notification.Name {
    static let applicationDidBecomeActive = Notification.Name("applicationDidBecomeActive")
    static let applicationWillResignActive = Notification.Name("applicationWillResignActive")
    static let applicationDidEnterBackground = Notification.Name("applicationDidEnterBackground")
    static let applicationWillEnterForeground = Notification.Name("applicationWillEnterForeground")
    
    static let geofenceTriggeredInForeground = Notification.Name("geofenceTriggeredInForeground")
    static let geofenceNotificationTapped = Notification.Name("geofenceNotificationTapped")
    static let testNotificationTapped = Notification.Name("testNotificationTapped")
    
    static let deviceTokenReceived = Notification.Name("deviceTokenReceived")
    static let deviceTokenRegistrationFailed = Notification.Name("deviceTokenRegistrationFailed")

}
