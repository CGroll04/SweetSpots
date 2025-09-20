//
//  AuthView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI
import os.log

/// View for handling user authentication: Sign In, Sign Up, and Forgot Password.
struct AuthView: View {
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "AuthView")
    @EnvironmentObject private var authViewModel: AuthViewModel

    // Local state to manage which authentication mode is active.
    enum AuthMode {
        case signIn, signUp, forgotPassword
    }
    @State private var currentMode: AuthMode = .signIn

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) { // Adjusted main spacing
                    logoAndTitleView()
                        .padding(.top, 30) // Reduced top padding

                    // Dynamically show the correct form based on currentMode
                    Group {
                        switch currentMode {
                        case .signIn:
                            signInForm()
                        case .signUp:
                            signUpForm()
                        case .forgotPassword:
                            forgotPasswordForm()
                        }
                    }
                    .padding(.horizontal) // Side padding for form blocks

                    errorAndSuccessMessageView()
                    
                    actionButtonView()

                    if currentMode != .forgotPassword {
                        toggleAuthModeButtonView()
                    }
                    
                    // "Back to Sign In" button for Forgot Password mode
                    if currentMode == .forgotPassword {
                        backToSignInButtonView()
                            .padding(.top, 10)
                    }
                }
                .padding() // Overall padding for the VStack content
            }
            .background(Color.themeBackground.ignoresSafeArea())
            .navigationTitle(navigationTitleForCurrentMode())
            .navigationBarTitleDisplayMode(.inline)
            .overlay { loadingOverlay() }
            .onDisappear {
                authViewModel.clearAllInputs()
            }
        }
    }

    // MARK: - Subviews for UI Sections
    private func logoAndTitleView() -> some View {
        VStack(spacing: 15) {
            Image("LaunchLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)

            Text("SweetSpots")
                .font(.system(.largeTitle, design: .rounded)).fontWeight(.bold)
                .foregroundStyle(Color.themeTextPrimary)
        }
    }

    private func signInForm() -> some View {
        VStack(spacing: 18) {
            AuthTextField(text: $authViewModel.email, placeholder: "Email Address", systemImage: "envelope.fill")
                .textContentType(.emailAddress).textInputAutocapitalization(.never).keyboardType(.emailAddress)
            AuthTextField(text: $authViewModel.password, placeholder: "Password", systemImage: "lock.fill", isSecureByDefault: true)
                .textContentType(.password)
            
            // Forgot Password Button for Sign In mode
            HStack {
                Spacer()
                Button("Forgot Password?") {
                    withAnimation { currentMode = .forgotPassword }
                    authViewModel.errorMessage = nil // Clear previous errors
                    authViewModel.successMessage = nil
                }
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(Color.themeAccent)
            }
            .padding(.top, -8) // Adjust to bring closer to password field
        }
    }

    private func signUpForm() -> some View {
        VStack(spacing: 18) {
            AuthTextField(text: $authViewModel.username, placeholder: "Username", systemImage: "person.fill")
                .textContentType(.username).textInputAutocapitalization(.never)
            AuthTextField(text: $authViewModel.email, placeholder: "Email Address", systemImage: "envelope.fill")
                .textContentType(.emailAddress).textInputAutocapitalization(.never).keyboardType(.emailAddress)
            // Password Field with live updates
            AuthTextField(text: $authViewModel.password, placeholder: "Password", systemImage: "lock.fill", isSecureByDefault: true)
                .textContentType(.newPassword)
                .onChange(of: authViewModel.password) { // Zero parameters
                    authViewModel.validatePasswordLive(newPasswordValue: authViewModel.password) // Re-access the value
                }

            PasswordRequirementsView() // New subview
                .padding(.top, -8)

            AuthTextField(text: $authViewModel.confirmPassword, placeholder: "Confirm Password", systemImage: "lock.fill", isSecureByDefault: true)
                .textContentType(.newPassword)
        }
    }

    private func forgotPasswordForm() -> some View {
        VStack(spacing: 18) {
            Text("Enter your email address below to receive a password reset link.")
                .font(.callout)
                .foregroundStyle(Color.themeTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            
            AuthTextField(text: $authViewModel.forgotPasswordEmail, placeholder: "Email Address", systemImage: "envelope.fill")
                .textContentType(.emailAddress).textInputAutocapitalization(.never).keyboardType(.emailAddress)
        }
    }

    @ViewBuilder
    private func errorAndSuccessMessageView() -> some View {
        if let message = authViewModel.errorMessage {
            Text(message)
                .foregroundStyle(Color.themeError)
                .font(.caption).fontWeight(.medium)
                .multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 5)
        } else if let message = authViewModel.successMessage {
            Text(message)
                .foregroundStyle(Color.green) // Or your theme's success color
                .font(.caption).fontWeight(.medium)
                .multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 5)
        }
    }

    private func actionButtonView() -> some View {
        Button {
            Task { // Perform action asynchronously
                switch currentMode {
                case .signIn:
                    logger.info("User initiated sign-in.")
                    await authViewModel.signIn()
                case .signUp:
                    logger.info("User initiated sign-up.")
                    await authViewModel.signUp()
                case .forgotPassword:
                    logger.info("User initiated password reset.")
                    await authViewModel.sendPasswordResetEmail()
                }
            }
        } label: {
            HStack {
                Text(buttonTextForCurrentMode())
                    .fontWeight(.semibold)
                if currentMode != .forgotPassword { // No arrow for "Send Reset Link"
                    Image(systemName: "arrow.right")
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 50) // Slightly shorter button
            .background(Color.themePrimary)
            .foregroundColor(Color.themeButtonText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.themePrimary.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal)
        .padding(.top, (authViewModel.errorMessage == nil && authViewModel.successMessage == nil) ? 15 : 5)
        .disabled(authViewModel.isLoading)
    }

    private func toggleAuthModeButtonView() -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentMode = (currentMode == .signIn) ? .signUp : .signIn
                authViewModel.clearAllInputs() // Clear inputs when switching main modes
            }
        } label: {
            Text(currentMode == .signIn ? "Don't have an account? Sign Up" : "Already have an account? Sign In")
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(Color.themeAccent)
        }
        .padding(.bottom, 20)
    }
    
    private func backToSignInButtonView() -> some View {
        Button {
            withAnimation { currentMode = .signIn }
            authViewModel.clearAllInputs()
        } label: {
            Text("Back to Sign In")
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(Color.themeAccent)
        }
    }

    @ViewBuilder
    private func loadingOverlay() -> some View {
        if authViewModel.isLoading {
            ZStack {
                Color.black.opacity(0.001).ignoresSafeArea().onTapGesture {} // Blocks taps
                ProgressView()
                    .scaleEffect(1.5).tint(Color.themePrimary)
                    .padding(30).background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    
    // MARK: - Helper Computed Properties for UI
    private func navigationTitleForCurrentMode() -> String {
        switch currentMode {
        case .signIn: return "Welcome Back"
        case .signUp: return "Create Account"
        case .forgotPassword: return "Reset Password"
        }
    }

    private func buttonTextForCurrentMode() -> String {
        switch currentMode {
        case .signIn: return "Sign In"
        case .signUp: return "Create Account"
        case .forgotPassword: return "Send Reset Link"
        }
    }
}
