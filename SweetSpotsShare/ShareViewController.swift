//
//  ShareViewController.swift
//  SweetSpotsShare
//
//  Created by Your Name on CurrentDate.
//

import UIKit
import Social // Though we are not using SLComposeServiceViewController
import UniformTypeIdentifiers // For UTType (iOS 14+)
import MobileCoreServices // For kUTType constants (older iOS fallback)

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // We don't want to show any UI from the extension itself for this simple case.
        // The view is still loaded, so we hide it.
        self.view.alpha = 0.0 // Make it transparent
        self.view.isUserInteractionEnabled = false // Prevent interaction
        
        extractSharedItemAndOpenApp()
    }

    private func extractSharedItemAndOpenApp() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            print("Share Extension: No input items found.")
            completeRequest(success: false)
            return
        }

        let urlTypeIdentifier: String
        let textTypeIdentifier: String

        if #available(iOS 14.0, *) {
            urlTypeIdentifier = UTType.url.identifier
            textTypeIdentifier = UTType.plainText.identifier
        } else {
            urlTypeIdentifier = kUTTypeURL as String
            textTypeIdentifier = kUTTypePlainText as String
        }
        
        // Prioritize URL type
        if itemProvider.hasItemConformingToTypeIdentifier(urlTypeIdentifier) {
            itemProvider.loadItem(forTypeIdentifier: urlTypeIdentifier, options: nil) { [weak self] (item, error) in
                DispatchQueue.main.async { // Ensure UI-related openURL is on main
                    guard let self = self else { return }
                    if let sharedURL = item as? URL {
                        print("Share Extension: Extracted URL: \(sharedURL.absoluteString)")
                        self.openMainApp(withSourceURL: sharedURL)
                    } else {
                        print("Share Extension: Failed to cast item to URL. Error: \(error?.localizedDescription ?? "Unknown error")")
                        self.completeRequest(success: false)
                    }
                }
            }
        }
        // Fallback to plain text if URL type not found (some apps share URLs as text)
        else if itemProvider.hasItemConformingToTypeIdentifier(textTypeIdentifier) {
            itemProvider.loadItem(forTypeIdentifier: textTypeIdentifier, options: nil) { [weak self] (item, error) in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let sharedText = item as? String, let potentialURL = URL(string: sharedText) {
                        // Basic check if the string is a plausible URL
                        if potentialURL.scheme != nil && (potentialURL.host != nil || potentialURL.pathComponents.count > 1) {
                             print("Share Extension: Extracted URL from text: \(potentialURL.absoluteString)")
                             self.openMainApp(withSourceURL: potentialURL)
                        } else {
                            print("Share Extension: Shared text is not a valid URL: \(sharedText)")
                            self.completeRequest(success: false) // Or handle as a note? For now, fail.
                        }
                    } else {
                        print("Share Extension: Failed to cast item to String or create URL from text. Error: \(error?.localizedDescription ?? "Unknown error")")
                        self.completeRequest(success: false)
                    }
                }
            }
        } else {
            print("Share Extension: Attachment does not conform to URL or Plain Text.")
            completeRequest(success: false)
        }
    }

    private func openMainApp(withSourceURL sourceURL: URL) {
        // Your app's custom URL scheme
        let appScheme = "sweetspotsapp"
        let actionPath = "addSpotFromShare"

        guard var components = URLComponents(string: "\(appScheme)://\(actionPath)") else {
            print("Share Extension: Could not create base app URL components.")
            completeRequest(success: false)
            return
        }
        
        // Add the sourceURL as a query parameter, properly percent-encoded
        components.queryItems = [
            URLQueryItem(name: "sourceURL", value: sourceURL.absoluteString)
        ]

        guard let appURL = components.url else {
            print("Share Extension: Could not create final app URL with query items.")
            completeRequest(success: false)
            return
        }
        
        print("Share Extension: Attempting to open appURL: \(appURL.absoluteString)")

        // Use a UIResponder extension to find UIApplication to open the URL
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                // Check if the app can open the URL (it should if URL scheme is registered)
                if application.canOpenURL(appURL) {
                    application.open(appURL, options: [:]) { [weak self] success in
                        print("Share Extension: Open URL success: \(success)")
                        self?.completeRequest(success: success)
                    }
                } else {
                    print("Share Extension: Application cannot open appURL: \(appURL.absoluteString)")
                    self.completeRequest(success: false)
                }
                return // Found UIApplication, no need to continue up the responder chain
            }
            responder = responder?.next
        }
        
        // Fallback if UIApplication instance could not be found (should be rare)
        print("Share Extension: Could not find UIApplication in responder chain.")
        completeRequest(success: false)
    }

    private func completeRequest(success: Bool) {
        // Call completeRequest to dismiss the share sheet and unblock the host app.
        // Passing an empty array of items means we don't want to return any modified content.
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
