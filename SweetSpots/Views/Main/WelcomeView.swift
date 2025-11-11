//
//  WelcomeView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-11-06.
//

import SwiftUI

struct WelcomeView: View {
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Background Color
            Color(red: 0.53, green: 0.44, blue: 0.84) // A nice purple, adjust RGB as needed
                .ignoresSafeArea()
            
            VStack(spacing: 25) {
                Spacer() // Pushes content towards the center/top
                Spacer()
                
                Image("LaunchLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100) // Adjust size as needed
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 5)
                    .padding(.bottom, 20) // Add some space below the icon

                Text("Welcome to\nSweetSpots") // Use \n for line break
                    .font(.largeTitle) // Or a custom font if you have one
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(10) // Adjust line spacing if needed to match design

                Text("Turn social media discoveries into\nreal-world experiences")
                    .font(.headline) // Or a custom font
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .lineSpacing(5) // Adjust line spacing if needed
                
                Spacer() // Pushes content towards the center/bottom
                Spacer() // Add another Spacer to push the button lower, similar to your design

                // The button that triggers the 'onDismiss' action
                Button(action: onDismiss) {
                    Text("Get Started")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white) // White background for the button
                        .foregroundStyle(Color(red: 0.53, green: 0.44, blue: 0.84)) // Purple text
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20) // Add some padding from the bottom edge
            }
            .padding(30)
        }
    }
}

#Preview {
    WelcomeView(onDismiss: {})
}
