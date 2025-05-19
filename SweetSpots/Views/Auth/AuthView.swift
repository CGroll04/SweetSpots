//
//  AuthView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-18.
//
import SwiftUI

struct AuthView: View {

    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "mappin.and.ellipse")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.accentColor)

                Text("SweetSpots")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                VStack(spacing: 15) {
                    
                    TextField("Email", text: $authViewModel.email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    SecureField("Password", text: $authViewModel.password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    if authViewModel.isSigningUp {
                        SecureField("Confirm Password", text: $authViewModel.confirmPassword)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: {
                    if authViewModel.isSigningUp {
                        authViewModel.signUp() // This will update the shared authViewModel
                    } else {
                        authViewModel.signIn() // This will update the shared authViewModel
                    }
                }) {
                    Text(authViewModel.isSigningUp ? "Sign Up" : "Sign In")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                Button(action: {
                    authViewModel.isSigningUp.toggle()
                    authViewModel.clearInputs()
                }) {
                    Text(authViewModel.isSigningUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.subheadline)
                }

                Spacer()
                Spacer()
            }
            .padding()
            .navigationTitle(authViewModel.isSigningUp ? "Create Account" : "Welcome Back")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
            .environmentObject(AuthViewModel())
    }
}
