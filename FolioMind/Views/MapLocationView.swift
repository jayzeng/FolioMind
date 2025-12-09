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
    let locations: [DocumentLocation]  // New: use structured locations
    let onEdit: ((DocumentLocation) -> Void)?  // Optional edit callback
    let onAddLabel: (() -> Void)?  // Callback to trigger adding labels to legacy locations

    @State private var position: MapCameraPosition = .automatic
    @State private var resolvedLocations: [ResolvedLocation] = []
    @State private var isResolving: Bool = false

    struct ResolvedLocation: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let coordinate: CLLocationCoordinate2D
        let category: LocationCategory
        let sourceLocation: DocumentLocation?  // Link back to original location for editing
    }

    init(
        locationStrings: [String] = [],
        locations: [DocumentLocation] = [],
        onEdit: ((DocumentLocation) -> Void)? = nil,
        onAddLabel: (() -> Void)? = nil
    ) {
        self.locationStrings = locationStrings
        self.locations = locations
        self.onEdit = onEdit
        self.onAddLabel = onAddLabel
    }

    var body: some View {
        VStack(spacing: 8) {
            if !resolvedLocations.isEmpty {
                Map(position: $position) {
                    ForEach(resolvedLocations) { location in
                        Annotation(location.title, coordinate: location.coordinate) {
                            Button {
                                if let sourceLocation = location.sourceLocation {
                                    onEdit?(sourceLocation)
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(categoryColor(location.category).opacity(0.2))
                                            .frame(width: 38, height: 38)

                                        Image(systemName: location.category.icon)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(categoryColor(location.category))
                                            .background(
                                                Circle()
                                                    .fill(.white)
                                                    .frame(width: 26, height: 26)
                                            )
                                    }
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                                    if let subtitle = location.subtitle {
                                        Text(subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .frame(maxWidth: 100)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .animation(.easeInOut, value: resolvedLocations.count)

                HStack(spacing: 16) {
                    // Add Label button (for legacy locations without labels)
                    if !locationStrings.isEmpty && locations.isEmpty, let onAddLabel = onAddLabel {
                        Button {
                            onAddLabel()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tag.fill")
                                    .font(.caption)
                                Text("Add Label")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(.orange)
                            .padding(.vertical, 6)
                        }
                    }

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
        .task(id: taskID) {
            await resolveLocations()
        }
    }

    private var taskID: String {
        if !locations.isEmpty {
            return locations.map { $0.id.uuidString }.joined(separator: "|")
        }
        return locationStrings.joined(separator: "|")
    }

    // MARK: - Location Resolution

    @MainActor
    private func resolveLocations() async {
        // Prioritize new structured locations over old locationStrings
        if !locations.isEmpty {
            await resolveStructuredLocations()
        } else if !locationStrings.isEmpty {
            await resolveLegacyLocations()
        } else {
            resolvedLocations = []
        }
    }

    @MainActor
    private func resolveStructuredLocations() async {
        isResolving = true
        defer { isResolving = false }

        var pins: [ResolvedLocation] = []

        for location in locations {
            let trimmed = location.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var coords: CLLocationCoordinate2D?

            if location.type == .coordinate {
                coords = parseCoordinates(from: trimmed)
            } else {
                coords = await geocodeAddress(trimmed)
            }

            if let coords = coords {
                pins.append(ResolvedLocation(
                    title: location.label.isEmpty ? location.rawValue : location.label,
                    subtitle: location.label.isEmpty ? nil : formatSubtitle(location.rawValue),
                    coordinate: coords,
                    category: location.category,
                    sourceLocation: location
                ))
            }
        }

        resolvedLocations = pins

        if let region = regionThatFits(pins) {
            position = .region(region)
        }
    }

    @MainActor
    private func resolveLegacyLocations() async {
        isResolving = true
        defer { isResolving = false }

        var pins: [ResolvedLocation] = []

        for (index, rawLocation) in locationStrings.enumerated() {
            let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let coords = parseCoordinates(from: trimmed) {
                pins.append(ResolvedLocation(
                    title: displayTitle(for: trimmed, index: index),
                    subtitle: nil,
                    coordinate: coords,
                    category: .custom,
                    sourceLocation: nil
                ))
                continue
            }

            if let coords = await geocodeAddress(trimmed) {
                pins.append(ResolvedLocation(
                    title: displayTitle(for: trimmed, index: index),
                    subtitle: nil,
                    coordinate: coords,
                    category: .custom,
                    sourceLocation: nil
                ))
            }
        }

        resolvedLocations = pins

        if let region = regionThatFits(pins) {
            position = .region(region)
        }
    }

    private func formatSubtitle(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 30 {
            return String(cleaned.prefix(27)) + "..."
        }
        return cleaned
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

    private func categoryColor(_ category: LocationCategory) -> Color {
        switch category {
        case .home: return .blue
        case .work: return .orange
        case .school: return .purple
        case .medical: return .red
        case .custom: return .pink
        }
    }

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
