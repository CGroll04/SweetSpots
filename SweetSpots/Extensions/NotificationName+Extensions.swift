//
//  NotificationName+Extensions.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-29.
//

import Foundation

extension Notification.Name {
    
    // Auth & User
    static let userDidSignIn = Notification.Name("userDidSignIn")
    static let userDidSignOut = Notification.Name("userDidSignOut")
    
    // Navigation & UI
    static let shouldNavigateToSpot = Notification.Name("shouldNavigateToSpot")
    static let handlePendingSharedURL = Notification.Name("handlePendingSharedURL")
    
    // App Health
    static let memoryWarningReceived = Notification.Name("memoryWarningReceived")
    static let spotNotificationTapped = Notification.Name("spotNotificationTapped")
    static let mapCameraDidChange = Notification.Name("mapCameraDidChange")

}
