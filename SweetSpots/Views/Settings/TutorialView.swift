//
//  TutorialView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-10-07.
//

import SwiftUI
import PDFKit

enum TutorialContext {
    case firstLaunch
    case fromSettings
}

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
    }
}

struct TutorialView: View {
    
    let context: TutorialContext
    let onDismiss: () -> Void
    
    @State private var selection = 0
    
    // List the names of your PDF files as they appear in your Assets
    let slideNames = ["Tutorial1", "Tutorial2","Tutorial3","Tutorial4","Tutorial5","Tutorial6","Tutorial7"]

    private var isLastSlide: Bool {
        selection == slideNames.count - 1
    }
    

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selection) {
                ForEach(slideNames.indices, id: \.self) { index in
                    let slideName = slideNames[index]
                    
                    if let url = Bundle.main.url(forResource: slideName, withExtension: "pdf") {
                        PDFKitView(url: url)
                            .tag(index)
                    } else {
                        Text("Could not load slide: \(slideName)")
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page)
            .ignoresSafeArea()

            // Dismiss Button - This logic is now correct
            HStack {
                Spacer()
                if context == .fromSettings || isLastSlide {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
            }
            .padding()
        }
    }
}
