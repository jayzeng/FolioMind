//
//  SettingsView.swift
//  FolioMind
//
//  Settings view for configuring app preferences including LLM API keys and features.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    @Environment(\.modelContext) private var modelContext
    @State private var showingSignOutConfirmation: Bool = false
    @StateObject private var languageManager = LanguageManager.shared

    var body: some View {
        NavigationStack {
            Form {
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                } header: {
                    Text("About")
                }
                
                // Language Section
                Section {
                    Picker("App Language", selection: $languageManager.currentLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            HStack {
                                Text(language.icon)
                                Text(language.displayName)
                            }
                            .tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Language")
                } footer: {
                    Text("Change the app language. The interface updates right away without restarting.")
                }

                // Privacy Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        PrivacyRow(
                            icon: "lock.shield.fill",
                            title: "Local-First",
                            description: "Documents and OCR are processed on-device by default"
                        )

                        Divider()

                        PrivacyRow(
                            icon: "icloud.slash.fill",
                            title: "No Cloud Storage",
                            description: "Your documents stay on your device unless you choose to share them"
                        )

                        Divider()

                        PrivacyRow(
                            icon: "key.fill",
                            title: "Secure Keys",
                            description: "API keys are encrypted and stored in iOS Keychain"
                        )
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Privacy & Security")
                }

                // Account Section
                Section {
                    if services.authViewModel.isAuthenticated {
                        if let name = services.authViewModel.userName {
                            HStack {
                                Text("Name")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(name)
                            }
                        }

                        if let email = services.authViewModel.userEmail {
                            HStack {
                                Text("Email")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(email)
                            }
                        }

                        Button(role: .destructive) {
                            showingSignOutConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Not signed in")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Account")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Sign Out", isPresented: $showingSignOutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    services.authViewModel.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out? You'll need to sign in again to use backend features.")
            }
        }
    }
}

struct PrivacyRow: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    SettingsView()
}
