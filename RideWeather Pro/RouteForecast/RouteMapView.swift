//
//  RouteMapView.swift
//  RideWeather Pro
//

import SwiftUI
import MapKit
import CoreLocation

struct RouteMapView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Binding var cameraPosition: MapCameraPosition

    var body: some View {
        Map(position: $cameraPosition) {
            // Route polyline (only when we have points)
            if !viewModel.routePoints.isEmpty {
                let gradient = LinearGradient(
                    colors: [.cyan, .blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                let style = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)

                MapPolyline(coordinates: viewModel.routePoints)
                    .stroke(gradient, style: style)
            }

            // Weather annotations
            ForEach(viewModel.weatherDataForRoute) { point in
                Annotation("Weather Point", coordinate: point.coordinate) {
                    ModernWeatherAnnotationView(weatherPoint: point)
                        .environmentObject(viewModel)
                }
                .annotationTitles(.hidden)
                .annotationSubtitles(.automatic)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControlVisibility(.hidden)
        .onAppear {
            centerToCurrentRoute()
        }
        .onChange(of: viewModel.routePoints.count) { _, _ in
            centerToCurrentRoute()
        }
    }

    // MARK: - Centering

    /// Centers the map to fit the current route points with some padding.
    private func centerToCurrentRoute() {
        guard !viewModel.routePoints.isEmpty else { return }

        let coordinates = viewModel.routePoints

        // Compute min/max
        let minLat = coordinates.map(\.latitude).min() ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? 0
        let minLon = coordinates.map(\.longitude).min() ?? 0
        let maxLon = coordinates.map(\.longitude).max() ?? 0

        // Center and span (with padding)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        let latDelta = max(abs(maxLat - minLat) * 1.3, 0.01)
        let lonDelta = max(abs(maxLon - minLon) * 1.3, 0.01)

        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        let region = MKCoordinateRegion(center: center, span: span)

        cameraPosition = .region(region)
    }
}
