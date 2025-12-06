//
//  AuthAPI.swift
//  FolioMind
//
//  Backend authentication API client.
//

import Foundation
import UIKit

actor AuthAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: String = "http://192.168.0.144:8000", session: URLSession = .shared) {
        // Remove trailing slash if present
        let cleanURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.baseURL = URL(string: cleanURL)!
        self.session = session
    }

    // MARK: - Authentication Endpoints

    /// Authenticate with Apple identity token
    func authenticateWithApple(identityToken: String, appleUserID: String) async throws -> AuthSession {
        let url = baseURL.appendingPathComponent("/api/v1/auth/apple")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceID = await UIDevice.current.identifierForVendor?.uuidString ?? ""
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

        let body: [String: Any] = [
            "identity_token": identityToken,
            "device_id": deviceID,
            "app_version": appVersion
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let tokenResponse: TokenResponse = try await performRequest(request)
        return AuthSession(from: tokenResponse, appleUserID: appleUserID)
    }

    /// Refresh access token using refresh token
    func refresh(using refreshToken: String, appleUserID: String?) async throws -> AuthSession {
        let url = baseURL.appendingPathComponent("/api/v1/auth/refresh")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "refresh_token": refreshToken
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let tokenResponse: TokenResponse = try await performRequest(request)
        return AuthSession(from: tokenResponse, appleUserID: appleUserID)
    }

    /// Logout and invalidate tokens
    func logout(accessToken: String, refreshToken: String?) async throws {
        let url = baseURL.appendingPathComponent("/api/v1/auth/logout")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Include refresh token in body if available
        if let refreshToken = refreshToken {
            let body: [String: Any] = [
                "refresh_token": refreshToken
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        _ = try await performRequest(request) as EmptyResponse
    }

    // MARK: - Private Helpers

    private struct EmptyResponse: Decodable {}

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw AuthError.networkFailure(httpResponse.statusCode, message)
        }

        // Handle empty responses
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Response data: \(jsonString)")
            }
            throw AuthError.invalidResponse
        }
    }
}
