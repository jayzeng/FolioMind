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

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls: Bool = true

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let imageURL = imageURL,
               let image = loadImage(from: imageURL) {
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
    }

    private var controlsView: some View {
        HStack(spacing: 32) {
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
            .disabled(scale <= minScale)

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
            .disabled(scale == minScale && offset == .zero)

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
            .disabled(scale >= maxScale)
        }
        .padding(.bottom, 32)
    }

    private func loadImage(from url: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
