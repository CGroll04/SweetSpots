//
//   TutorialPopoverContent.swift
//   SweetSpots
//
//   Created by Charlie Groll on 2025-11-08.
//

import SwiftUI

/// A reusable, styled view for all tutorial popovers.
struct TutorialPopoverContent: View {
    let title: String
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Title and Close Button
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    // --- FIX 3: Use adaptive primary color for text ---
                    .foregroundStyle(Color.primary)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .padding(8)
                        .background(.quaternary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // 2. Message
            Text(message)
                .font(.subheadline)
                // --- FIX 3: Use adaptive secondary color for text ---
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // --- FIX 2: Add more vertical padding ---
        .padding(.vertical, 24) // More vertical
        .padding(.horizontal, 20) // Keep horizontal
        // --- FIX 1: Condense horizontally ---
        .frame(maxWidth: 300) // Narrower
        // --- FIX 3: Use high-contrast system background ---
        .background(Color(UIColor.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}
