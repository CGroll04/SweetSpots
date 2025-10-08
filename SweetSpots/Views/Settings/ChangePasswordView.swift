//
//  ChangePasswordView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-04.
//

import SwiftUI
import os.log

private struct RequirementRow: View {
    let description: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .secondary)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct SecureInputView: View {
    let title: String
    @Binding var text: String
    
    @FocusState.Binding var focusedField: ChangePasswordView.Field?
    let fieldCase: ChangePasswordView.Field

    @State private var isVisible = false

    var body: some View {
        HStack {
            if isVisible {
                TextField(title, text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: fieldCase) // Apply focus
            } else {
                SecureField(title, text: $text)
                    .focused($focusedField, equals: fieldCase) // Apply focus
            }
            
            Spacer()
            
            Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                .foregroundColor(.secondary)
                .onTapGesture {
                    isVisible.toggle()
                    // Immediately restore focus to this field
                    focusedField = fieldCase
                }
        }
    }
}
/// A view that allows an authenticated user to change their password.
struct ChangePasswordView: View {
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "ChangePasswordView")
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingSuccess = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isProcessing = false
    
    @FocusState private var focusedField: Field?
    enum Field: Hashable {
            case current, new, confirm
        }
    
    
    private var canSubmit: Bool {
        !currentPassword.isEmpty &&
        !newPassword.isEmpty &&
        newPassword == confirmPassword &&
        !isProcessing &&
        // This checks all requirements from the ViewModel
        AuthViewModel.PasswordRequirement.allCases.allSatisfy {
            authViewModel.passwordRequirementsMet[$0, default: false]
        }
    }
    
    var body: some View {
        Form {
            Section {
                SecureInputView(title: "Current Password", text: $currentPassword, focusedField: $focusedField, fieldCase: .current)
                    .textContentType(.password)
                
                SecureInputView(title: "New Password", text: $newPassword, focusedField: $focusedField, fieldCase: .new)
                    .textContentType(.newPassword)
                
                SecureInputView(title: "Confirm New Password", text: $confirmPassword, focusedField: $focusedField, fieldCase: .confirm)
                    .textContentType(.newPassword)
            } header: {
                Text("Change Password")
            } footer: {
                VStack(alignment: .leading, spacing: 5) {
                    // Main error message from the ViewModel
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    if !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword != confirmPassword {
                        Text("The new passwords do not match.")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Text("New password must meet the following requirements:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 5)
                    
                    ForEach(AuthViewModel.PasswordRequirement.allCases) { requirement in
                        RequirementRow(
                            description: requirement.description,
                            isMet: authViewModel.passwordRequirementsMet[requirement, default: false]
                        )
                    }
                }
                .padding(.top, 5)
            }
            
            Section {
                Button(action: handleChangePassword) {
                    HStack {
                        Spacer()
                        if isProcessing {
                            ProgressView()
                        } else {
                            Text("Update Password")
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: { dismiss() })
            }
        }
        .alert("Success", isPresented: $showingSuccess, actions: {
            Button("OK", role: .cancel) {
                dismiss()
            }
        }, message: {
            Text("Your password has been updated successfully.")
        })
        .onChange(of: newPassword) {
            authViewModel.validatePasswordLive(newPasswordValue: newPassword)
        }
        .onAppear {
            authViewModel.errorMessage = nil
            authViewModel.validatePasswordLive(newPasswordValue: newPassword)
        }
    }
    
    /// Validates inputs and calls the AuthViewModel to update the user's password.
    private func handleChangePassword() {
        // Pass local state to the ViewModel
        authViewModel.currentPassword = currentPassword
        
        Task {
            isProcessing = true
            await authViewModel.updatePassword(newPassword: newPassword, newPasswordConfirmation: confirmPassword)
            isProcessing = false
            
            // Show success alert only if there's no error
            if authViewModel.errorMessage == nil {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                self.showingSuccess = true
            } else {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }
}
