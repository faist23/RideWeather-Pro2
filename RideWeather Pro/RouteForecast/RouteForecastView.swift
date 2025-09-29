import SwiftUI
import MapKit
import UniformTypeIdentifiers
import CoreLocation

struct RouteForecastView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isImporting = false
    @FocusState private var isSpeedFieldFocused: Bool
    @State private var showBottomControls = true
    @State private var estimatedRideTime: String? = nil
    @State private var navigationPath = NavigationPath()

    let supportedTypes: [UTType] = [
        UTType(filenameExtension: "gpx")!,
        UTType(filenameExtension: "fit")!,
    ]
    
    @State private var cameraPosition = MapCameraPosition.camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                  distance: 50000)
    )
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                mapContent
                    .onAppear {
                        viewModel.centerMapOnRoute(&cameraPosition)
                        updateEstimatedRideTime()
                    }
                    .onChange(of: viewModel.routePoints.count) { _, _ in
                        viewModel.centerMapOnRoute(&cameraPosition)
                        updateEstimatedRideTime()
                    }
                    .onChange(of: viewModel.averageSpeedInput) { _, _ in
                        updateEstimatedRideTime()
                    }
                    .ignoresSafeArea(edges: .bottom)

                if viewModel.routePoints.isEmpty {
                    emptyStateView
                        .transition(.blurReplace.combined(with: .scale))
                }
                
                VStack {
                    topStatusBar
                    Spacer()
                    if showBottomControls {
                        RouteBottomControlsView(isImporting: $isImporting,
                                                isSpeedFieldFocused: _isSpeedFieldFocused,
                                                showBottomControls: $showBottomControls)
                        .environmentObject(viewModel)
                        .transition(.move(edge: .bottom).combined(with: .blurReplace))
                    } else {
                        showControlsButton
                            .transition(.blurReplace)
                    }
                }
            }
            .animation(.smooth, value: showBottomControls)
            .animation(.smooth, value: viewModel.uiState)
            .navigationTitle("Route Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isSpeedFieldFocused = false }
                        .fontWeight(.semibold)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !viewModel.routePoints.isEmpty {
                        Button { withAnimation(.smooth) { viewModel.centerMapOnRoute(&cameraPosition) } } label: {
                            Image(systemName: "scope")
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: supportedTypes) { result in
                if case .success(let url) = result {
                    viewModel.importRoute(from: url)
                    updateEstimatedRideTime()
                }
            }
        }
    }
    
    // MARK: - Map Content
    private var mapContent: some View {
        Map(position: $cameraPosition) {
            if !viewModel.routePoints.isEmpty {
                routePolyline
            }
            weatherAnnotations
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .mapControlVisibility(.hidden)
    }
    
    private var routePolyline: some MapContent {
        let gradient = LinearGradient(colors: [.cyan, .blue, .purple],
                                      startPoint: .leading,
                                      endPoint: .trailing)
        let style = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        return MapPolyline(coordinates: viewModel.routePoints)
            .stroke(gradient, style: style)
    }
    
    private var weatherAnnotations: some MapContent {
        ForEach(viewModel.weatherDataForRoute) { point in
            Annotation("Weather Point", coordinate: point.coordinate) {
                ModernWeatherAnnotationView(weatherPoint: point)
                    .environmentObject(viewModel)
            }
            .annotationTitles(.hidden)
            .annotationSubtitles(.automatic)
        }
    }
    
    // MARK: - Top Bar
    private var topStatusBar: some View {
        HStack {
            if case .parsing(let progress) = viewModel.uiState {
                ModernProgressView(progress: progress, label: "Parsing Route")
                    .transition(.blurReplace)
            } else if let timeString = estimatedRideTime {
                EstimatedTimeChip(timeString: timeString)
                    .transition(.blurReplace)
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 25) {
                Text("Import Your Route")
                    .font(.title2.weight(.semibold))
                Text("Upload a GPX or FIT file to see weather forecasts along your cycling route")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button { isImporting = true } label: {
                Label("Import Route File", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
    }
    
    private var showControlsButton: some View {
        Button { withAnimation(.smooth) { showBottomControls = true } } label: {
            Label("Show Controls", systemImage: "chevron.up.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Helpers
    private func updateEstimatedRideTime() {
        guard viewModel.routePoints.count >= 2 else {
            estimatedRideTime = nil
            return
        }
        var totalDistance: Double = 0
        for i in 1..<viewModel.routePoints.count {
            let loc1 = CLLocation(latitude: viewModel.routePoints[i - 1].latitude,
                                   longitude: viewModel.routePoints[i - 1].longitude)
            let loc2 = CLLocation(latitude: viewModel.routePoints[i].latitude,
                                   longitude: viewModel.routePoints[i].longitude)
            totalDistance += loc2.distance(from: loc1)
        }
        let speedMps = averageSpeedMetersPerSecond()
        guard speedMps > 0 else {
            estimatedRideTime = nil
            return
        }
        let durationSeconds = totalDistance / speedMps
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        estimatedRideTime = formatter.string(from: durationSeconds) ?? "N/A"
    }
    
    private func averageSpeedMetersPerSecond() -> Double {
        if let speedVal = Double(viewModel.averageSpeedInput) {
            return viewModel.settings.units == .metric
                ? speedVal * 1000 / 3600
                : speedVal * 0.44704
        }
        return 0
    }
}
