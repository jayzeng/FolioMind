//
//  OCRReviewView.swift
//  FolioMind
//
//  Lets users preview detected text, rotate, and auto-crop images before ingestion.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(VisionKit)
import VisionKit
#endif

struct OCRReviewView: View {
    var urls: [URL]
    var onCancel: () -> Void
    var onConfirm: ([URL]) -> Void

    @State private var pages: [OCRReviewPage] = []
    @State private var currentIndex = 0
    @State private var isSaving = false
    @State private var notice: String?

    private var currentPage: OCRReviewPage? {
        guard currentIndex < pages.count else { return nil }
        return pages[currentIndex]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                noticeView
                pagerView
                Spacer(minLength: 0)
            }
            .navigationTitle("Review & Trim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Use & Process") {
                        Task { await saveAndContinue() }
                    }
                    .disabled(isSaving || pages.isEmpty)
                }
            }
            .task {
                await loadPages()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var pagerView: some View {
        if pages.isEmpty {
            ProgressView("Preparing preview…")
                .padding()
        } else {
            TabView(selection: $currentIndex) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(for: index)
                        .padding(.horizontal)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(maxHeight: 560)
        }
    }

    @ViewBuilder
    private func pageView(for index: Int) -> some View {
        let page = pages[index]

        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                if let image = page.workingImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .padding(4)
                } else {
                    ProgressView()
                }
                rotationControls(for: index)
                HStack {
                    PillBadge(text: "Page \(index + 1) of \(pages.count)", icon: nil, tint: .blue)
                    Spacer()
                    if page.isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: 320)
        }
    }

    @ViewBuilder
    private func rotationControls(for index: Int) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        Task { await rotatePage(at: index, clockwise: false) }
                    } label: {
                        Image(systemName: "rotate.left")
                            .padding(10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue.opacity(0.85))

                    Button {
                        Task { await rotatePage(at: index, clockwise: true) }
                    } label: {
                        Image(systemName: "rotate.right")
                            .padding(10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue.opacity(0.85))
                }
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
        }
    }

    // MARK: - Loading & OCR

    @MainActor
    private func loadPages() async {
        notice = "Auto-cropping to document edges and prepping for upload."
        var loaded: [OCRReviewPage] = []

        for url in urls {
            var page = OCRReviewPage(originalURL: url)
            page.isProcessing = true
            if let image = UIImage(contentsOfFile: url.path) {
                let prepared = ImagePreprocessor.preparePreviewImage(from: image)
                if let cropped = try? await ImagePreprocessor.autoCrop(prepared) {
                    page.workingImage = cropped
                } else {
                    page.workingImage = prepared
                }
            } else {
                page.ocrText = "Unable to load image."
            }
            page.isProcessing = false
            loaded.append(page)
        }

        pages = loaded
        currentIndex = 0
    }

    // MARK: - Editing actions

    @MainActor
    private func rotatePage(at index: Int, clockwise: Bool) async {
        guard pages.indices.contains(index), let image = pages[index].workingImage else { return }
        notice = "Rotated page to improve alignment."
        pages[index].isProcessing = true
        pages[index].workingImage = ImagePreprocessor.rotate90(image, clockwise: clockwise)
        pages[index].isProcessing = false
    }

    // MARK: - Save & Continue

    @MainActor
    private func saveAndContinue() async {
        guard !pages.isEmpty else { return }
        isSaving = true
        do {
            var output: [URL] = []
            for page in pages {
                try autoreleasepool {
                    guard let image = page.workingImage else { return }
                    let url = try ImagePreprocessor.saveTemporaryJPEG(image)
                    output.append(url)
                }
            }
            onConfirm(output)
        } catch {
            notice = "Failed to prepare images: \(error.localizedDescription)"
        }
        isSaving = false
    }
}

private struct OCRReviewPage: Identifiable {
    let id = UUID()
    let originalURL: URL
    var workingImage: UIImage?
    var ocrText: String = ""
    var isProcessing: Bool = false
}
