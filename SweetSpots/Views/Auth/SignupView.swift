//
//  SignupView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI

struct SignupView: View {
    @State private var email = ""
    @State private var firstname = ""
    @State private var lastname = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack{
            
            //Logo
            Image(systemName: "map")
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .padding(.vertical, 32)
            
            VStack(spacing:24){
                
                //Email
                InputView(text: $email,
                          title: "Email Address",
                          placeholder: "name@example.com")
                .textInputAutocapitalization(.never)
                
                //First Name
                InputView(text: $firstname,
                          title: "First Name",
                          placeholder: "Enter your first name")
                //Last Name
                InputView(text: $lastname,
                          title: "Last Name",
                          placeholder: "Enter your last name")
                
                //Password
                InputView(text: $password, title: "Password", placeholder: "Enter your password", isSecureField: true)
                
                //Confirm Password
                InputView(text: $confirmPassword, title: "Confirm Password", placeholder: "Confirm your password", isSecureField: true)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            //Forgot Password
            
            
            //Sign In
            Button{
                print("Sign user up..")
            }label:{
                HStack{
                    Text("SIGN UP")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Color(.white))
                .frame(width: UIScreen.main.bounds.width - 32, height: 48)
            }
            .background(Color(.systemBlue))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 24)
            
            Spacer()
            
            //Sign Up
            Button{
                dismiss()
            }label:{
                HStack(spacing: 2){
                    Text("Already have an account?")
                    Text("Sign In")
                    .fontWeight(.bold)
                }
                .font(.system(size: 14))
                .foregroundStyle(Color(.systemBlue))

            }
            
        }
    }
}

#Preview {
    SignupView()
}
