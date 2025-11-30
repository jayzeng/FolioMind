//
//  ImageMetadataExtractor.swift
//  FolioMind
//
//  Extracts lightweight EXIF metadata (location + capture time) for assets.
//

import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

struct ImageMetadata {
    let locationDescription: String?
    let captureDate: Date?
}

protocol ImageMetadataExtracting {
    func extract(from imageURL: URL) -> ImageMetadata
}

struct ImageMetadataExtractor: ImageMetadataExtracting {
    func extract(from imageURL: URL) -> ImageMetadata {
#if canImport(ImageIO)
        guard
            let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return ImageMetadata(locationDescription: nil, captureDate: nil)
        }

        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let location = formattedLocation(from: gps)
        let captureDate = parseCaptureDate(from: exif)
        return ImageMetadata(locationDescription: location, captureDate: captureDate)
#else
        return ImageMetadata(locationDescription: nil, captureDate: nil)
#endif
    }

#if canImport(ImageIO)
    private func formattedLocation(from gps: [CFString: Any]?) -> String? {
        guard let gps else { return nil }

        guard
            let rawLat = gps[kCGImagePropertyGPSLatitude],
            let rawLon = gps[kCGImagePropertyGPSLongitude]
        else { return nil }

        guard let lat = number(from: rawLat), let lon = number(from: rawLon) else {
            return nil
        }

        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()

        let normalizedLat = (latRef == "S") ? -lat : lat
        let normalizedLon = (lonRef == "W") ? -lon : lon

        return String(format: "%.4f, %.4f", normalizedLat, normalizedLon)
    }

    private func parseCaptureDate(from exif: [CFString: Any]?) -> Date? {
        guard let exif else { return nil }
        let dateKeys: [CFString] = [
            kCGImagePropertyExifDateTimeOriginal,
            kCGImagePropertyExifDateTimeDigitized
        ]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for key in dateKeys {
            if let value = exif[key] as? String, let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func number(from value: Any) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }
#endif
}
