//
//  ShareSheet.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-25.
//

import SwiftUI

/// A SwiftUI view that wraps the UIKit `UIActivityViewController` for sharing content.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
