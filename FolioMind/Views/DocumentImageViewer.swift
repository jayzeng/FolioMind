//
//  DocumentImageViewer.swift
//  FolioMind
//
//  Zoomable image viewer with full screen support for document images.
//

import SwiftUI

struct ZoomableImageView: View {
    let imageURL: URL?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showFullScreen: Bool = false

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        Group {
            if let imageURL = imageURL,
               let image = loadImage(from: imageURL) {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, minScale), maxScale)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if scale < minScale {
                                        withAnimation(.spring(response: 0.3)) {
                                            scale = minScale
                                            offset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                        .onTapGesture {
                            showFullScreen = true
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .fullScreenCover(isPresented: $showFullScreen) {
                    FullScreenImageViewer(imageURL: imageURL)
                }
            } else {
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.systemGray5))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    private func loadImage(from url: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

struct FullScreenImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let imageURL: URL?
    let onDelete: (() -> Void)?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls: Bool = true
    @State private var imageVersion: Int = 0
    @State private var isRotating: Bool = false
    @State private var rotationError: String?
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    private var isBusy: Bool { isRotating || isDeleting }

    init(imageURL: URL?, onDelete: (() -> Void)? = nil) {
        self.imageURL = imageURL
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let imageURL = imageURL,
               let image = loadImage(from: imageURL, cacheBuster: imageVersion) {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, minScale), maxScale)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if scale < minScale {
                                        withAnimation(.spring(response: 0.3)) {
                                            scale = minScale
                                            offset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()

                if showControls {
                    controlsView
                }
            }
            .opacity(showControls ? 1 : 0)
        }
        .alert(
            "Rotate Failed",
            isPresented: Binding(
                get: { rotationError != nil },
                set: { isPresented in
                    if !isPresented {
                        rotationError = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    rotationError = nil
                }
            },
            message: {
                if let rotationError {
                    Text(rotationError)
                }
            }
        )
        .confirmationDialog(
            "Delete Image?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Image", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the image from the document.")
        }
    }

    private var controlsView: some View {
        HStack(spacing: 26) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    scale = max(scale - 0.5, minScale)
                    if scale == minScale {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .disabled(scale <= minScale || isBusy)

            Button {
                withAnimation(.spring(response: 0.3)) {
                    scale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .disabled((scale == minScale && offset == .zero) || isBusy)

            Button {
                rotateCurrentImage()
            } label: {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.5))
                        .frame(width: 50, height: 50)
                    if isRotating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(isBusy || imageURL == nil)

            if onDelete != nil {
                Button {
                    showDeleteConfirm = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(.red.opacity(0.8), lineWidth: 1)
                            )
                        if isDeleting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.red)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(isBusy)
            }

            Button {
                withAnimation(.spring(response: 0.3)) {
                    scale = min(scale + 0.5, maxScale)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .disabled(scale >= maxScale || isBusy)
        }
        .padding(.bottom, 32)
    }

    private func rotateCurrentImage(clockwise: Bool = true) {
        guard !isRotating, let imageURL else { return }

        isRotating = true
        Task.detached(priority: .userInitiated) {
            do {
                try rotateImageFile(at: imageURL, clockwise: clockwise)
                await MainActor.run {
                    withAnimation(.spring(response: 0.3)) {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                        imageVersion += 1
                        showControls = true
                    }
                }
            } catch {
                await MainActor.run {
                    rotationError = error.localizedDescription
                }
            }
            await MainActor.run {
                isRotating = false
            }
        }
    }

    private func performDelete() {
        guard !isDeleting else { return }
        guard let onDelete else { return }

        isDeleting = true
        Task { @MainActor in
            onDelete()
            isDeleting = false
            dismiss()
        }
    }

    private func rotateImageFile(at url: URL, clockwise: Bool) throws {
        guard let image = loadImage(from: url) else {
            throw RotationError.imageUnavailable
        }

        let angle = clockwise ? CGFloat.pi / 2 : -CGFloat.pi / 2
        let rotatedSize = CGSize(width: image.size.height, height: image.size.width)
        var format = image.imageRendererFormat
        format.scale = image.scale

        let renderer = UIGraphicsImageRenderer(size: rotatedSize, format: format)
        let rotatedImage = renderer.image { context in
            context.cgContext.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            context.cgContext.rotate(by: angle)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }

        guard let data = rotatedImage.jpegData(compressionQuality: 0.95) else {
            throw RotationError.encodingFailed
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RotationError.writeFailed(error.localizedDescription)
        }
    }

    private enum RotationError: LocalizedError {
        case imageUnavailable
        case encodingFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .imageUnavailable:
                return "Could not load the image to rotate."
            case .encodingFailed:
                return "Saving the rotated image failed."
            case .writeFailed(let message):
                return "Could not update the file: \(message)"
            }
        }
    }

    private func loadImage(from url: URL, cacheBuster: Int = 0) -> UIImage? {
        _ = cacheBuster // Ensures SwiftUI recomputes when the image updates
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
