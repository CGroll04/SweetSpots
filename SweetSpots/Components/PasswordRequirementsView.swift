//
//  PasswordRequirementsView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//

import SwiftUI

// MARK: - PasswordRequirementsView Subview
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
