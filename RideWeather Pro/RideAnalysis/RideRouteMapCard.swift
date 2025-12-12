//
//  RideRouteMapCard.swift
//  RideWeather Pro
//

import SwiftUI
import MapKit

struct RideRouteMapCard: View {
    let routeBreadcrumbs: [CLLocationCoordinate2D]
    let analysisID: UUID
    
    @State private var mapImage: Image?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    ProgressView()
                }
            } else if let mapImage {
                mapImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    Text("Map Unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .task(id: analysisID) {
            await generateSnapshot()
        }
    }
    
    private func generateSnapshot() async {
        await MainActor.run {
            isLoading = true
        }
        
        let snapshotterOptions = MKMapSnapshotter.Options()
        
        // Set the region for the map
        snapshotterOptions.region = boundingRegion(for: routeBreadcrumbs)
        
        // Use standard map type (works on all iOS versions)
        snapshotterOptions.mapType = .standard
        
        // Set the output size
        let size = CGSize(width: 600, height: 400)
        snapshotterOptions.size = size
        snapshotterOptions.showsBuildings = false
        
        let snapshotter = MKMapSnapshotter(options: snapshotterOptions)
        
        do {
            let snapshot = try await snapshotter.start()
            let finalImage = drawPolyline(on: snapshot)
            
            await MainActor.run {
                self.mapImage = Image(uiImage: finalImage)
                self.isLoading = false
            }
        } catch {
            print("Failed to generate map snapshot: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    /// Draws the polyline onto the generated map snapshot
    private func drawPolyline(on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let image = snapshot.image
        
        // Create a UIGraphicsImageRenderer
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            // 1. Draw the map image first
            image.draw(at: .zero)
            
            // 2. Get the Core Graphics context
            let cgContext = context.cgContext
            
            // 3. Convert coordinates to points on the image
            let points = routeBreadcrumbs.map { snapshot.point(for: $0) }
            
            // 4. Create the path
            let path = CGMutablePath()
            if !points.isEmpty {
                path.addLines(between: points)
            }
            
            // 5. Configure and draw the path
            cgContext.addPath(path)
            cgContext.setStrokeColor(UIColor.systemYellow.cgColor)
            cgContext.setLineWidth(4.0)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            cgContext.strokePath()
        }
    }

    /// Calculates the bounding box region for all coordinates
    private func boundingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }

        var minLat = coordinates.first!.latitude
        var maxLat = coordinates.first!.latitude
        var minLon = coordinates.first!.longitude
        var maxLon = coordinates.first!.longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        
        let latDelta = max((maxLat - minLat) * 1.4, 0.01) // Add 40% padding, minimum 0.01
        let lonDelta = max((maxLon - minLon) * 1.4, 0.01) // Add 40% padding, minimum 0.01
        
        let span = MKCoordinateSpan(
            latitudeDelta: latDelta,
            longitudeDelta: lonDelta
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
}
