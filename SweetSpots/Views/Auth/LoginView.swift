//
//  LoginView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        NavigationStack {
            VStack {
                
                //Logo
                Image(systemName: "map")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .padding(.top, 60)
                
                VStack(spacing:24){
                    
                    //Email
                    InputView(text: $email,
                              title: "Email Address",
                              placeholder: "name@example.com")
                    .textInputAutocapitalization(.never)
                    
                    
                    //Password
                    InputView(text: $password, title: "Password", placeholder: "Enter your password", isSecureField: true)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                //Forgot Password
                
                
                //Sign In
                Button{
                    print("Log user in..")
                }label:{
                    HStack{
                        Text("SIGN IN")
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
                NavigationLink{
                    SignupView()
                        .navigationBarBackButtonHidden(true)
                }label:{
                    HStack(spacing: 2){
                        Text("Don't have an account?")
                        Text("Sign Up")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.systemBlue))
                    
                }
                
            }
        }
    }
}

#Preview {
    LoginView()
}
