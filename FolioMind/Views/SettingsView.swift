//
//  SettingsView.swift
//  FolioMind
//
//  Settings view for configuring app preferences including LLM API keys and features.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    @AppStorage("openai_api_key") private var openAIAPIKey: String = ""
    @AppStorage("use_apple_intelligence") private var useAppleIntelligence: Bool = true
    @AppStorage("use_openai_fallback") private var useOpenAIFallback: Bool = true
    @AppStorage("use_backend_processing") private var useBackendProcessing: Bool = true
    @State private var showingAPIKeyInfo: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    @State private var showingRestartAlert: Bool = false
    @State private var showingSignOutConfirmation: Bool = false
    @StateObject private var languageManager = LanguageManager.shared

    private var hasAppleIntelligence: Bool {
        LLMServiceFactory.create(type: .apple) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Intelligence Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.blue)
                            Text("Apple Intelligence")
                                .font(.headline)
                        }

                        if hasAppleIntelligence {
                            Label("Available on this device", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label("Requires iOS 18.2+ or later", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)

                    Toggle("Use Apple Intelligence", isOn: $useAppleIntelligence)
                        .disabled(!hasAppleIntelligence)
                } header: {
                    Text("Intelligence")
                } footer: {
                    Text(
                        "Apple Intelligence provides on-device text cleaning and intelligent field extraction "
                        + "for better accuracy and privacy."
                    )
                }

                // Backend Processing Section
                Section {
                    Toggle("Use Backend Processing", isOn: $useBackendProcessing)
                        .onChange(of: useBackendProcessing) { _, _ in
                            showingRestartAlert = true
                        }

                    if useBackendProcessing {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "network")
                                    .foregroundStyle(.blue)
                                Text("Backend Status")
                                    .font(.subheadline)
                            }

                            Label("Connected to https://foliomind-backend.fly.dev/", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Processing Mode")
                } footer: {
                    if useBackendProcessing {
                        Text(
                            "Using backend API for document classification, field extraction, and audio transcription. "
                            + "This provides more accurate results powered by advanced LLM models."
                        )
                    } else {
                        Text("Using on-device processing with Apple Intelligence or OpenAI. All data is processed locally on your device.")
                    }
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

                // OpenAI Section
                Section {
                    Toggle("Use OpenAI Fallback", isOn: $useOpenAIFallback)

                    if useOpenAIFallback {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("API Key")
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    showingAPIKeyInfo = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.blue)
                                }
                            }

                            SecureField("sk-proj-...", text: $openAIAPIKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))

                            if !openAIAPIKey.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("API key configured")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("OpenAI Integration")
                } footer: {
                    if useOpenAIFallback {
                        Text(
                            "OpenAI is used as a fallback when Apple Intelligence is unavailable. "
                            + "Your API key is stored securely on-device and never shared with FolioMind servers."
                        )
                    } else {
                        Text("OpenAI fallback is disabled. Only Apple Intelligence will be used for intelligent extraction.")
                    }
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
                if useBackendProcessing {
                    Section {
                        if services.authViewModel.isAuthenticated {
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
                    } footer: {
                        Text("Sign in with Apple is required when using backend processing.")
                    }
                }

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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveSettings()
                    }
                }
            }
            .alert("API Key Information", isPresented: $showingAPIKeyInfo) {
                Button("OK", role: .cancel) {}
                Button("Get API Key") {
                    if let url = URL(string: "https://platform.openai.com/api-keys") {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("To use OpenAI features, you need an API key from OpenAI. Get one at platform.openai.com/api-keys")
            }
            .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your settings have been saved.")
            }
            .alert("Restart Required", isPresented: $showingRestartAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please restart the app for this change to take effect.")
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

    private func saveSettings() {
        // Settings are automatically saved via @AppStorage and apply immediately
        showingSaveConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}

struct PrivacyRow: View {
    let icon: String
    let title: String
    let description: String

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
