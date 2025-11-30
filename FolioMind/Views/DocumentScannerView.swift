//
//  DocumentScannerView.swift
//  FolioMind
//
//  SwiftUI wrapper for VisionKit document scanner with fallback when unavailable.
//

import SwiftUI

#if canImport(VisionKit)
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    var onComplete: ([URL]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    static var isAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel, onError: onError)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: ([URL]) -> Void
        let onCancel: () -> Void
        let onError: (Error) -> Void

        init(onComplete: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onError(error)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var urls: [URL] = []
            let fm = FileManager.default
            let dir: URL
            if let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let assetsDir = docs.appendingPathComponent("FolioMindAssets", isDirectory: true)
                try? fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
                dir = assetsDir
            } else {
                dir = fm.temporaryDirectory
            }

            for page in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: page)
                guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
                let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                do {
                    try data.write(to: url)
                    urls.append(url)
                } catch {
                    continue
                }
            }
            controller.dismiss(animated: true)
            onComplete(urls)
        }
    }
}
#else
struct DocumentScannerView: View {
    var onComplete: ([URL]) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onError: (Error) -> Void = { _ in }

    static var isAvailable: Bool { false }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Document scanning is unavailable on this device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Close") { onCancel() }
        }
        .padding()
    }
}
#endif
