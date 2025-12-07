//
//  OnboardingView.swift
//  FolioMind
//
//  A narrative first-run experience that introduces FolioMind,
//  lets users pick a starting goal, and optionally loads a small
//  sample folio so they can explore before committing their own docs.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.modelContext) private var modelContext

    /// Persists the user’s primary organizing goal so empty states can adapt copy.
    @AppStorage("onboarding_primary_goal") private var primaryGoal: String = ""

    @State private var currentPage: Int = 0
    @State private var selectedGoal: String = ""
    @State private var wantsSampleFolio: Bool = false
    @State private var isCompleting: Bool = false

    let onFinished: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    introPage
                        .tag(0)
                    intelligencePage
                        .tag(1)
                    goalsPage
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Material.ultraThin)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(hue: 0.60, saturation: 0.22, brightness: 0.96),
                        Color(hue: 0.62, saturation: 0.30, brightness: 0.90),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationBarBackButtonHidden(true)
        }
    }

    private var introPage: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)

            VStack(spacing: 12) {
                Text("Welcome to FolioMind")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Turn scattered paperwork into a living memory bank.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            heroStack
                .padding(.horizontal, 24)

            Text(
                "Capture receipts, IDs, letters and more. " +
                "FolioMind remembers people, dates, and details so you can stop digging for that one document."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    private var intelligencePage: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            VStack(spacing: 10) {
                Text("Your docs, with context")
                    .font(.title2.weight(.semibold))

                Text("We analyze each page for text, people, dates and places – then make everything searchable in a few seconds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                SurfaceCard {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.viewfinder")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scan or import")
                                .font(.subheadline.weight(.semibold))
                            Text("Bring in a document from your camera or photo library.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SurfaceCard {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.title3)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("We do the busywork")
                                .font(.subheadline.weight(.semibold))
                            Text("OCR, document type, key fields and links are suggested automatically.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SurfaceCard {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Find anything later")
                                .font(.subheadline.weight(.semibold))
                            Text("Search by person, amount, place or phrase across all your docs.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Text("Most processing stays on your device by default, with optional backend support you control in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    private var goalsPage: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 40)

            VStack(spacing: 10) {
                Text("What do you want to tame first?")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("We’ll tune suggestions and empty states around this, and you can still store anything.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 10) {
                goalButton(
                    title: "Receipts & money",
                    subtitle: "Rent, reimbursements, subscriptions",
                    icon: "creditcard.fill",
                    key: "receipts"
                )
                goalButton(
                    title: "ID & cards",
                    subtitle: "Passports, licenses, insurance",
                    icon: "person.crop.rectangle",
                    key: "ids"
                )
                goalButton(
                    title: "Health & medical",
                    subtitle: "Lab results, referrals, bills",
                    icon: "cross.vial.fill",
                    key: "health"
                )
                goalButton(
                    title: "Family docs",
                    subtitle: "School, pets, shared paperwork",
                    icon: "person.2.crop.square.stack",
                    key: "family"
                )
            }
            .padding(.horizontal, 20)

            Toggle(isOn: $wantsSampleFolio) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore with a sample folio")
                        .font(.subheadline.weight(.semibold))
                    Text("We’ll add a few fake documents so you can tap around before adding your own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 24)
            .padding(.top, 6)

            Text(
                "You’re always in control. You can delete sample data, change your goal, " +
                "or adjust privacy and backend options later in Settings."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                if currentPage == 0 {
                    onFinished()
                } else {
                    withAnimation(.easeInOut) {
                        currentPage -= 1
                    }
                }
            } label: {
                Text(currentPage == 0 ? "Skip" : "Back")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.secondary)

            Spacer()

            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 6) {
                    if isCompleting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(currentPage == 2 ? "Start organizing" : "Continue")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(minWidth: 140)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .foregroundStyle(.white)
            }
            .disabled(isCompleting)
        }
    }

    private var heroStack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: 0.60, saturation: 0.30, brightness: 0.95),
                            Color(hue: 0.65, saturation: 0.28, brightness: 0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 24, y: 12)

            VStack(spacing: 14) {
                HStack {
                    Label("Smart folio", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.2))
                        )
                        .foregroundStyle(.white)
                    Spacer()
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“March rent receipt”")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Found in 0.2 seconds")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.18))
                        )
                }

                Divider()
                    .background(Color.white.opacity(0.3))

                HStack(spacing: 12) {
                    pill(icon: "person.crop.circle.fill", text: "People")
                    pill(icon: "calendar", text: "Dates")
                    pill(icon: "mappin.circle.fill", text: "Places")
                }

                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("We gently enrich, never overwrite your docs.")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.9))
                    Spacer()
                }
            }
            .padding(18)
        }
        .frame(maxWidth: 380)
        .frame(height: 220)
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
        .foregroundStyle(.white)
    }

    private func goalButton(title: String, subtitle: String, icon: String, key: String) -> some View {
        Button {
            withAnimation(.easeInOut) {
                selectedGoal = key
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedGoal == key {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(selectedGoal == key ? 1.0 : 0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selectedGoal == key ? Color.blue.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func handlePrimaryAction() {
        if currentPage < 2 {
            withAnimation(.easeInOut) {
                currentPage += 1
            }
            return
        }

        guard !isCompleting else { return }
        isCompleting = true

        let goalKey = selectedGoal.isEmpty ? "receipts" : selectedGoal
        primaryGoal = goalKey

        Task {
            if wantsSampleFolio {
                await createSampleFolioIfNeeded()
            }

            await MainActor.run {
                onFinished()
            }
        }
    }

    private func createSampleFolioIfNeeded() async {
        let context = modelContext

        let descriptor = FetchDescriptor<Document>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else {
            return
        }

        for index in 1...4 {
            do {
                _ = try await services.documentStore.createStubDocument(
                    in: context,
                    titleSuffix: index
                )
            } catch {
                print("⚠️ Failed to create stub document \(index): \(error)")
            }
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
        .environmentObject(AppServices())
}
