//
//  RootView.swift
//  FolioMind
//
//  Root view that handles authentication state.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        AuthenticatedRootView()
            .environmentObject(services.authViewModel)
    }
}

private struct AuthenticatedRootView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                ContentView()
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
