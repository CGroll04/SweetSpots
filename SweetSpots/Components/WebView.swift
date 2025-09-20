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

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.scrollView.bounces = true
    }
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView
    let request: URLRequest
    
    @Binding var isLoading: Bool
    @Binding var loadingError: Error?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadingError: $loadingError)
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        
        if webView.url == nil && !webView.isLoading {
            webView.load(request)
        }
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate {
        private var isLoadingBinding: Binding<Bool>
        private var loadingErrorBinding: Binding<Error?>
        private var isInitialLoad = true

        init(isLoading: Binding<Bool>, loadingError: Binding<Error?>) {
            self.isLoadingBinding = isLoading
            self.loadingErrorBinding = loadingError
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow the very first request to load the page.
            if isInitialLoad {
                isInitialLoad = false
                decisionHandler(.allow)
                return
            }

            // After the initial load, only allow navigations that the user explicitly clicked on.
            // This blocks the automatic JavaScript redirects that cause the reload loop.
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateState(isLoading: true, error: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateState(isLoading: false)
            // Bonus: I've re-enabled text selection in the CSS injection.
            injectMobileOptimizationCSS(into: webView)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateState(isLoading: false, error: error)
        }
        
        private func updateState(isLoading: Bool, error: Error? = nil) {
            DispatchQueue.main.async {
                self.isLoadingBinding.wrappedValue = isLoading
                if let error = error, (error as NSError).code != NSURLErrorCancelled {
                    self.loadingErrorBinding.wrappedValue = error
                }
            }
        }
        
        private func injectMobileOptimizationCSS(into webView: WKWebView) {
            let script = """
                var meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                var head = document.getElementsByTagName('head')[0];
                if (head) { head.appendChild(meta); }

                var style = document.createElement('style');
                style.textContent = `
                    body {
                        -webkit-text-size-adjust: 100%;
                        -webkit-touch-callout: none;
                        -webkit-user-select: auto; /* Allows user to select text */
                        user-select: auto;
                    }
                `;
                if (head) { head.appendChild(style); }
            """
            webView.evaluateJavaScript(script)
        }
    }
}
