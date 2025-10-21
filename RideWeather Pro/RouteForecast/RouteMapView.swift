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
    
    // Progressive loading states
    @State private var showRoute = false
    @State private var showWeatherAnnotations = false
    @State private var useRealisticElevation = false
    
    // Add ID to force view recreation when route changes
    @State private var mapID = UUID()

    var body: some View {
        Map(position: $cameraPosition) {
            // Show route first (fastest to render)
            if showRoute && !viewModel.routePoints.isEmpty {
                let gradient = LinearGradient(
                    colors: [.cyan, .blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                let style = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)

                MapPolyline(coordinates: viewModel.routePoints)
                    .stroke(gradient, style: style)
            }

            // Load weather annotations after route is visible
            if showWeatherAnnotations {
                ForEach(viewModel.weatherDataForRoute) { point in
                   Annotation("Weather Point", coordinate: point.coordinate) {
                        ModernWeatherAnnotationView(weatherPoint: point)
                            .environmentObject(viewModel)
                    }
                    .annotationTitles(.hidden)
                    .annotationSubtitles(.automatic)
                }
            }
        }
        .id(mapID) // Force view recreation when route changes
        // Start with flat elevation for faster initial render
        .mapStyle(useRealisticElevation ?
                 .standard(elevation: .realistic, emphasis: .muted) :
                 .standard(elevation: .flat, emphasis: .muted))
        .mapControlVisibility(.hidden)
        .onAppear {
            centerToCurrentRoute()
            loadMapContentProgressively()
        }
        .onChange(of: viewModel.routePoints.count) { oldCount, newCount in
            // Reset and reload when route changes
            // Force immediate cleanup of old map
            if oldCount > 0 && newCount == 0 {
                // Route was cleared - reset immediately and force recreation
                resetMapState()
                mapID = UUID()
            } else if newCount > 0 {
                // New route loaded or route changed - full reset
                resetAndReload()
            }
        }
        .onDisappear {
            // Critical: Clean up map state when view disappears
            resetMapState()
        }
    }
    
    private func resetMapState() {
        showRoute = false
        showWeatherAnnotations = false
        useRealisticElevation = false
    }
    
    private func loadMapContentProgressively() {
        guard !viewModel.routePoints.isEmpty else { return }
        
        // Step 1: Show route immediately
        withAnimation(.easeOut(duration: 0.2)) {
            showRoute = true
        }
        
        // Step 2: Add weather annotations after slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.4)) {
                showWeatherAnnotations = true
            }
        }
        
        // Step 3: Upgrade to realistic elevation after content is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.5)) {
                useRealisticElevation = true
            }
        }
    }
    
    private func resetAndReload() {
        // Reset states
        resetMapState()
        
        // Force map recreation with new ID
        mapID = UUID()
        
        // Restart progressive loading after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            centerToCurrentRoute()
            loadMapContentProgressively()
        }
    }

    private func centerToCurrentRoute() {
        guard !viewModel.routePoints.isEmpty else { return }

        let coordinates = viewModel.routePoints

        let minLat = coordinates.map(\.latitude).min() ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? 0
        let minLon = coordinates.map(\.longitude).min() ?? 0
        let maxLon = coordinates.map(\.longitude).max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0  // Fixed: was minLon + minLon
        )

        let latDelta = max(abs(maxLat - minLat) * 1.3, 0.01)
        let lonDelta = max(abs(maxLon - minLon) * 1.3, 0.01)

        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        let region = MKCoordinateRegion(center: center, span: span)

        cameraPosition = .region(region)
    }
}
