//
//  NotificationName+Extensions.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-29.
//

import Foundation

/// Defines custom notification names used throughout the application for loose coupling of components.
extension Notification.Name {
    
    // MARK: - Auth & User
    /// Posted when a user successfully signs in.
    static let userDidSignIn = Notification.Name("userDidSignIn")
    /// Posted when a user signs out.
    static let userDidSignOut = Notification.Name("userDidSignOut")
    
    // MARK: - Navigation & UI
    /// Posted to request a navigation to a specific spot detail view.
    /// The `userInfo` dictionary should contain a "spotId" (String).
    static let shouldNavigateToSpot = Notification.Name("shouldNavigateToSpot")
    /// Posted when a pending deep link URL needs to be handled by the UI.
    static let handlePendingSharedURL = Notification.Name("handlePendingSharedURL")
    /// Posted when the map's visible region or camera position changes.
    static let mapCameraDidChange = Notification.Name("mapCameraDidChange")
    
    
    // MARK: - App Lifecycle & Health
    /// A system notification posted when the app receives a memory warning.
    static let memoryWarningReceived = Notification.Name("memoryWarningReceived")
    /// A system notification posted when the app becomes active.
    static let applicationDidBecomeActive = Notification.Name("applicationDidBecomeActive")
    /// A system notification posted when the app is about to become inactive.
    static let applicationWillResignActive = Notification.Name("applicationWillResignActive")
    /// A system notification posted when the app enters the background.
    static let applicationDidEnterBackground = Notification.Name("applicationDidEnterBackground")
    /// A system notification posted when the app is about to enter the foreground.
    static let applicationWillEnterForeground = Notification.Name("applicationWillEnterForeground")
    
    // MARK: - Geofencing
    /// Posted when a geofence is triggered while the app is in the foreground.
    static let geofenceTriggeredInForeground = Notification.Name("geofenceTriggeredInForeground")
    /// Posted when the user taps on a geofence-triggered notification.
    /// The `userInfo` dictionary should contain a "spotId" (String).
    static let geofenceNotificationTapped = Notification.Name("geofenceNotificationTapped")
    
    
    // MARK: - Push Notifications
    /// Posted when the app successfully receives a push notification device token from APNS.
    static let deviceTokenReceived = Notification.Name("deviceTokenReceived")
    /// Posted when the app fails to register for a push notification device token.
    static let deviceTokenRegistrationFailed = Notification.Name("deviceTokenRegistrationFailed")
    static let testNotificationTapped = Notification.Name("testNotificationTapped")
    static let spotNotificationTapped = Notification.Name("spotNotificationTapped")
}
