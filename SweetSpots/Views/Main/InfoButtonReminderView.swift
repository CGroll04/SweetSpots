//
//  InfoButtonReminderView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-11-06.
//

import SwiftUI

struct InfoButtonReminderView: View {
    /// This is a closure that the view will call when the user is ready to dismiss
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Use the same background as WelcomeView for consistency
            Color(hex: "8771D7") // Assumes you have the Color(hex:) extension
                .ignoresSafeArea()
            
            VStack(spacing: 25) {
                Spacer()
                Spacer()
                
                // Icon
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .padding()

                Text("Happy SweetSpotting")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text("You can find these tips and tutorials again at any time by tapping the info button.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineSpacing(5)

                Spacer()
                Spacer()

                // The button that triggers the 'onDismiss' action
                Button(action: onDismiss) {
                    Text("Got It")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundStyle(Color(hex: "8771D7")) // Purple text
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .padding(30)
        }
    }
}

#Preview {
    InfoButtonReminderView(onDismiss: {})
}
