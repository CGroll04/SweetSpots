//
//  ShareableContent.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-26.
//

import Foundation

/// A generic, identifiable struct to hold content for the share sheet.
struct ShareableContent: Identifiable {
    let id = UUID()
    let text: String
    let url: URL
}
