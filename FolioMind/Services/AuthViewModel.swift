//
//  AuthViewModel.swift
//  FolioMind
//
//  Manages Sign in with Apple flow and authentication state.
//

import AuthenticationServices
import SwiftUI

@MainActor
final class AuthViewModel: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var authError: AuthError?
    @Published var showReloginPrompt = false

    private let authAPI = AuthAPI()
    private let tokenManager: TokenManager
    private var authCheckTimer: Timer?

    override init() {
        self.tokenManager = TokenManager(authAPI: authAPI)
        super.init()

        Task {
            // Check if we're already authenticated
            isAuthenticated = await tokenManager.isAuthenticated

            // Check Apple credential state on launch
            await tokenManager.checkAppleCredentialState()

            // Re-check authentication status after credential check
            isAuthenticated = await tokenManager.isAuthenticated

            // Start periodic auth check to detect when session is cleared
            startAuthMonitoring()
        }
    }

    deinit {
        authCheckTimer?.invalidate()
    }

    private func startAuthMonitoring() {
        // Check auth status every 10 seconds to detect session changes
        authCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAuthenticated = self.isAuthenticated
                let nowAuthenticated = await self.tokenManager.isAuthenticated

                // If user was authenticated but now isn't, show re-login prompt
                if wasAuthenticated && !nowAuthenticated {
                    print("⚠️ Session lost - prompting user to re-login")
                    self.isAuthenticated = false
                    self.showReloginPrompt = true
                    self.authError = .tokenExpired
                } else {
                    self.isAuthenticated = nowAuthenticated
                }
            }
        }
    }

    // MARK: - Public API

    func signInWithApple() {
        authError = nil
        isAuthenticating = true
        showReloginPrompt = false

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        Task {
            do {
                try await tokenManager.clearSession()

                await MainActor.run {
                    isAuthenticated = false
                    authError = nil

                    // Clear stored user info
                    UserDefaults.standard.removeObject(forKey: "user_email")
                    UserDefaults.standard.removeObject(forKey: "user_name")
                }

                print("✅ Signed out successfully")
            } catch {
                print("⚠️ Sign out error: \(error)")

                await MainActor.run {
                    authError = AuthError.appleAuthFailed(error)
                }
            }
        }
    }

    /// Get the user's email if available
    var userEmail: String? {
        UserDefaults.standard.string(forKey: "user_email")
    }

    /// Get the user's name if available
    var userName: String? {
        UserDefaults.standard.string(forKey: "user_name")
    }

    /// Get a valid access token (for making authenticated API calls)
    func getAccessToken() async throws -> String {
        try await tokenManager.validAccessToken()
    }

    /// Get the TokenManager for direct use by services
    func getTokenManager() -> TokenManager {
        tokenManager
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthViewModel: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task {
            do {
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    throw AuthError.invalidIdentityToken
                }

                guard let tokenData = credential.identityToken,
                      let tokenString = String(data: tokenData, encoding: .utf8) else {
                    throw AuthError.invalidIdentityToken
                }

                let appleUserID = credential.user

                // Authenticate with backend
                let session = try await authAPI.authenticateWithApple(
                    identityToken: tokenString,
                    appleUserID: appleUserID
                )

                // Save session
                try await tokenManager.saveSession(session)

                // Update state on main thread
                await MainActor.run {
                    isAuthenticated = true
                    isAuthenticating = false
                    authError = nil
                    print("🔄 Auth state updated: isAuthenticated = \(isAuthenticated)")
                }

                print("✅ Sign in with Apple successful")

                // Save user info if available (only on first sign-in)
                if let email = credential.email {
                    print("📧 Email: \(email)")
                    UserDefaults.standard.set(email, forKey: "user_email")
                }
                if let fullName = credential.fullName {
                    let name = [fullName.givenName, fullName.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    if !name.isEmpty {
                        print("👤 Name: \(name)")
                        UserDefaults.standard.set(name, forKey: "user_name")
                    }
                }

            } catch let error as AuthError {
                await MainActor.run {
                    isAuthenticating = false
                    authError = error
                }
                print("❌ Auth error: \(error.localizedDescription)")
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authError = .appleAuthFailed(error)
                }
                print("❌ Auth error: \(error.localizedDescription)")
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            isAuthenticating = false

            // Check if user cancelled
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                self.authError = .appleAuthCancelled
                print("ℹ️ Sign in cancelled by user")
            } else {
                self.authError = .appleAuthFailed(error)
                print("❌ Sign in with Apple error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthViewModel: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }
}
