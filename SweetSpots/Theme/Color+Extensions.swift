//
//  Color+Extensions.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-20.
//

import SwiftUI

extension Color {
    static let themeBackground = Color(hex: "FFF8F0") // Creamy Off-White
    static let themePrimary = Color(hex: "342a7e")    // Purple
    static let themeAccent = Color(hex: "FF7066")     // Coral Accent (for highlights, secondary actions)
    static let themeTextPrimary = Color(hex: "6B4F4F")// Dark Warm Brown (for main text)
    static let themeTextSecondary = Color(hex: "A08585")// Muted Brown (for placeholders, secondary text)
    static let themeError = Color(hex: "E57373")       // Softer Red (for error messages)
    static let themeFieldBackground = Color.white     // Background for text fields
    static let themeFieldBorder = Color.themePrimary.opacity(0.4) // Border for text fields
    static let themeButtonText = Color.white          // Text color for primary buttons

    // Helper to initialize Color from a hex string
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
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
