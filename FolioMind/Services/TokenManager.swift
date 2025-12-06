//
//  TokenManager.swift
//  FolioMind
//
//  Manages token lifecycle with automatic refresh and request coalescing.
//

import Foundation
import AuthenticationServices

actor TokenManager {
    private let authAPI: AuthAPI
    private let keychain: KeychainManager
    private var currentSession: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?

    init(authAPI: AuthAPI = AuthAPI(), keychain: KeychainManager = .shared) {
        self.authAPI = authAPI
        self.keychain = keychain

        // Load session from Keychain on init
        if let savedSession = try? keychain.loadAuthSession() {
            self.currentSession = savedSession
            print("✅ Loaded auth session from Keychain")
        }
    }

    // MARK: - Public API

    /// Get a valid access token, refreshing if necessary
    func validAccessToken() async throws -> String {
        // Check if we have a session
        guard let session = currentSession else {
            throw AuthError.notAuthenticated
        }

        // If token is still valid and not expiring soon, return it
        if !session.isExpired && !session.isExpiringSoon {
            return session.accessToken
        }

        // Token is expired or expiring soon - refresh it
        return try await refreshAccessToken().accessToken
    }

    /// Save a new session (after login)
    func saveSession(_ session: AuthSession) throws {
        currentSession = session
        try keychain.saveAuthSession(session)
        print("✅ Saved auth session to Keychain")
    }

    /// Clear the current session (logout)
    func clearSession() async throws {
        // Call logout endpoint if we have a valid token
        if let session = currentSession, !session.isExpired {
            try? await authAPI.logout(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        }

        currentSession = nil
        try keychain.deleteAuthSession()
        print("✅ Cleared auth session")
    }

    /// Check if user is authenticated
    var isAuthenticated: Bool {
        get async {
            currentSession != nil && !(currentSession?.isExpired ?? true)
        }
    }

    /// Get the current session
    func getSession() -> AuthSession? {
        currentSession
    }

    /// Check Apple credential state and clear session if revoked
    func checkAppleCredentialState() async {
        guard let appleUserID = currentSession?.appleUserID else {
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: appleUserID)

            switch state {
            case .revoked, .notFound:
                print("⚠️ Apple credentials revoked or not found")
                try? await clearSession()
            case .authorized:
                print("✅ Apple credentials still valid")
            case .transferred:
                print("ℹ️ Apple credentials transferred")
            @unknown default:
                print("⚠️ Unknown Apple credential state")
            }
        } catch {
            print("⚠️ Failed to check Apple credential state: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func refreshAccessToken() async throws -> AuthSession {
        // Coalesce concurrent refresh requests
        if let task = refreshTask {
            return try await task.value
        }

        let task = Task<AuthSession, Error> {
            guard let session = currentSession else {
                throw AuthError.notAuthenticated
            }

            guard let refreshToken = session.refreshToken else {
                throw AuthError.noRefreshToken
            }

            do {
                let newSession = try await authAPI.refresh(
                    using: refreshToken,
                    appleUserID: session.appleUserID
                )

                // Save the new session
                try saveSession(newSession)

                print("✅ Refreshed access token")
                return newSession
            } catch {
                // Refresh failed - clear the session
                try? await clearSession()
                throw AuthError.refreshFailed
            }
        }

        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }
}
