//
//  AuthView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss // Not currently used, but good to keep if needed

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Logo and Title
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.themePrimary, Color.themeAccent]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.themePrimary.opacity(0.25), radius: 8, x: 0, y: 4)

                        Text("SweetSpots")
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.themeTextPrimary)
                    }
                    .padding(.top, 50)

                    // Form Fields
                    VStack(spacing: 18) {
                        // << NEW: Username field appears if signing up >>
                        if authViewModel.isSigningUp {
                            AuthTextField(
                                text: $authViewModel.username,
                                placeholder: "Username",
                                systemImage: "person.fill" // Or "at" or "person.circle.fill"
                            )
                            .textContentType(.username) // Good for autofill hints
                            .textInputAutocapitalization(.never)
                        }
                        
                        AuthTextField(
                            text: $authViewModel.email,
                            placeholder: "Email Address",
                            systemImage: "envelope.fill"
                        )
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                        AuthTextField(
                            text: $authViewModel.password,
                            placeholder: "Password",
                            systemImage: "lock.fill",
                            isSecure: true
                        )
                        .textContentType(authViewModel.isSigningUp ? .newPassword : .password) // Hint for password managers

                        if authViewModel.isSigningUp {
                            AuthTextField(
                                text: $authViewModel.confirmPassword,
                                placeholder: "Confirm Password",
                                systemImage: "lock.fill",
                                isSecure: true
                            )
                            .textContentType(.newPassword) // Hint for password managers
                        }
                    }
                    .padding(.horizontal)

                    // Error Message
                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(Color.themeError)
                            .font(.caption)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }

                    // Action Button
                    Button {
                        Task {
                            if authViewModel.isSigningUp {
                                await authViewModel.signUp()
                            } else {
                                await authViewModel.signIn()
                            }
                        }
                    } label: {
                        HStack {
                            Text(authViewModel.isSigningUp ? "Create Account" : "Sign In")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color.themePrimary)
                        .foregroundColor(Color.themeButtonText)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color.themePrimary.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal)
                    .padding(.top, authViewModel.errorMessage == nil && !authViewModel.isSigningUp ? 10 : (authViewModel.errorMessage == nil && authViewModel.isSigningUp ? 10 : 0) ) // Adjusted logic for padding
                    .disabled(authViewModel.isLoading)

                    // Toggle Auth Mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            authViewModel.isSigningUp.toggle()
                            authViewModel.clearInputs() // This will also clear the username field
                        }
                    } label: {
                        Text(authViewModel.isSigningUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.themeAccent)
                    }
                    .padding(.bottom, 20)
                }
                .padding()
            }
            .background(Color.themeBackground.ignoresSafeArea())
            .navigationTitle(authViewModel.isSigningUp ? "Create Account" : "Welcome Back")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if authViewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.1).ignoresSafeArea()
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.themePrimary)
                    }
                    .background(.ultraThinMaterial.opacity(0.8))
                }
            }
        }
    }
}

// MARK: - Reusable Components
// AuthTextField remains the same as previously defined
private struct AuthTextField: View {
    @Binding var text: String
    let placeholder: String
    let systemImage: String
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.themePrimary)
                .frame(width: 22, alignment: .center)

            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.themeTextSecondary))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.themeTextSecondary))
                }
            }
            .foregroundStyle(Color.themeTextPrimary)
            .font(.system(size: 16))
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Color.themeFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themeFieldBorder, lineWidth: 1)
        )
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
        .onAppear {
        }
}
