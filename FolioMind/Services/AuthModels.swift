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
    let issuedAt: Date
    let appleUserID: String?  // Store for credential state checking

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var isExpiringSoon: Bool {
        // Refresh when 20% of token lifetime remains (or minimum 5 minutes)
        // This scales with token lifetime and ensures smooth renewal
        let now = Date()
        guard now < expiresAt else { return true }

        let totalLifetime = expiresAt.timeIntervalSince(issuedAt)
        let remainingTime = expiresAt.timeIntervalSince(now)
        let refreshThreshold = max(totalLifetime * 0.2, 300) // 20% or 5 min minimum

        return remainingTime < refreshThreshold
    }

    init(accessToken: String, refreshToken: String?, expiresAt: Date, issuedAt: Date = Date(), appleUserID: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.issuedAt = issuedAt
        self.appleUserID = appleUserID
    }

    init(from tokenResponse: TokenResponse, appleUserID: String? = nil) {
        let now = Date()
        self.accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        self.expiresAt = now.addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        self.issuedAt = now
        self.appleUserID = appleUserID
    }

    // Custom decoding to handle missing issuedAt in old sessions
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        appleUserID = try container.decodeIfPresent(String.self, forKey: .appleUserID)

        // For old sessions without issuedAt, estimate it based on typical 1-hour token lifetime
        if let decodedIssuedAt = try? container.decode(Date.self, forKey: .issuedAt) {
            issuedAt = decodedIssuedAt
        } else {
            issuedAt = expiresAt.addingTimeInterval(-3600) // Assume 1 hour ago
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresAt, issuedAt, appleUserID
    }
}
