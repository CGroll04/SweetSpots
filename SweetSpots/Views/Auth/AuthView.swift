//
//  AuthView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//

import SwiftUI

/// View for handling user authentication: Sign In, Sign Up, and Forgot Password.
struct AuthView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    // Local state to manage which authentication mode is active.
    enum AuthMode {
        case signIn, signUp, forgotPassword
    }
    @State private var currentMode: AuthMode = .signIn
    
    // State for forgot password email, distinct from sign-in/sign-up email.
    // If we decide to re-use authViewModel.email, this isn't needed,
    // but a separate one is cleaner for a distinct flow.
    // For now, let's use the new `forgotPasswordEmail` from AuthViewModel.

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
                // Clear inputs when the AuthView disappears (e.g., user successfully logs in)
                // This ensures fields are fresh if the user logs out and returns.
                // If AuthView is always in the hierarchy and just hidden, this might not be desired.
                // But since it's swapped by ContentView, this is usually fine.
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
                .frame(width: 100, height: 100) // Slightly smaller logo
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
            
            // Display Password Requirements only if password field is not empty OR if in sign-up mode and focused
            // Or always show them in sign-up mode below password field.
            // Let's always show them in sign-up mode for clarity.
            PasswordRequirementsView() // New subview
                .padding(.top, -8) // Adjust spacing if needed

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
                case .signIn: await authViewModel.signIn()
                case .signUp: await authViewModel.signUp()
                case .forgotPassword: await authViewModel.sendPasswordResetEmail()
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

// MARK: - Reusable AuthTextField Component (No changes needed from your version)
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

// MARK: - New PasswordRequirementsView Subview
struct PasswordRequirementsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        // Only show if there's some password input or if requirements are defined
        // Or always show if it's the sign-up form
        if !AuthViewModel.PasswordRequirement.allCases.isEmpty { // Ensure requirements are defined
            VStack(alignment: .leading, spacing: 6) {
                ForEach(AuthViewModel.PasswordRequirement.allCases) { requirement in
                    HStack {
                        Image(systemName: authViewModel.passwordRequirementsMet[requirement, default: false] ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(authViewModel.passwordRequirementsMet[requirement, default: false] ? .green : .red)
                        Text(requirement.description)
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                        Spacer() // Push to the left
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10) // Optional: add a bit of horizontal padding
            // Optional: Add a subtle background or border
            // .background(Color.gray.opacity(0.05))
            // .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Preview
#Preview("Sign In") {
    AuthView().environmentObject(AuthViewModel())
}
