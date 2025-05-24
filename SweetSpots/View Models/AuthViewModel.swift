//
//  AuthViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import SwiftUI
import FirebaseAuth // Make sure this is imported

class AuthViewModel: ObservableObject {
    @Published var userSession: FirebaseAuth.User?
    @Published var errorMessage: String?
    @Published var isSigningUp = false
    @Published var isLoading = false

    @Published var email = ""
    @Published var username = "" // << NEW: Add username property
    @Published var password = ""
    @Published var confirmPassword = ""

    private var authStateHandler: AuthStateDidChangeListenerHandle?

    init() {
        self.userSession = Auth.auth().currentUser
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async { // Ensure UI updates are on the main thread
                self?.userSession = user
            }
        }
    }

    deinit {
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }

    @MainActor
    func signIn() async {
        isLoading = true
        errorMessage = nil // Clear previous errors

        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            // Success is handled by the authStateHandler
            isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signUp() async {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { // << NEW: Validate username
            errorMessage = "Please enter a username."
            return
        }
        // You might want to add more username validation (length, characters, etc.)
        // For example:
        // guard username.count >= 3 else {
        //     errorMessage = "Username must be at least 3 characters long."
        //     return
        // }

        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        isLoading = true
        errorMessage = nil // Clear previous errors

        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            // User created successfully, now update their display name
            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = self.username
            try await changeRequest.commitChanges()

            // Success is also handled by authStateHandler, which will update userSession
            // If you need to do something immediately after displayName update and before
            // userSession is updated by the listener, you can do it here.
            // For instance, manually setting userSession if the listener is too slow,
            // though generally the listener should suffice.
            // self.userSession = authResult.user // Optionally set here if listener is slow

            self.isLoading = false

        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            // Clear fields on the main thread
            DispatchQueue.main.async {
                self.clearInputs() // Use the clearInputs method
                self.isSigningUp = false // Reset to sign-in mode
            }
        } catch let signOutError as NSError {
            // Ensure error message is set on the main thread
            DispatchQueue.main.async {
                self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
            }
        }
    }

    @MainActor // Ensure UI-bound properties are updated on main thread
    func clearInputs() {
        email = ""
        username = "" // << NEW: Clear username
        password = ""
        confirmPassword = ""
        errorMessage = nil
    }
}
