//
//  SweetSpotsApp.swift
//  SweetSpots
//
//

import SwiftUI
import FirebaseCore
import FirebaseAppCheck
import UserNotifications
import os.log
import TipKit

fileprivate let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "AppLifecycle")

@main
struct SweetSpotsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()

    @StateObject private var navigationCoordinator = NavigationCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(navigationCoordinator)
                .onOpenURL { incomingURL in
                    DeepLinkRouter.handle(url: incomingURL, navigation: navigationCoordinator)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else {
                        return
                    }
                    logger.info("Continuing user activity with URL: \(url.absoluteString)")
                    DeepLinkRouter.handle(url: url, navigation: navigationCoordinator)
                }
                .task{
                    try? Tips.configure()
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
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "AppDelegate")
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        
        logger.debug("APP LAUNCH: Configuring App Check debug provider...")
        
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        
        FirebaseApp.configure()
        
        logger.debug("APP LAUNCH: Firebase configured.")
        
        setupNotificationCenter()
        setupRemoteNotifications(for: application)
        
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
        // Support: sweetspotsapp://addSpot?sourceURL=<encoded>
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
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            case .notDetermined:
                // Let your UI flow request permission at the right moment
                break
            case .denied, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - App Lifecycle
    func applicationDidBecomeActive(_ application: UIApplication) {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("Failed to clear badge: \(error)")
            }
        }
        NotificationCenter.default.post(name: .applicationDidBecomeActive, object: nil)
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        NotificationCenter.default.post(name: .applicationWillResignActive, object: nil)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        NotificationCenter.default.post(name: .applicationDidEnterBackground, object: nil)
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        NotificationCenter.default.post(name: .applicationWillEnterForeground, object: nil)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        
        // Foreground geofence notification
        if let geofenceEvent = userInfo["geofenceEvent"] as? String,
           let spotId = userInfo["spotId"] as? String {
            completionHandler([.banner, .sound])
            NotificationCenter.default.post(
                name: .geofenceTriggeredInForeground,
                object: nil,
                userInfo: ["spotId": spotId, "geofenceEvent": geofenceEvent]
            )
        } else {
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        handleNotificationTap(response)
        
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
        if let spotId = userInfo["spotId"] as? String {
            LaunchManager.shared.launchAction = .navigateToSpotID(spotId)
            return
        }
        
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
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs device token: \(tokenString)")
        UserDefaults.standard.set(tokenString, forKey: "APNSToken")
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
                DispatchQueue.main.async { completion(true) }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("Notification authorization error: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        self.notificationPermissionGranted = granted
                        self.hasRequestedNotificationPermission = true
                        if granted { UIApplication.shared.registerForRemoteNotifications() }
                        completion(granted)
                    }
                }
            case .denied, .provisional, .ephemeral:
                DispatchQueue.main.async { completion(false) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}
