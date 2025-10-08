//
//  TutorialView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-10-07.
//

import SwiftUI
import PDFKit

// A helper view to display a single PDF page
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: self.url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displaysPageBreaks = false
        pdfView.backgroundColor = .clear
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // No update needed
    }
}

struct TutorialView: View {
    // List the names of your PDF files as they appear in your Assets
    let slideNames = ["Tutorial1", "Tutorial2","Tutorial3","Tutorial4","Tutorial5","Tutorial6","Tutorial7"]
    
    // This closure is called when the view is dismissed
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // TabView creates the swipeable pages
            TabView {
                ForEach(slideNames, id: \.self) { slideName in
                    if let url = Bundle.main.url(forResource: slideName, withExtension: "pdf") {
                        PDFKitView(url: url)
                    } else {
                        Text("Could not load slide: \(slideName)")
                    }
                }
            }
            .tabViewStyle(.page)
            .ignoresSafeArea()

            // Dismiss Button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                    .background(Circle().fill(.white).padding(4))
            }
            .padding()
        }
    }
}
