//
//  TutorialKeys.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-11-08.
//

import Foundation
import SwiftUI

/// A central place to store the keys for all our tutorial @AppStorage flags.
struct TutorialKeys {
    
    static let hasSeenInfoButtonPDF = "hasSeenInfoButtonPDF"
    
    // Step 4: Add Spot (SpotListView)
    static let hasSeenAddSpotManualTip = "hasSeenAddSpotManualTip"
    
    // Step 5a & 5b: Address & Notify (AddSpotView)
    static let hasSeenAddSpotTips = "hasSeenAddSpotTips"
    
    // Step 6: Share Spot (SpotCardView)
    static let hasSeenShareSpotTip = "hasSeenShareSpotTip"
    
    // Step 7: Add Collection (CollectionView)
    static let hasSeenAddCollectionTip = "hasSeenAddCollectionTip"
    static let hasAddedFirstCollection = "hasAddedFirstCollection"
    
    // Step 8: Share Collection (CollectionView)
    static let hasSeenShareCollectionTip = "hasSeenShareCollectionTip"
    
    // Step 9: Map View (MapView)
    static let hasSeenMapViewTip = "hasSeenMapViewTip"
}

/// We also need our Notification name.
extension Notification.Name {
    /// Posted from ContentView after the "Info PDF" is dismissed.
    static let infoPDFDismissed = Notification.Name("infoPDFDismissed")
    static let userAddedFirstSpot = Notification.Name("userAddedFirstSpot")
    static let userAddedFirstCollection = Notification.Name("userAddedFirstCollection")
}
