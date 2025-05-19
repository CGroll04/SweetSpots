//
//  AuthViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-04.
//

import SwiftUI
import FirebaseAuth

class AuthViewModel: ObservableObject {
    @Published var userSession: FirebaseAuth.User?
    @Published var errorMessage: String?
    @Published var isSigningUp = false
    
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    
    init(){
        self.userSession = Auth.auth().currentUser
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.userSession = user
        }
    }
    
    deinit{
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }
    
    func signIn(){
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            if let error = error{
                self?.errorMessage = error.localizedDescription
                return
            }
            self?.errorMessage = nil
        }
    }
    
    func signUp(){
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
                
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error{
                self?.errorMessage = error.localizedDescription
                return
            }
            self?.errorMessage = nil
        }
    }
    
    func signOut(){
        do {
            try Auth.auth().signOut()
            self.email = ""
            self.password = ""
            self.confirmPassword = ""
            self.isSigningUp = false
            self.errorMessage = nil
        }catch let signOutError as NSError{
            self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
        }
    }
    
    func clearInputs(){
        email = ""
        password = ""
        confirmPassword = ""
        errorMessage = nil
    }
}

