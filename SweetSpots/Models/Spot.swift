//
//  Spot.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import FirebaseFirestore
import CoreLocation

struct Spot: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var userId: String?
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var sourceURL: String?
    @ServerTimestamp var createdAt: Timestamp? = Timestamp()
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    static func == (lhs: Spot, rhs: Spot) -> Bool {
        lhs.id == rhs.id
    }
}
