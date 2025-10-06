// SharedCollectionPayload.swift

import Foundation

/// A data structure for encoding and decoding a shared collection and its spots.
struct SharedCollectionPayload: Codable, Equatable {

    // MARK: - These are the only properties that should remain
    var collectionName: String
    var collectionDescription: String?
    var emoji: String?
    var spots: [SharedSpotPayload]
}
