//
//  AuthViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import os.log

enum AuthContext {
    case signIn, passwordChange
}

@MainActor
/// Manages all user authentication flows, including sign in, sign up, password management, and session state.
class AuthViewModel: ObservableObject {
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "AuthViewModel")
    
    // MARK: - Published State
    @Published var userSession: FirebaseAuth.User?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // MARK: - User Input Fields
    @Published var email = ""
    @Published var username = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var currentPassword = ""
    @Published var forgotPasswordEmail = ""
    
    // MARK: - Form Validation Computed Properties
    var canSignIn: Bool {
        guard let trimmedEmail = email.trimmed() else { return false }
        return !trimmedEmail.isEmpty &&
               !password.isEmpty &&
               trimmedEmail.isValidEmail &&
               !isLoading
    }

    var canSignUp: Bool {
        guard let trimmedUsername = username.trimmed(),
              let trimmedEmail = email.trimmed() else { return false }
        
        return !trimmedUsername.isEmpty &&
               !trimmedEmail.isEmpty &&
               !password.isEmpty &&
               !confirmPassword.isEmpty &&
               ValidationUtils.isValidUsername(username) &&
               trimmedEmail.isValidEmail &&
               password == confirmPassword &&
               PasswordRequirement.allCases.allSatisfy { passwordRequirementsMet[$0, default: false] } &&
               !isLoading
    }

    var canResetPassword: Bool {
        guard let trimmedEmail = forgotPasswordEmail.trimmed() else { return false }
        return !trimmedEmail.isEmpty &&
               trimmedEmail.isValidEmail &&
               !isLoading
    }

    // MARK: - Password Requirements
    /// Defines the requirements for a valid user password.
    enum PasswordRequirement: CaseIterable, Identifiable {
        case length
        case hasUppercase
        case hasLowercase
        case hasNumber
        case hasSpecialChar
        
        var id: Self { self }

        var description: String {
            switch self {
            case .length: return "At least \(AuthViewModel.minPasswordLengthGlobal) characters"
            case .hasUppercase: return "At least one uppercase letter"
            case .hasLowercase: return "At least one lowercase letter"
            case .hasNumber: return "At least one number"
            case .hasSpecialChar: return "At least one special character (e.g., !@#$%)"
            }
        }
        
        func isMet(for password: String) -> Bool {
            switch self {
            case .length:
                return password.count >= AuthViewModel.minPasswordLengthGlobal
            case .hasUppercase:
                return password.range(of: "[A-Z]", options: .regularExpression) != nil
            case .hasLowercase:
                return password.range(of: "[a-z]", options: .regularExpression) != nil
            case .hasNumber:
                return password.range(of: "[0-9]", options: .regularExpression) != nil
            case .hasSpecialChar:
                return password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
            }
        }
    }

    @Published var passwordRequirementsMet: [PasswordRequirement: Bool] = [:]
    
    // MARK: - Constants
    nonisolated static let minPasswordLengthGlobal = 6
    let minUsernameLength = 3
    let minPasswordLength = minPasswordLengthGlobal
    private let db = Firestore.firestore()

    // MARK: - Private Properties
    private var authStateHandler: AuthStateDidChangeListenerHandle?

    // MARK: - Initialization & Deinitialization
    init() {
        self.userSession = Auth.auth().currentUser
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.userSession = user
            if user == nil {
                self?.clearSensitiveInputs()
            }
        }
        updatePasswordRequirements(for: password)
    }

    deinit {
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }
    
    // MARK: - Live Password Validation
    func validatePasswordLive(newPasswordValue: String) {
        self.password = newPasswordValue
        updatePasswordRequirements(for: newPasswordValue)
    }
    
    func updatePasswordRequirements(for passwordToCheck: String) {
        var newRequirementsMet: [PasswordRequirement: Bool] = [:]
        
        for requirement in PasswordRequirement.allCases {
            newRequirementsMet[requirement] = requirement.isMet(for: passwordToCheck)
        }

        if newRequirementsMet != self.passwordRequirementsMet {
            self.passwordRequirementsMet = newRequirementsMet
        }
    }
    
    // MARK: - Account Deletion
    /// This is the main function called from your SettingsView.
    func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        
        guard let user = self.userSession else {
            self.errorMessage = "No user is currently signed in."
            self.isLoading = false
            return
        }
        
        do {
            // STEP 1: Delete all user data from Firestore first.
            try await deleteAllUserData(for: user)
            logger.info("Successfully deleted all Firestore data for UID: \(user.uid)")
            
            // STEP 2: Only after data is gone, delete the authentication user.
            try await user.delete()
            logger.info("Successfully deleted user account for UID: \(user.uid)")
            
        } catch {
            logger.error("Failed during account deletion process: \(error.localizedDescription)")
            // Provide a helpful message if re-authentication is needed
            let nsError = error as NSError
            if nsError.domain == AuthErrorDomain, nsError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                self.errorMessage = "This is a sensitive action. Please sign out and sign back in before deleting your account."
            } else {
                self.errorMessage = "Failed to delete account. Please check your connection and try again."
            }
        }
        
        isLoading = false
    }
    
    /// Helper function to delete all Firestore data for a given user.
    private func deleteAllUserData(for user: User) async throws {
        let uid = user.uid
        let batch = db.batch()

        // 1. Delete all of the user's spots
        let spotsRef = db.collection("users").document(uid).collection("spots")
        let spotsSnapshot = try await spotsRef.getDocuments()
        spotsSnapshot.documents.forEach { doc in
            batch.deleteDocument(doc.reference)
        }
        
        // 2. Delete all of the user's collections
        let collectionsRef = db.collection("users").document(uid).collection("spotCollections")
        let collectionsSnapshot = try await collectionsRef.getDocuments()
        collectionsSnapshot.documents.forEach { doc in
            batch.deleteDocument(doc.reference)
        }
        
        // 3. Delete the user's username reservation
        if let username = user.displayName?.lowercased() {
            let usernameRef = db.collection("usernames").document(username)
            batch.deleteDocument(usernameRef)
        }
        
        // 4. Commit all deletions as a single batch
        try await batch.commit()
    }

    // MARK: - Authentication Operations
    /// Attempts to sign in the user with the provided email and password.
    func signIn() async {
        guard validateSignInInputs() else { return }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            guard let trimmedEmail = email.trimmed() else {
                self.errorMessage = "Please enter a valid email address."
                isLoading = false
                return
            }
            _ = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password)
            clearSensitiveInputsOnSuccess()
        } catch {
            logger.error("Sign in failed: \(error.localizedDescription)")
            self.errorMessage = mapAuthError(error)
        }
        isLoading = false
    }

    /// Attempts to create a new user account, reserve their username, and sign them in.
    func signUp() async {
        guard validateSignUpInputs() else { return }

        let allLiveRequirementsMet = PasswordRequirement.allCases.allSatisfy { requirement in
            passwordRequirementsMet[requirement, default: false]
        }
        guard allLiveRequirementsMet else {
            errorMessage = "Password does not meet all requirements."
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        guard let originalTrimmedUsername = username.trimmed(),
              let trimmedEmail = email.trimmed() else {
            self.errorMessage = "Please enter valid username and email."
            self.isLoading = false
            return
        }
        
        let firestoreUsernameKey = originalTrimmedUsername.lowercased()

        guard !firestoreUsernameKey.isEmpty else {
            logger.fault("Firestore username key is empty after trimming/lowercasing. Username was: '\(self.username)'")
            self.errorMessage = "Username format is invalid. Please try a different username."
            self.isLoading = false
            return
        }
        
        var authResult: AuthDataResult?

        do {
            let isUsernameAvailable = await checkUsernameAvailability(firestoreUsernameKey)
            guard isUsernameAvailable else {
                self.errorMessage = "This username is already taken. Please choose another."
                self.isLoading = false
                return
            }

            authResult = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            guard let createdUser = authResult?.user else {
                throw NSError(domain: "AuthViewModel.SignUp", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to get user data after creation."])
            }
            
            let changeRequest = createdUser.createProfileChangeRequest()
            changeRequest.displayName = originalTrimmedUsername
            try await changeRequest.commitChanges()

            do {
                try await reserveUsername(firestoreUsernameKey, userId: createdUser.uid)
            } catch {
                logger.fault("Failed to reserve username '\(firestoreUsernameKey)' for user \(createdUser.uid) AFTER Auth user creation. Error: \(error)")
                
                logger.warning("Attempting to delete orphaned Firebase Auth user \(createdUser.uid)...")
                do {
                    try await createdUser.delete()
                    logger.info("Successfully deleted orphaned Firebase Auth user \(createdUser.uid)")
                } catch let deleteError {
                    logger.fault("CRITICAL: Failed to delete orphaned Firebase Auth user \(createdUser.uid). Manual cleanup may be required. Delete Error: \(deleteError)")
                }
                
                if let firestoreError = error as NSError?,
                   firestoreError.domain == FirestoreErrorDomain,
                   firestoreError.code == FirestoreErrorCode.alreadyExists.rawValue {
                    self.errorMessage = "This username was taken just before you finished signing up. Please try a different username."
                } else if let nsError = error as NSError?, nsError.domain == "AuthViewModel.ReserveUsername", nsError.code == 1001 {
                    self.errorMessage = "Username format is invalid (internal error RU)."
                } else {
                    self.errorMessage = "Could not complete sign up. Error reserving username."
                }
                self.isLoading = false
                return
            }
            
            clearSensitiveInputsOnSuccess()

        } catch let outerError {
            logger.error("Error during sign up process (outer catch): \(outerError.localizedDescription)")
            self.errorMessage = mapAuthError(outerError)
        }
        isLoading = false
    }

    /// Signs out the current user and clears all input fields.
    func signOut() {
        do {
            try Auth.auth().signOut()
            logger.info("User successfully signed out.")
        } catch let signOutError {
            logger.error("Sign out failed: \(signOutError.localizedDescription)")
            self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
        }
        clearAllInputs() // Clear inputs regardless of success or failure
    }

    func sendPasswordResetEmail() async {
        guard let trimmedEmail = forgotPasswordEmail.trimmed() else {
            self.errorMessage = "Please enter your email address."
            return
        }
        guard trimmedEmail.isValidEmail else {
            self.errorMessage = "Please enter a valid email address."
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
            self.successMessage = "If an account exists for \(trimmedEmail), a password reset email has been sent. Please check your inbox (and spam folder)."
            self.forgotPasswordEmail = ""
        } catch {
            self.errorMessage = mapAuthError(error)
        }
        isLoading = false
    }
    
    // MARK: - Username Management
    private func checkUsernameAvailability(_ usernameKeyForFirestore: String) async -> Bool {
        guard !usernameKeyForFirestore.isEmpty else {
            logger.error("Received an empty usernameKeyForFirestore. This indicates a logic flaw in the caller.")
            self.errorMessage = "Internal error verifying username (CUA)."
            return false
        }

        do {
            let document = try await db.collection("usernames").document(usernameKeyForFirestore).getDocument()
            return !document.exists
        } catch {
            logger.error("Error checking username availability: \(error.localizedDescription)")
            self.errorMessage = "Could not verify username. Please try again."
            return false
        }
    }

    private func reserveUsername(_ usernameKeyForFirestore: String, userId: String) async throws {
        guard !usernameKeyForFirestore.isEmpty else {
            logger.error("Received an empty usernameKeyForFirestore. This indicates a logic flaw in the caller.")
            throw NSError(domain: "AuthViewModel.ReserveUsername", code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Attempted to reserve an empty username."])
        }

        do {
            try await db.collection("usernames").document(usernameKeyForFirestore).setData(["userId": userId])
        } catch {
            logger.error("Failed to reserve username '\(usernameKeyForFirestore)' in Firestore: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Profile Management
    /// Updates the current user's password after re-authenticating them.
    func updatePassword(newPassword: String, newPasswordConfirmation: String) async {
        guard validatePasswordChangeInputs(newPassword: newPassword, newPasswordConfirmation: newPasswordConfirmation) else { return }
        
        guard let user = self.userSession, let userEmail = user.email else {
            self.errorMessage = "User session or email not found. Please sign in again."
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        let credential = EmailAuthProvider.credential(withEmail: userEmail, password: currentPassword)
        
        do {
            try await user.reauthenticate(with: credential)
            guard currentPassword != newPassword else {
                self.errorMessage = "Your new password cannot be the same as your current password."
                self.isLoading = false
                return
            }
            
            try await user.updatePassword(to: newPassword)
            
            self.successMessage = "Password updated successfully."
            clearPasswordFields()
        } catch {
            logger.error("Failed to update password: \(error.localizedDescription)")
            self.errorMessage = mapAuthError(error, context: .passwordChange)
        }
        isLoading = false
    }
    
    // MARK: - Input Validation
    private func validateSignInInputs() -> Bool {
        guard let trimmedEmail = email.trimmed(), !password.isEmpty else {
            errorMessage = "Please enter both email and password."
            return false
        }
        guard trimmedEmail.isValidEmail else {
            errorMessage = "Please enter a valid email address."
            return false
        }
        return true
    }

    private func validateSignUpInputs() -> Bool {
        guard let trimmedUsername = username.trimmed() else {
            errorMessage = "Please enter a username."
            return false
        }
        
        guard trimmedUsername.count >= minUsernameLength else {
            errorMessage = "Username must be at least \(minUsernameLength) characters long."
            return false
        }
        
        guard ValidationUtils.isValidUsername(username) else {
            errorMessage = "Username can only contain letters, numbers, and underscores."
            return false
        }
        
        guard let trimmedEmail = email.trimmed() else {
            errorMessage = "Please enter an email address."
            return false
        }
        guard trimmedEmail.isValidEmail else {
            errorMessage = "Please enter a valid email address."
            return false
        }
        guard !password.isEmpty else {
            errorMessage = "Please enter a password."
            return false
        }
        
        var unmetRequirements: [String] = []
        for requirement in PasswordRequirement.allCases {
            if !(passwordRequirementsMet[requirement, default: false]) {
                unmetRequirements.append(requirement.description)
            }
        }
        
        guard unmetRequirements.isEmpty else {
            errorMessage = "Password requirements not met: " + unmetRequirements.joined(separator: ", ")
            return false
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return false
        }
        return true
    }

    
    private func validatePasswordChangeInputs(newPassword: String, newPasswordConfirmation: String) -> Bool {
        guard !currentPassword.isEmpty else { // Use isEmpty for clarity
            errorMessage = "Please enter your current password to continue."
            return false
        }

        let allRequirementsMet = PasswordRequirement.allCases.allSatisfy { $0.isMet(for: newPassword) }
        guard allRequirementsMet else {
            errorMessage = "Your new password does not meet all the requirements."
            return false
        }
        
        guard newPassword == newPasswordConfirmation else {
            errorMessage = "The new passwords do not match."
            return false
        }
        
        return true
    }

    // MARK: - Input Clearing
    @MainActor private func clearSensitiveInputs() {
        password = ""
        confirmPassword = ""
        currentPassword = ""
    }

    @MainActor private func clearSensitiveInputsOnSuccess() {
        email = ""
        username = ""
        clearSensitiveInputs()
    }

    @MainActor func clearAllInputs() {
        email = ""
        username = ""
        forgotPasswordEmail = ""
        clearSensitiveInputs()
        errorMessage = nil
        successMessage = nil
        updatePasswordRequirements(for: "")
    }
    
    @MainActor private func clearPasswordFields() {
        currentPassword = ""
        password = ""
        confirmPassword = ""
    }

    // MARK: - Error Mapping
    private func mapAuthError(_ error: Error, context: AuthContext = .signIn) -> String {
        logger.error("Mapping auth error: \(error.localizedDescription) | Domain: \((error as NSError).domain), Code: \((error as NSError).code)")
        var friendlyMessage = "Sorry, we couldn't complete this action. Please check your connection and try again."
        let nsError = error as NSError

        if nsError.domain == AuthErrorDomain {
            if let errorCode = AuthErrorCode(rawValue: nsError.code) {
                switch errorCode {
                case .invalidCredential, .wrongPassword:
                   // If we're changing a password, the error is the current password.
                   if context == .passwordChange {
                       return "The current password you entered is incorrect."
                   } else {
                       // Otherwise, it's the standard login error.
                       return "Incorrect email or password. Please try again."
                   }
                case .invalidEmail:
                    friendlyMessage = "The email address is badly formatted. Please check and try again."
                case .emailAlreadyInUse:
                    friendlyMessage = "This email address is already in use."
                case .weakPassword:
                    friendlyMessage = "Password must be at least \(minPasswordLength) characters."
                case .userNotFound:
                    friendlyMessage = "No account found with this email. Would you like to sign up?"
                case .userDisabled:
                    friendlyMessage = "This account has been disabled. Please contact support."
                case .networkError:
                    friendlyMessage = "A network error occurred. Please check your internet connection and try again."
                case .requiresRecentLogin:
                    friendlyMessage = "This action requires you to have signed in recently. Please sign out and sign back in."
                case .tooManyRequests:
                    friendlyMessage = "We've detected unusual activity. Please try again later."
                case .operationNotAllowed:
                    friendlyMessage = "Sign-in with email and password is not currently enabled. Please contact support."
                case .keychainError:
                    friendlyMessage = "A secure storage error occurred. Please try again. If the problem persists, restarting your device may help."
                case .internalError:
                    friendlyMessage = "An unexpected internal error occurred. Please try again later."
                case .credentialAlreadyInUse:
                    friendlyMessage = "This credential is already associated with a different account."
                case .invalidUserToken, .userTokenExpired:
                    friendlyMessage = "Your session has expired. Please sign in again."
                case .missingEmail:
                    friendlyMessage = "Email address is required."
                default:
                    logger.warning("Unhandled AuthErrorCode: \(nsError.code) - \(error.localizedDescription)")
                    friendlyMessage = "Authentication failed. Please try again."
                }
            } else {
                logger.warning("Unknown AuthErrorCode raw value: \(nsError.code) - \(error.localizedDescription)")
                friendlyMessage = "An unexpected authentication error occurred. Please try again."
            }
        } else if nsError.domain == FirestoreErrorDomain {
            logger.warning("Firestore Error: \(nsError.code) - \(error.localizedDescription)")
            switch nsError.code {
            case FirestoreErrorCode.permissionDenied.rawValue:
                friendlyMessage = "You don't have permission for this database action."
            case FirestoreErrorCode.alreadyExists.rawValue:
                friendlyMessage = "This item (e.g., username) already exists."
            case FirestoreErrorCode.notFound.rawValue:
                friendlyMessage = "The requested data was not found."
            case FirestoreErrorCode.unavailable.rawValue:
                friendlyMessage = "Service is temporarily unavailable. Please try again."
            case FirestoreErrorCode.deadlineExceeded.rawValue:
                friendlyMessage = "Request timed out. Please check your connection and try again."
            default:
                friendlyMessage = "A database error occurred. Please check your connection and try again."
            }
        } else if (error as? URLError)?.code == .notConnectedToInternet {
            friendlyMessage = "No internet connection. Please connect to the internet and try again."
        } else if (error as? URLError)?.code == .timedOut {
            friendlyMessage = "Request timed out. Please check your connection and try again."
        } else {
            logger.warning("Non-Firebase Error during auth operation: \(nsError.domain) - \(nsError.code) - \(error.localizedDescription)")
            friendlyMessage = "An unexpected error occurred. Please try again. If the problem persists, please contact support."
        }
        return friendlyMessage
    }
}
