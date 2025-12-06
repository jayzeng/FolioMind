# Authentication Setup Guide

This guide covers setting up Sign in with Apple authentication for FolioMind.

## Overview

FolioMind now includes complete authentication using Sign in with Apple. The implementation follows the architecture described in `/Users/jay/designland/doc-ocr-service/docs/AUTHENTICATION_STRATEGY.md`.

## Components Implemented

### Core Services
- **KeychainManager.swift** - Secure token storage using iOS Keychain
- **AuthModels.swift** - Authentication models and error types
- **AuthAPI.swift** - Backend authentication API client
- **TokenManager.swift** - Automatic token refresh with request coalescing
- **AuthViewModel.swift** - Sign in with Apple flow coordinator

### UI Components
- **SignInView.swift** - Authentication screen
- **RootView.swift** - Handles authenticated vs. unauthenticated state
- **SettingsView.swift** - Updated with sign out functionality

### Integration
- **AppServices.swift** - Authentication integrated into app services
- **BackendAPIService.swift** - Automatic token attachment to API requests

## Xcode Project Setup

### 1. Add Sign in with Apple Capability

1. Open `FolioMind.xcodeproj` in Xcode
2. Select the FolioMind target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "Sign in with Apple"

### 2. Configure App ID in Apple Developer Portal

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to Certificates, Identifiers & Profiles
3. Select your App ID (or create one)
4. Enable "Sign in with Apple" capability
5. Save changes

### 3. Update Info.plist (if needed)

The following usage descriptions may be needed:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>We use Sign in with Apple to securely authenticate your account.</string>
```

### 4. Add Files to Xcode Project

Ensure all new Swift files are added to the Xcode project:

**Services:**
- `Services/KeychainManager.swift`
- `Services/AuthModels.swift`
- `Services/AuthAPI.swift`
- `Services/TokenManager.swift`
- `Services/AuthViewModel.swift`

**Views:**
- `Views/SignInView.swift`
- `Views/RootView.swift`

## Backend Configuration

The iOS client expects the backend to implement these endpoints:

### POST /api/v1/auth/apple
Request:
```json
{
  "identity_token": "eyJraWQ...",
  "device_id": "uuid",
  "app_version": "1.0.0"
}
```

Response:
```json
{
  "access_token": "eyJhbGc...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "refresh_abc123"
}
```

### POST /api/v1/auth/refresh
Request:
```json
{
  "refresh_token": "refresh_abc123"
}
```

Response:
```json
{
  "access_token": "eyJhbGc...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "refresh_xyz789"
}
```

### POST /api/v1/auth/logout
Headers:
```
Authorization: Bearer <access_token>
```

Response: 200 OK

## How It Works

### First Launch / Sign In Flow

1. User launches app
2. `RootView` checks `authViewModel.isAuthenticated`
3. If not authenticated, shows `SignInView`
4. User taps "Sign in with Apple"
5. iOS presents Apple ID authentication sheet
6. On success, app receives `identityToken` from Apple
7. `AuthViewModel` sends token to backend `/auth/apple`
8. Backend verifies Apple token and returns access/refresh tokens
9. `TokenManager` saves session to Keychain
10. User sees main app (`ContentView`)

### Subsequent Launches

1. User launches app
2. `TokenManager` loads session from Keychain
3. Checks if access token is valid
4. If valid, user sees main app immediately
5. If expired but refresh token exists, automatically refreshes
6. On successful refresh, user sees main app
7. If refresh fails, user sees `SignInView`

### Making Authenticated API Calls

All calls through `BackendAPIService` automatically include authentication:

```swift
// In BackendAPIService
private func post<T: Encodable, R: Decodable>(url: URL, body: T) async throws -> R {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    // Automatically adds auth header
    if let tokenManager = tokenManager {
        let token = try await tokenManager.validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // ... rest of request
}
```

### Token Refresh Strategy

- Access tokens expire after 60 minutes (configurable on backend)
- `TokenManager` proactively refreshes when < 5 minutes remaining
- Multiple concurrent refresh requests are coalesced into one
- If refresh fails, user is signed out and returns to `SignInView`

### Apple Credential State Monitoring

The app monitors Apple credential state:

```swift
func checkAppleCredentialState() async {
    let state = try await ASAuthorizationAppleIDProvider()
        .credentialState(forUserID: appleUserID)

    switch state {
    case .revoked, .notFound:
        // Clear session and sign out
    case .authorized:
        // Continue
    }
}
```

This runs:
- On app launch
- When app returns to foreground
- Periodically during active use

## Testing

### Test Sign In Flow

1. Build and run the app
2. You should see the `SignInView`
3. Tap "Sign in with Apple"
4. Complete Apple authentication
5. Verify you're redirected to `ContentView`
6. Check console for "✅ Sign in with Apple successful"

### Test Token Persistence

1. Sign in successfully
2. Force quit the app
3. Relaunch the app
4. You should see `ContentView` immediately (no sign in screen)
5. Check console for "✅ Loaded auth session from Keychain"

### Test Token Refresh

1. In `TokenManager.swift`, temporarily change:
   ```swift
   // Change this:
   if !session.isExpired && !session.isExpiringSoon {

   // To this (forces immediate refresh):
   if false {
   ```
2. Sign in and make an API call
3. Check console for "✅ Refreshed access token"
4. Revert the change

### Test Sign Out

1. Navigate to Settings
2. Scroll to "Account" section
3. Tap "Sign Out"
4. Confirm sign out
5. Verify you're returned to `SignInView`

### Test Backend Integration

Use the backend's health endpoint to verify:

```bash
curl https://foliomind-backend.fly.dev/health
```

## Troubleshooting

### "Invalid Identity Token" Error

- Ensure Sign in with Apple capability is enabled
- Verify App ID matches backend configuration
- Check that identity token is being passed correctly

### "Authentication Required" Error

- Backend endpoints may require authentication
- Check that `BackendAPIService` is initialized with `tokenManager`
- Verify token is being sent in Authorization header

### Token Not Persisting

- Check Keychain entitlements
- Verify `KeychainManager` save operations succeed
- Look for errors in console during save/load

### Sign In Button Not Responding

- Verify `SignInWithAppleButton` is properly configured
- Check that `AuthViewModel` delegate methods are being called
- Look for Apple authentication errors in console

## Security Considerations

1. **Keychain Storage**: Tokens are stored with `kSecAttrAccessibleAfterFirstUnlock` for security
2. **Token Rotation**: Refresh tokens are rotated on each refresh
3. **HTTPS Only**: All API calls use HTTPS
4. **No Token Logging**: Never log full tokens (only success/failure)
5. **Automatic Cleanup**: Tokens are cleared on sign out

## Next Steps

### Optional Enhancements

1. **Biometric Auth**: Add Face ID/Touch ID before showing stored session
2. **Multiple Devices**: Track active sessions per device
3. **Session Management**: Show active devices in settings
4. **Forced Sign Out**: Backend endpoint to revoke all sessions
5. **Activity Monitoring**: Log authentication events for security audit

### Backend Implementation Checklist

If you haven't implemented the backend yet, you need:

- [ ] Apple JWT verification (fetch and cache Apple public keys)
- [ ] User creation on first sign-in
- [ ] Access token generation (JWT or opaque)
- [ ] Refresh token generation and storage (hashed)
- [ ] Token refresh endpoint with rotation
- [ ] Logout endpoint
- [ ] Protected endpoint middleware

See `/Users/jay/designland/doc-ocr-service/docs/AUTHENTICATION_STRATEGY.md` for full backend implementation details.

## Reference Architecture

```
┌─────────────┐
│   iOS App   │
└──────┬──────┘
       │
       │ 1. identityToken
       ▼
┌─────────────────┐
│  POST /auth/    │
│      apple      │
└────────┬────────┘
         │
         │ 2. Verify Apple JWT
         │    Create/Find User
         │    Issue Tokens
         ▼
┌─────────────────┐
│   Keychain      │
│   Storage       │
└────────┬────────┘
         │
         │ 3. Load on launch
         │    Auto refresh
         ▼
┌─────────────────┐
│  API Requests   │
│  w/ Bearer      │
│  Token          │
└─────────────────┘
```

## Additional Resources

- [Apple Documentation: Sign in with Apple](https://developer.apple.com/sign-in-with-apple/)
- [Backend Auth Strategy](../doc-ocr-service/docs/AUTHENTICATION_STRATEGY.md)
- [iOS Integration Guide](../doc-ocr-service/docs/IOS_AUTH_INTEGRATION.md)
