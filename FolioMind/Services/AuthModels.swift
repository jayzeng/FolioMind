//
//  AuthModels.swift
//  FolioMind
//
//  Authentication models and errors.
//

import Foundation

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case appleAuthCancelled
    case appleAuthFailed(Error)
    case invalidIdentityToken
    case networkFailure(Int, String?)
    case invalidResponse
    case tokenExpired
    case refreshFailed
    case noRefreshToken
    case notAuthenticated
    case credentialRevoked

    var errorDescription: String? {
        switch self {
        case .appleAuthCancelled:
            return "Sign in was cancelled"
        case .appleAuthFailed(let error):
            return "Sign in with Apple failed: \(error.localizedDescription)"
        case .invalidIdentityToken:
            return "Unable to obtain valid credentials from Apple"
        case .networkFailure(let code, let message):
            if let message = message {
                return "Authentication failed (\(code)): \(message)"
            }
            return "Authentication failed with status \(code)"
        case .invalidResponse:
            return "Invalid response from authentication server"
        case .tokenExpired:
            return "Your session has expired. Please sign in again."
        case .refreshFailed:
            return "Failed to refresh session. Please sign in again."
        case .noRefreshToken:
            return "No refresh token available"
        case .notAuthenticated:
            return "You need to sign in to continue"
        case .credentialRevoked:
            return "Your Apple ID credentials have been revoked. Please sign in again."
        }
    }
}

// MARK: - Auth Models

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let appleUserID: String?  // Store for credential state checking

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var isExpiringSoon: Bool {
        // Consider expired if less than 5 minutes remaining
        expiresAt.timeIntervalSinceNow < 300
    }

    init(accessToken: String, refreshToken: String?, expiresAt: Date, appleUserID: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.appleUserID = appleUserID
    }

    init(from tokenResponse: TokenResponse, appleUserID: String? = nil) {
        self.accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        self.expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        self.appleUserID = appleUserID
    }
}
