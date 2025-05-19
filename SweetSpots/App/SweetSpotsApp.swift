//
//  SweetSpotsApp.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import SwiftUI
import FirebaseCore
import UIKit
import UserNotifications // Import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate { // Add delegate
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    UNUserNotificationCenter.current().delegate = self // Set delegate
    return true
  }

  // Handle foreground notifications (optional, but good practice)
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    // Show alert, sound, badge even if app is in foreground
    completionHandler([.banner, .sound, .badge])
  }

  // Handle user tapping on a notification (optional)
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    // Handle the action, e.g., navigate to the specific spot
    let identifier = response.notification.request.identifier
    print("Notification tapped: \(identifier)")
    // You could post a NotificationCenter event here that your MainTabView or a coordinator listens to.
    completionHandler()
  }
}

@main
struct SweetSpotsApp: App {
  // register app delegate for Firebase setup
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate


  var body: some Scene {
    WindowGroup {
      NavigationView {
        ContentView()
      }
    }
  }
}


