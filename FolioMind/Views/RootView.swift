//
//  RootView.swift
//  FolioMind
//
//  Root view that handles authentication state.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var services: AppServices
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        AuthenticatedRootView()
            .environmentObject(services.authViewModel)
            .environmentObject(services)
    }
}

private struct AuthenticatedRootView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            } else {
                SignInView(authViewModel: authViewModel)
            }
        }
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
    }
}

#Preview {
    RootView()
        .environmentObject(AppServices())
}
