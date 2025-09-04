//
//  DeepLinkRouter.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-08-25.
//


import Foundation
import SwiftUI
import FirebaseFirestore

final class NavigationCoordinator: ObservableObject {
    @Published var incomingShareURL: URL? = nil
    @Published var incomingSharedPayload: SharedSpotPayload? = nil
    @Published var incomingSharedCollectionPayload: SharedCollectionPayload? = nil
}

enum DeepLinkRouter {
    static let allowedHosts: Set<String> = ["sweetspotsshare.netlify.app", "localhost"]
    
    // --- ADD THESE TWO PROPERTIES ---
    private static var lastHandledURL: URL?
    private static var lastHandledTime: Date?
    // ---------------------------------

    static func handle(url: URL, navigation: NavigationCoordinator) {
        // --- ADD THIS DE-BOUNCING LOGIC ---
        // If we handled this exact URL in the last 2 seconds, ignore the duplicate call.
        if let lastURL = lastHandledURL, let lastTime = lastHandledTime,
           url == lastURL && Date().timeIntervalSince(lastTime) < 2.0 {
            print("ℹ️ DeepLinkRouter: Ignoring duplicate URL handled within the last 2 seconds.")
            return
        }
        // ------------------------------------
        
        print("✅ DeepLinkRouter: handle() was called with URL: \(url.absoluteString)")

        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            print("❌ DeepLinkRouter: Could not create URLComponents.")
            return
        }

        guard let host = comps.host, allowedHosts.contains(host) else {
            print("❌ DeepLinkRouter: Host check FAILED. Host was '\(comps.host ?? "nil")'.")
            return
        }
        print("  - Host check PASSED: '\(host)'")
        
        // --- MARK THE URL AS HANDLED ---
        // Do this *before* routing to prevent race conditions.
        lastHandledURL = url
        lastHandledTime = Date()
        // --------------------------------
        
        if comps.path.contains("/s/spot/") {
            handleSpotShare(url: url, components: comps, navigation: navigation)
        } else if comps.path.contains("/s/collection/") {
            handleCollectionShare(url: url, components: comps, navigation: navigation)
        } else {
            print("❌ DeepLinkRouter: Path check FAILED. Path was '\(comps.path)'.")
        }
    }
    
    // This helper function is correct
    private static func handleSpotShare(url: URL, components: URLComponents, navigation: NavigationCoordinator) {
        let pathComponents = components.path.split(separator: "/")
        guard pathComponents.count == 3, pathComponents[1] == "spot" else { return }
        let shareId = String(pathComponents[2])
        print("  - Found spot share ID: \(shareId)")
        
        Task {
            do {
                let db = Firestore.firestore()
                let doc = try await db.collection("shares").document(shareId).getDocument()
                let payload = try doc.data(as: SharedSpotPayload.self)
                
                print("✅ DeepLinkRouter: Successfully fetched and decoded SPOT payload.")
                await MainActor.run {
                    navigation.incomingSharedPayload = payload
                }
            } catch {
                print("❌ DeepLinkRouter: FAILED to fetch/decode spot payload for ID \(shareId): \(error)")
            }
        }
    }

    // This helper function is correct
    private static func handleCollectionShare(url: URL, components: URLComponents, navigation: NavigationCoordinator) {
        let pathComponents = components.path.split(separator: "/")
        guard pathComponents.count == 3, pathComponents[1] == "collection" else { return }
        let shareId = String(pathComponents[2])
        print("  - Found collection share ID: \(shareId)")
        
        Task {
            do {
                let db = Firestore.firestore()
                let doc = try await db.collection("shares").document(shareId).getDocument()
                let payload = try doc.data(as: SharedCollectionPayload.self)
                
                print("✅ DeepLinkRouter: Successfully fetched and decoded COLLECTION payload.")
                await MainActor.run {
                    navigation.incomingSharedCollectionPayload = payload
                }
            } catch {
                print("❌ DeepLinkRouter: FAILED to fetch/decode collection payload for ID \(shareId): \(error)")
            }
        }
    }
}
