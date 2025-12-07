//
//  MapLocationView.swift
//  FolioMind
//
//  Displays a map with pins for capture location and parsed addresses.
//

import SwiftUI
import MapKit
import CoreLocation

struct MapLocationView: View {
    let locationStrings: [String]

    @State private var position: MapCameraPosition = .automatic
    @State private var resolvedLocations: [ResolvedLocation] = []
    @State private var isResolving: Bool = false

    struct ResolvedLocation: Identifiable {
        let id = UUID()
        let title: String
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        VStack(spacing: 8) {
            if !resolvedLocations.isEmpty {
                Map(position: $position) {
                    ForEach(resolvedLocations) { location in
                        Annotation(location.title, coordinate: location.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(.blue.opacity(0.3))
                                    .frame(width: 34, height: 34)

                                Image(systemName: "mappin.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.red)
                                    .background(
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 22, height: 22)
                                    )
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .animation(.easeInOut, value: resolvedLocations.count)

                Button {
                    openInMaps(locations: resolvedLocations)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                            .font(.caption)
                        Text("Open in Apple Maps")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.blue)
                    .padding(.vertical, 6)
                }
            } else if isResolving {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Resolving addresses...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .foregroundStyle(.secondary)
                    Text("Location data unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .task(id: locationStrings.joined(separator: "|")) {
            await resolveLocations()
        }
    }

    // MARK: - Location Resolution

    @MainActor
    private func resolveLocations() async {
        guard !locationStrings.isEmpty else {
            resolvedLocations = []
            return
        }

        isResolving = true
        defer { isResolving = false }

        var pins: [ResolvedLocation] = []

        for (index, rawLocation) in locationStrings.enumerated() {
            let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let coords = parseCoordinates(from: trimmed) {
                pins.append(ResolvedLocation(
                    title: displayTitle(for: trimmed, index: index),
                    coordinate: coords
                ))
                continue
            }

            if let coords = await geocodeAddress(trimmed) {
                pins.append(ResolvedLocation(
                    title: displayTitle(for: trimmed, index: index),
                    coordinate: coords
                ))
            }
        }

        resolvedLocations = pins

        if let region = regionThatFits(pins) {
            position = .region(region)
        }
    }

    private func geocodeAddress(_ address: String) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.geocodeAddressString(address) { placemarks, _ in
                if let coordinate = placemarks?.first?.location?.coordinate {
                    continuation.resume(returning: coordinate)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func displayTitle(for raw: String, index: Int) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 28 {
            let prefix = cleaned.prefix(25)
            return "Location \(index + 1): \(prefix)..."
        }
        return "Location \(index + 1): \(cleaned)"
    }

    private func regionThatFits(_ locations: [ResolvedLocation]) -> MKCoordinateRegion? {
        guard !locations.isEmpty else { return nil }

        if locations.count == 1 {
            let center = locations[0].coordinate
            return MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        let lats = locations.map { $0.coordinate.latitude }
        let lons = locations.map { $0.coordinate.longitude }

        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0

        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.02) * 1.3,
            longitudeDelta: max(maxLon - minLon, 0.02) * 1.3
        )

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - Helper Functions

    /// Parses coordinates from a string in the format "latitude, longitude"
    private func parseCoordinates(from locationString: String) -> CLLocationCoordinate2D? {
        let components = locationString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count == 2,
              let latitude = Double(components[0]),
              let longitude = Double(components[1]),
              latitude >= -90 && latitude <= 90,
              longitude >= -180 && longitude <= 180
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func openInMaps(locations: [ResolvedLocation]) {
        guard !locations.isEmpty else { return }

        let items = locations.map { location in
            let placemark = MKPlacemark(coordinate: location.coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = location.title
            return item
        }

        MKMapItem.openMaps(with: items)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        MapLocationView(locationStrings: ["37.7749, -122.4194", "1600 Amphitheatre Parkway, Mountain View, CA"])
            .padding()

        MapLocationView(locationStrings: [])
            .padding()
    }
}
