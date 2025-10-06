// SharedSpotPayload.swift

import Foundation
import os.log

/// A data structure for encoding and decoding a single shared spot.
struct SharedSpotPayload: Codable, Equatable, Hashable {
    
    // MARK: - These are the only properties that should remain
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    var phoneNumber: String?
    var websiteURL: String?
    var notes: String?
    var sourceURL: String?
    
    // MARK: - Helper function (no changes needed)
    private static let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SharedSpotPayload")
    
    func resolvedCategory(default fallback: SpotCategory = .other) -> SpotCategory {
        if let resolved = SpotCategory(rawValue: category) {
            return resolved
        } else {
            Self.logger.warning("Unrecognized category string '\(self.category)' found in payload. Falling back to default.")
            return fallback
        }
    }
}
