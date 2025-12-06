//
//  SignInView.swift
//  FolioMind
//
//  Sign in with Apple authentication screen.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App branding
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)

                Text("FolioMind")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Organize your documents with intelligence")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Authentication section
            VStack(spacing: 24) {
                // Sign in with Apple button
                SignInWithAppleButton(
                    .signIn,
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { _ in
                        // Handled by AuthViewModel delegate
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(8)
                .onTapGesture {
                    authViewModel.signInWithApple()
                }
                .disabled(authViewModel.isAuthenticating)

                // Loading indicator
                if authViewModel.isAuthenticating {
                    ProgressView()
                        .progressViewStyle(.circular)
                }

                // Error message
                if let error = authViewModel.authError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .padding()
    }
}

#Preview {
    SignInView(authViewModel: AuthViewModel())
}
