//
//  MapLocationView.swift
//  FolioMind
//
//  Displays a map with a pin at the document's capture location.
//

import SwiftUI
import MapKit

struct MapLocationView: View {
    let locationString: String

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedLocation: CLLocationCoordinate2D?

    private var coordinates: CLLocationCoordinate2D? {
        parseCoordinates(from: locationString)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let coords = coordinates {
                Map(position: $position) {
                    Annotation("Captured Here", coordinate: coords) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.3))
                                .frame(width: 40, height: 40)

                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                                .background(
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 24, height: 24)
                                )
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear {
                    // Set initial camera position to the coordinates
                    position = .region(MKCoordinateRegion(
                        center: coords,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }

                // Open in Apple Maps button
                Button {
                    openInMaps(coordinates: coords)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                            .font(.caption)
                        Text("Open in Apple Maps")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.blue)
                    .padding(.vertical, 8)
                }
            } else {
                // Fallback if coordinates can't be parsed
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

    /// Opens the location in Apple Maps
    private func openInMaps(coordinates: CLLocationCoordinate2D) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinates))
        mapItem.name = "Document Capture Location"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinates),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        ])
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // San Francisco coordinates
        MapLocationView(locationString: "37.7749, -122.4194")
            .padding()

        // Invalid coordinates
        MapLocationView(locationString: "Invalid location")
            .padding()
    }
}
