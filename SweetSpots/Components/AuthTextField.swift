//
//  AuthTextField.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//
import SwiftUI

// MARK: - Reusable AuthTextField Component
struct AuthTextField: View {
    @Binding var text: String
    let placeholder: String
    let systemImage: String
    var isSecureByDefault: Bool = false // Renamed for clarity, was 'isSecure'

    @State private var isSecureTextEntry: Bool
    
    private var canToggleSecure: Bool
    
init(text: Binding<String>, placeholder: String, systemImage: String, isSecureByDefault: Bool = false) {
        self._text = text
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.isSecureByDefault = isSecureByDefault
        self._isSecureTextEntry = State(initialValue: isSecureByDefault) // Initialize local state
        self.canToggleSecure = isSecureByDefault // Field can only be toggled if it's a password-like field
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.themePrimary)
                .frame(width: 22, alignment: .center)
            Group {
                if isSecureTextEntry {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.themeTextSecondary.opacity(0.7)))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.themeTextSecondary.opacity(0.7)))
                }
            }
            .foregroundStyle(Color.themeTextPrimary)
            .font(.system(size: 16))
            
            if canToggleSecure {
                Button {
                    isSecureTextEntry.toggle()
                } label: {
                    Image(systemName: isSecureTextEntry ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(Color.themePrimary.opacity(0.7))
                        .frame(width: 22, height: 22) // Ensure consistent tap area
                }
                .padding(.trailing, 5) // Add a little space for the button
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: canToggleSecure ? 10 : 16)) // Adjust trailing padding if button is present        .background(Color.themeFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeFieldBorder, lineWidth: 1))
    }
}
