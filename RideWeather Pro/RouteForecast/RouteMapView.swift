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

    // Inputs from parent
    let routePolyline: [CLLocationCoordinate2D]
    let displayedAnnotations: [RouteWeatherPoint]
    let scrubbingMarkerCoordinate: CLLocationCoordinate2D?

    var body: some View {
        Map(position: $cameraPosition) {

            // 1️⃣ Route polyline
            if !routePolyline.isEmpty {
                let gradient = LinearGradient(
                    colors: [.cyan, .blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                let style = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)

                MapPolyline(coordinates: routePolyline)
                    .stroke(gradient, style: style)
            }

            // 2️⃣ Weather annotations (hidden while scrubbing)
            if scrubbingMarkerCoordinate == nil {
                ForEach(displayedAnnotations) { point in
                    Annotation("Weather Point", coordinate: point.coordinate) {
                        ModernWeatherAnnotationView(weatherPoint: point)
                            .environmentObject(viewModel)
                    }
                    .annotationTitles(.hidden)
                }
            }

            // 3️⃣ Red scrubbing marker (persistent & stable)
            if let scrubbingCoordinate = scrubbingMarkerCoordinate {
                Annotation("ScrubbingMarker-\(scrubbingCoordinate.latitude)-\(scrubbingCoordinate.longitude)",
                           coordinate: scrubbingCoordinate) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .zIndex(10)
                }
                .annotationTitles(.hidden)
                .annotationSubtitles(.hidden)
            }
        }
        // 4️⃣ Map appearance
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControlVisibility(.hidden)
    }
}
