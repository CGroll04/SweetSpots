//
//  Utils.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-24.
//

import Foundation
import SwiftUI
import CoreLocation
import UserNotifications
import os.log


fileprivate let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "Utilities")


// MARK: - String Extensions
extension String {
    /// Returns a trimmed version of the string, removing leading and trailing whitespace and newlines.
    /// Returns nil if the trimmed string is empty.
    func trimmed() -> String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    /// Returns a trimmed version of the string, removing leading and trailing whitespace and newlines.
    /// Returns an empty string if the original string was only whitespace.
    func trimmedSafe() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Checks if the string is a valid email format
    var isValidEmail: Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: self)
    }
    
    /// Checks if the string is a valid URL format
    var isValidURL: Bool {
        return URL(string: self) != nil
    }
    
    /// Formats a string as a proper URL by adding https:// if no scheme is present
    var asProperURL: String {
        let trimmed = self.trimmedSafe()
        if trimmed.isEmpty { return trimmed }
        
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        } else {
            return "https://\(trimmed)"
        }
    }
    
    /// Returns the first few characters of a string for display purposes
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count <= length {
            return self
        } else {
            return String(self.prefix(length)) + trailing
        }
    }
}

// MARK: - Double Extensions
extension Double {
    /// Checks if two Double values are approximately equal within a tolerance
    func isApproximately(_ value: Double, tolerance: Double = 1.0) -> Bool {
        return abs(self - value) < tolerance
    }
    
    /// Rounds a Double to a specified number of decimal places
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
    
    /// Clamps a Double value between a minimum and maximum
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
    
    /// Formats a distance in meters to a human-readable string
    func formattedAsDistance() -> String {
        let formatter = LengthFormatter()
        formatter.numberFormatter.maximumFractionDigits = 1
        
        if Locale.current.measurementSystem == .us {
            let distanceInFeet = self * 3.28084
            if distanceInFeet < 528 {
                formatter.numberFormatter.maximumFractionDigits = 0
                return formatter.string(fromValue: distanceInFeet, unit: .foot)
            } else {
                let distanceInMiles = self / 1609.34
                return formatter.string(fromValue: distanceInMiles, unit: .mile)
            }
        } else {
            if self < 100 {
                formatter.numberFormatter.maximumFractionDigits = 0
                return formatter.string(fromValue: self, unit: .meter)
            } else {
                let distanceInKilometers = self / 1000
                return formatter.string(fromValue: distanceInKilometers, unit: .kilometer)
            }
        }
    }
}

// MARK: - Date Extensions
extension Date {
    /// Returns a human-readable relative time string (e.g., "2 hours ago", "Yesterday")
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Returns a formatted date string for display
    func formatted(_ style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
    
    /// Returns true if the date is today
    var isToday: Bool {
        return Calendar.current.isDateInToday(self)
    }
    
    /// Returns true if the date is yesterday
    var isYesterday: Bool {
        return Calendar.current.isDateInYesterday(self)
    }
}

// MARK: - Array Extensions
extension Array where Element: Identifiable {
    /// Safely removes an element by its ID
    mutating func removeByID(_ id: Element.ID) {
        self.removeAll { $0.id == id }
    }
    
    /// Finds an element by its ID
    func firstByID(_ id: Element.ID) -> Element? {
        return self.first { $0.id == id }
    }
}

extension Array {
    /// Returns the element at the specified index if it's within bounds, otherwise returns nil
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
    
    /// Chunks the array into smaller arrays of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - CLLocation Extensions
extension CLLocation {
    /// Calculates the distance to another coordinate
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let otherLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return self.distance(from: otherLocation)
    }
    
    /// Returns a formatted distance string to another location
    func formattedDistance(to otherLocation: CLLocation) -> String {
        let distance = self.distance(from: otherLocation)
        return distance.formattedAsDistance()
    }
}

// MARK: - Color Extensions
extension Color {
    /// Creates a Color from a hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            logger.warning("Invalid hex string provided: '\(hex)'. Defaulting to clear color.")
            (a, r, g, b) = (0, 0, 0, 0) // Changed to black with 0 alpha
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    /// Returns the hex string representation of the color
    var hexString: String {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - NumberFormatter Utilities
/// A container for shared, pre-configured NumberFormatter instances.
struct NumberFormatters {
    /// Standard formatter for distances (no decimals, 50-50000 range)
    static let distance: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 50
        formatter.maximum = 50000
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    /// Formatter for currency values
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }()
    
    /// Formatter for percentages
    static let percentage: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

// MARK: - Validation Utilities
struct ValidationUtils {
    /// Validates if a coordinate is within valid bounds
    static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        return latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
    }
    
    /// Validates if a notification radius is within acceptable bounds
    static func isValidNotificationRadius(_ radius: Double) -> Bool {
        return radius >= 50.0 && radius <= 50000.0
    }
    
    /// Validates username format (letters, numbers, underscores only)
    static func isValidUsername(_ username: String) -> Bool {
        let trimmed = username.trimmedSafe()
        
        // Length check
        guard trimmed.count >= 3 && trimmed.count <= 30 else { return false }
        
        // Character validation
        let validUsernameRegex = "^[a-zA-Z0-9_]+$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", validUsernameRegex)
        guard usernamePredicate.evaluate(with: trimmed) else { return false }
        
        // Additional rules
        guard !trimmed.hasPrefix("_") && !trimmed.hasSuffix("_") else { return false }
        guard trimmed.range(of: "[a-zA-Z]", options: .regularExpression) != nil else { return false }
        
        return true
    }
    
    /// Validates phone number format (basic validation)
    static func isValidPhoneNumber(_ phoneNumber: String) -> Bool {
        let trimmed = phoneNumber.trimmedSafe()
        guard !trimmed.isEmpty else { return true } // Optional field
        
        // Basic phone number regex (allows various formats)
        let phoneRegex = "^[\\+]?[1-9]?[0-9]{7,15}$"
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phonePredicate.evaluate(with: trimmed.replacingOccurrences(of: "\\D", with: "", options: .regularExpression))
    }
}

// MARK: - UI Utilities
struct UIUtils {
    /// Standard corner radius for the app
    static let cornerRadius: CGFloat = 12
    
    /// Standard shadow for cards
    static let cardShadow = Shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
    
    /// Standard padding values
    enum Padding {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    
    /// Haptic feedback helper
    static func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
    
    /// Opens a URL in the system browser
    static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            logger.warning("Attempted to open an invalid URL string: '\(urlString)'")
            return
        }
        UIApplication.shared.open(url)
    }

    
    /// Opens the app's settings page
    static func openAppSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsUrl)
    }
}

// MARK: - Notification Extensions
extension UNUserNotificationCenter {
    /// Requests notification permission with completion
    func requestPermission() async -> Bool {
        do {
            return try await requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Checks current notification authorization status
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationSettings()
        return settings.authorizationStatus
    }
}

// MARK: - Debug Utilities
struct DebugUtils {
    /// Only prints in debug builds
    static func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        #if DEBUG
        print(items, separator: separator, terminator: terminator)
        #endif
    }
    
    /// Logs with timestamp in debug builds
    static func logWithTimestamp(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.debugTimestamp.string(from: Date())
        print("[\(timestamp)] \(filename):\(line) \(function) - \(message)")
        #endif
    }
}

// MARK: - DateFormatter Extensions
extension DateFormatter {
    static let debugTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - App Constants
struct AppConstants {
    
    static let universalLinkHost = "sweetspotsshare.netlify.app"
    static let universalLinkPrefix = "/s"
    static let downloadPath = "/download"
    //TODO: App Store/TestFlight links
    static let appStoreURL = "https://apps.apple.com/app/idXXXXXXXXX"
    static let testFlightURL = "https://testflight.apple.com/join/XXXXXXXX"
    
    // Notification keys
    static let pendingSharedURLKey = "pendingSharedURL"
    
    // UserDefaults keys
    static let globalGeofencingEnabledKey = "globalGeofencingEnabled"
    
    static let pendingSharedSpotPayloadKey = "PendingSharedSpotPayload"
    
    // Validation constants
    static let minPasswordLength = 6
    static let minUsernameLength = 3
    static let maxUsernameLength = 30
    static let minNotificationRadius = 50.0
    static let maxNotificationRadius = 50000.0
    static let maxCollectionDescriptionLength = 280
    
    // App info
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
    
    static var fullVersionString: String {
        "\(appVersion) (\(buildNumber))"
    }
}

// MARK: - Custom Shadow Helper
struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - ViewModifier for applying consistent shadows
struct ShadowModifier: ViewModifier {
    let shadow: Shadow
    
    func body(content: Content) -> some View {
        content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

extension View {
    func shadow(_ shadow: Shadow) -> some View {
        modifier(ShadowModifier(shadow: shadow))
    }
}

extension Data {
    init?(base64URLEncoded: String) {
        var s = base64URLEncoded.replacingOccurrences(of: "-", with: "+")
                                 .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (s.count % 4)
        if pad < 4 { s.append(String(repeating: "=", count: pad)) }
        self.init(base64Encoded: s)
    }
}

extension Color {
    static func from(name: String) -> Color {
        switch name {
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "blue": return .blue
        case "red": return .red
        case "teal": return .teal
        case "brown": return .brown
        default: return .gray
        }
    }
}
