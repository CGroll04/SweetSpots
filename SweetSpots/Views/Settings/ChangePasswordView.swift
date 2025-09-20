//
//  ChangePasswordView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-06-04.
//

import SwiftUI
import os.log

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
    @State private var errorMessage: String?
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case current, new, confirm
    }
    
    private var canSubmit: Bool {
        !currentPassword.isEmpty &&
        newPassword.count >= AppConstants.minPasswordLength &&
        newPassword == confirmPassword &&
        !isProcessing
    }
    
    var body: some View {
        Form {
            Section {
                SecureField("Current Password", text: $currentPassword)
                    .focused($focusedField, equals: .current)
                    .textContentType(.password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .new }
                
                SecureField("New Password", text: $newPassword)
                    .focused($focusedField, equals: .new)
                    .textContentType(.newPassword)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirm }
                
                SecureField("Confirm New Password", text: $confirmPassword)
                    .focused($focusedField, equals: .confirm)
                    .textContentType(.newPassword)
                    .submitLabel(.done)
                    .onSubmit {
                        if canSubmit {
                            handleChangePassword()
                        }
                    }
            } header: {
                Text("Change Password")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Text("Password must be at least \(AppConstants.minPasswordLength) characters.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .onAppear {
            focusedField = .current
        }
        .alert("Success", isPresented: $showingSuccess, actions: {
            Button("OK", role: .cancel) {
                dismiss()
            }
        }, message: {
            Text("Your password has been updated successfully.")
        })
    }
    
    /// Validates inputs and calls the AuthViewModel to update the user's password.
    private func handleChangePassword() {
        guard canSubmit else { return }
        
        logger.info("User initiated password change.")
        isProcessing = true
        errorMessage = nil
        
        Task {
            // Call the async function. It will complete when the network operation is done.
            await authViewModel.updatePassword(
                newPassword: newPassword,
                newPasswordConfirmation: confirmPassword
            )
            
            // After the await, the operation is finished. Now check the result
            // by inspecting the published properties on the authViewModel.
            await MainActor.run {
                self.isProcessing = false
                
                // Check if the ViewModel has published an error message.
                if let vmError = authViewModel.errorMessage {
                    // --- Failure Path ---
                    self.logger.error("Password change failed: \(vmError)")
                    self.errorMessage = vmError
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                } else {
                    // --- Success Path ---
                    // If no error message is set, the operation was successful.
                    self.logger.info("Password change successful.")
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    self.showingSuccess = true
                }
            }
        }
    }
}
