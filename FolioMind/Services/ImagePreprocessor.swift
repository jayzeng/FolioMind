//
//  ImagePreprocessor.swift
//  FolioMind
//
//  Lightweight image utilities for rotation and Vision-backed auto-cropping before ingestion.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

enum ImagePreprocessor {
    /// Normalize orientation and downscale for preview/OCR to avoid memory spikes.
    static func preparePreviewImage(from image: UIImage, maxDimension: CGFloat = 2400) -> UIImage {
        let normalized = normalizeOrientation(image)
        return downscaleIfNeeded(normalized, maxDimension: maxDimension)
    }

    /// Rotate an image by 90-degree increments.
    static func rotate90(_ image: UIImage, clockwise: Bool) -> UIImage {
        autoreleasepool {
            let normalized = normalizeOrientation(image)
            let radians = clockwise ? CGFloat.pi / 2 : -CGFloat.pi / 2
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: normalized.size.height, height: normalized.size.width))
            return renderer.image { context in
                context.cgContext.translateBy(
                    x: renderer.format.bounds.size.width / 2,
                    y: renderer.format.bounds.size.height / 2
                )
                context.cgContext.rotate(by: radians)
                normalized.draw(in: CGRect(
                    x: -normalized.size.width / 2,
                    y: -normalized.size.height / 2,
                    width: normalized.size.width,
                    height: normalized.size.height
                ))
            }
        }
    }

    /// Attempt to detect a document rectangle and crop to it. Returns nil if detection fails.
    static func autoCrop(_ image: UIImage) async throws -> UIImage? {
        #if canImport(Vision)
        return try await autoreleasepool { () -> UIImage? in
            let normalized = normalizeOrientation(image)
            guard let cgImage = normalized.cgImage else { return nil }
            let request = VNDetectRectanglesRequest()
            request.minimumConfidence = 0.6
            request.maximumObservations = 1

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            return crop(normalized, toNormalizedRect: observation.boundingBox)
        }
        #else
        return nil
        #endif
    }

    /// Crop a UIImage using a Vision-style normalized bounding box (origin bottom-left).
    static func crop(_ image: UIImage, toNormalizedRect rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let cropRect = CGRect(
            x: rect.origin.x * width,
            y: (1 - rect.origin.y - rect.size.height) * height,
            width: rect.size.width * width,
            height: rect.size.height * height
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    /// Save a UIImage as a temporary JPEG and return its URL.
    static func saveTemporaryJPEG(_ image: UIImage, quality: CGFloat = 0.9) throws -> URL {
        try autoreleasepool {
            let filename = UUID().uuidString + ".jpg"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            guard let data = image.jpegData(compressionQuality: quality) else {
                throw NSError(domain: "FolioMind.Image", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image."])
            }
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    /// Normalize orientation to .up to ensure Vision and cropping work predictably.
    static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? image
    }

    /// Downscale an image if any dimension exceeds `maxDimension`.
    static func downscaleIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Normalize, downscale, and auto-crop an image for ingestion. Falls back gracefully if Vision fails.
    static func processForIngestion(_ image: UIImage, maxDimension: CGFloat = 2400) async -> UIImage {
        let prepared = preparePreviewImage(from: image, maxDimension: maxDimension)
        if let cropped = try? await autoCrop(prepared) {
            return cropped
        }
        return prepared
    }

    /// Produce JPEG data from raw image data after applying normalization and auto-crop.
    static func processedJPEGData(from data: Data, quality: CGFloat = 0.9) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let processed = await processForIngestion(image)
        return processed.jpegData(compressionQuality: quality)
    }

    /// Load an image from disk, auto-crop/normalize it, and write it back to the same URL.
    static func processFileInPlace(_ url: URL, quality: CGFloat = 0.9) async -> URL? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let processedData = await processedJPEGData(from: data, quality: quality) else { return nil }

        #if canImport(ImageIO)
        let metadata = copyImageMetadata(from: url)
        #endif

        do {
            #if canImport(ImageIO)
            if let metadata, let merged = embedMetadata(metadata, into: processedData) {
                try merged.write(to: url, options: .atomic)
                return url
            }
            #endif

            try processedData.write(to: url, options: .atomic)
            return url
        } catch {
            print("Failed to write processed image to disk: \(error)")
            return nil
        }
    }

    #if canImport(ImageIO)
    private static func copyImageMetadata(from url: URL) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    }

    private static func embedMetadata(_ metadata: [String: Any], into imageData: Data) -> Data? {
        let output = NSMutableData()

        let destinationType: CFString
        #if canImport(UniformTypeIdentifiers)
        destinationType = UTType.jpeg.identifier as CFString
        #else
        destinationType = "public.jpeg" as CFString
        #endif

        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let destination = CGImageDestinationCreateWithData(output, destinationType, 1, nil)
        else {
            return nil
        }

        var updatedMetadata = metadata
        updatedMetadata[kCGImagePropertyOrientation as String] = 1

        CGImageDestinationAddImageFromSource(destination, source, 0, updatedMetadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
    #endif
}
