//
//  WebView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-03.
//

import SwiftUI
import WebKit

@MainActor
class WebViewStore: ObservableObject {
    let webView: WKWebView
    private var currentURL: URL?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.scrollView.bounces = true
    }
    
    func loadURLIfNeeded(_ url: URL) {
        // Only load if we haven't loaded this URL yet
        guard currentURL != url else { return }
        currentURL = url
        webView.load(URLRequest(url: url))
    }
}

struct WebView: UIViewRepresentable {
    // It now accepts a pre-made WKWebView and a URLRequest
    let webView: WKWebView
    let request: URLRequest
    
    @Binding var isLoading: Bool
    @Binding var loadingError: Error?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadingError: $loadingError)
    }

    func makeUIView(context: Context) -> WKWebView {
        // We no longer create the web view here. We just configure it.
        webView.navigationDelegate = context.coordinator
        
        // Load the initial request only once
        if webView.url == nil && !webView.isLoading {
            webView.load(request)
        }
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Remove the reload logic here to prevent reload loops
        // The WebView should maintain its state between updates
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate {
        private var isLoadingBinding: Binding<Bool>
        private var loadingErrorBinding: Binding<Error?>

        init(isLoading: Binding<Bool>, loadingError: Binding<Error?>) {
            self.isLoadingBinding = isLoading
            self.loadingErrorBinding = loadingError
        }
        
        // Helper to update state on the main thread
        private func updateState(isLoading: Bool, error: Error? = nil) {
            DispatchQueue.main.async {
                self.isLoadingBinding.wrappedValue = isLoading
                if let error = error {
                    // Don't report cancellation errors
                    if (error as NSError).code != NSURLErrorCancelled {
                        self.loadingErrorBinding.wrappedValue = error
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateState(isLoading: true, error: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateState(isLoading: false)
            injectMobileOptimizationCSS(into: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateState(isLoading: false, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateState(isLoading: false, error: error)
        }
        
        private func injectMobileOptimizationCSS(into webView: WKWebView) {
            let css = """
                var meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                var head = document.getElementsByTagName('head')[0];
                if (head) head.appendChild(meta);
                
                var style = document.createElement('style');
                style.textContent = `
                    body { 
                        -webkit-text-size-adjust: 100%; 
                        -webkit-touch-callout: none; 
                        -webkit-user-select: none; 
                        user-select: none;
                        margin: 0;
                        padding: 8px;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    }
                    img, video { 
                        max-width: 100%; 
                        height: auto; 
                    }
                    iframe {
                        max-width: 100%;
                        border: none;
                    }
                `;
                head.appendChild(style);
            """
            webView.evaluateJavaScript(css)
        }
    }
}

// MARK: - Custom Error (Good to have)
enum WebViewError: LocalizedError {
    case processTerminated
    var errorDescription: String? {
        switch self {
        case .processTerminated:
            return "Web content stopped unexpectedly."
        }
    }
}
