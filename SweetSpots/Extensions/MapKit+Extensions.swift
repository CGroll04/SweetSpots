//
//  MapKit+Extensions.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//

import SwiftUI
import MapKit

extension MKLocalSearchCompletion: @retroactive Identifiable {
    public var id: String {
        "\(title)-\(subtitle)"
    }
    
    var fullDescription: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}

extension MKMapRect {
    init(containing coordinates: [CLLocationCoordinate2D]) {
        self = coordinates.reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate)
            return rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
    }
}
