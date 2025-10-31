
//
// RouteForecastView.swift — Fixed Controls, Auto Analysis, Draggable Panel
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers
import CoreLocation

struct RouteForecastView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @State private var isImporting = false
    @State private var showingStravaImport = false

    @State private var selectedWeatherPoint: RouteWeatherPoint? = nil
    @State private var showWeatherDetail = false

    // Slide-out analysis panel
    @State private var panelState: SlideOutPanelState = .hidden

    // Controls sheet state
    @State private var showBottomControls = true
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var showingAnalysis = false

    // File import feedback
    @State private var showImportSuccess = false
    @State private var importedFileName: String = ""

    let supportedTypes: [UTType] = [
        UTType(filenameExtension: "gpx")!,
        UTType(filenameExtension: "fit")!,
    ]

    @State private var cameraPosition = MapCameraPosition.camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.334_900, longitude: -122.009_020),
            distance: 50000
        )
    )

    var body: some View {
        NavigationStack {
            ZStack {
                // Optimized Map with progressive loading
                RouteMapView(cameraPosition: $cameraPosition)
                    .environmentObject(viewModel)

                // Slide-Out Analysis Panel
                SlideOutAnalysisPanel(panelState: $panelState, edge: .trailing) {
                    VStack(spacing: 12) {
                        UnifiedRouteAnalyticsCard()
                            .environmentObject(viewModel)
                            .padding()
                    }
                }

                // Floating toggle button (independent)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.smooth) {
                                panelState = (panelState == .hidden) ? .expanded : .hidden
                            }
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                                .font(.largeTitle)
                                .padding()
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .overlay(alignment: .top) {
                // Import success banner
                if showImportSuccess {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Route imported successfully!")
                                .font(.subheadline.weight(.semibold))
                            
                            if !importedFileName.isEmpty {
                                Text(importedFileName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .onAppear {
                if let location = viewModel.currentLocation {
                    centerMap(on: location.coordinate)
                }
            }
            .onChange(of: viewModel.currentLocation) { _, newLocation in
                if let location = newLocation {
                    centerMap(on: location.coordinate)
                }
            }
            .onChange(of: viewModel.routePoints.count) { oldCount, newCount in
                // Detect successful route import
                if oldCount == 0 && newCount > 0 {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        showImportSuccess = true
                    }
                    
                    // Auto-hide success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            showImportSuccess = false
                        }
                    }
                }
            }
            // Auto-open analysis panel after forecast is ready
            .onChange(of: viewModel.isLoading) { _, loading in
                if !loading && !viewModel.weatherDataForRoute.isEmpty {
                    withAnimation(.smooth) {
                        panelState = .expanded
                    }
                }
            }
            .animation(.smooth, value: viewModel.uiState)
            .navigationTitle("Route Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !viewModel.routePoints.isEmpty {
                        Button {
                            withAnimation(.smooth) {
                                viewModel.centerMapOnRoute(&cameraPosition)
                            }
                        } label: {
                            Image(systemName: "scope")
                        }
                    }
                    
                    // ✅ Strava import button
                    if stravaService.isAuthenticated {
                        Button {
                            showingStravaImport = true
                        } label: {
                            Image(systemName: "figure.outdoor.cycle")
                        }
                    }
                }
            }
            // Weather + analytics sheets
            .sheet(isPresented: $showWeatherDetail) {
                if let point = selectedWeatherPoint {
                    WeatherDetailSheet(weatherPoint: point)
                        .environmentObject(viewModel)
                }
            }
            .sheet(isPresented: $showingAnalysis) {
                OptimizedUnifiedRouteAnalyticsDashboard()
                    .environmentObject(viewModel)
            }

            // Controls sheet with file import feedback
            .sheet(isPresented: $showBottomControls) {
                NavigationStack {
                    ModernRouteBottomControlsView(
                        isImporting: $isImporting,
                        showBottomControls: $showBottomControls,
                        importedFileName: $importedFileName
                    )
                    .environmentObject(viewModel)
                    .navigationTitle("Controls")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.fraction(0.25), .medium, .large], selection: $selectedDetent)
                .presentationDragIndicator(.visible)
                .fileImporter(isPresented: $isImporting, allowedContentTypes: supportedTypes) { result in
                    switch result {
                    case .success(let url):
                        // Extract filename for display
                        let fileName = url.lastPathComponent
                        importedFileName = String(fileName.prefix(20)) // Limit length for display
                        
                        // Immediate haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        
                        // Import the route
                        viewModel.importRoute(from: url)
                        
                        // Keep controls visible
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showBottomControls = true
                        }
                        
                    case .failure(let error):
                        print("File import failed: \(error.localizedDescription)")
                        
                        // Error haptic feedback
                        let notificationFeedback = UINotificationFeedbackGenerator()
                        notificationFeedback.notificationOccurred(.error)
                    }
                }
            }
            // ✅ ADD THIS: Strava import sheet
            .sheet(isPresented: $showingStravaImport) {
                StravaRouteImportView()
                    .environmentObject(stravaService)
                    .environmentObject(viewModel)
            }
            // ✅ Add this to debug - watch for route changes
            .onChange(of: viewModel.routePoints.count) { oldValue, newValue in
                print("🟢 Route points changed: \(oldValue) -> \(newValue)")
                if newValue > 0 {
                    print("🟢 Route loaded with \(newValue) points")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !viewModel.isLoading && !showBottomControls {
                    Button {
                        withAnimation { showBottomControls = true }
                    } label: {
                        Label("Show Controls", systemImage: "chevron.up.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    // MARK: - Helpers
    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: 60000
            )
        )
    }
}

// MARK: - Panel State
enum SlideOutPanelState {
    case hidden
    case expanded
}

// MARK: - Slide-Out Panel (flush grab handle, draggable)
struct SlideOutAnalysisPanel<Content: View>: View {
    @Binding var panelState: SlideOutPanelState
    var edge: Edge = .trailing
    let content: Content

    @GestureState private var dragOffset: CGFloat = 0

    init(panelState: Binding<SlideOutPanelState>, edge: Edge = .trailing, @ViewBuilder content: () -> Content) {
        self._panelState = panelState
        self.edge = edge
        self.content = content()
    }

    private var panelWidth: CGFloat { 320 }
    private var hiddenOffset: CGFloat { edge == .trailing ? panelWidth + 24 : -(panelWidth + 24) }

    var body: some View {
        ZStack {
            if panelState == .expanded {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.smooth) { panelState = .hidden } }
            }

            HStack {
                if edge == .trailing { Spacer() }

                VStack(spacing: 0) {
                    content
                }
                .frame(width: panelWidth)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(radius: 10)
                .offset(x: baseOffset + dragOffset)
                .overlay(alignment: edge == .trailing ? .leading : .trailing) {
                    ZStack {
                        Color.clear
                            .frame(width: 24)
                            .contentShape(Rectangle())
                            .gesture(dragGesture)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 16)
                }
                .transition(.move(edge: edge))

                if edge == .leading { Spacer() }
            }
        }
        .animation(.smooth, value: panelState)
    }

    private var baseOffset: CGFloat {
        panelState == .expanded ? 0 : hiddenOffset
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                let dx = value.translation.width
                if edge == .trailing {
                    state = max(-panelWidth, min(0, dx))
                } else {
                    state = min(panelWidth, max(0, dx))
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 80
                if edge == .trailing {
                    if value.translation.width < -threshold {
                        withAnimation(.smooth) { panelState = .hidden }
                    } else {
                        withAnimation(.smooth) { panelState = .expanded }
                    }
                } else {
                    if value.translation.width > threshold {
                        withAnimation(.smooth) { panelState = .hidden }
                    } else {
                        withAnimation(.smooth) { panelState = .expanded }
                    }
                }
            }
    }
}

struct AnalysisPromptView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct UnifiedRouteAnalyticsCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var showingFullAnalysis = false
    
    // This state now holds our calculated result
    @State private var analysisResult: ComprehensiveRouteAnalysis? = nil
    // This dedicated state tracks the loading process
    @State private var isLoading = false

    var body: some View {
        Group {
            if viewModel.routePoints.isEmpty {
                AnalysisPromptView(icon: "doc.badge.plus", text: "Import a route to see your analysis.")
            } else if viewModel.weatherDataForRoute.isEmpty {
                AnalysisPromptView(icon: "cloud.sun", text: "Tap 'Get Forecast' in the Controls to analyze your route.")
            } else if isLoading {
                // Show the spinner only when isLoading is true
                ProgressView("Analyzing...")
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if let analysis = analysisResult {
                // This is the success state, showing the full card.
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(analysis.overallScore.rating.color)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Complete Route Analysis")
                                .font(.headline.weight(.semibold))
                            
                            HStack(spacing: 8) {
                                Text(analysis.overallScore.rating.emoji)
                                    .font(.subheadline)
                                
                                Text(analysis.overallScore.rating.label)
                                    .font(.subheadline)
                                    .foregroundStyle(analysis.overallScore.rating.color)
                            }
                        }
                        
                        Spacer()
                        
                        ZStack {
                            Circle().stroke(.quaternary, lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: analysis.overallScore.overall / 100)
                                .stroke(analysis.overallScore.rating.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(analysis.overallScore.overall))")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(analysis.overallScore.rating.color)
                        }
                        .frame(width: 36, height: 36)
                    }
                    
                    HStack(spacing: 16) {
                        QuickInsightChip(icon: "shield.fill", label: "Safety", value: "\(Int(analysis.safetyScore.score))", color: analysis.safetyScore.level.color)
                        QuickInsightChip(icon: analysis.daylightAnalysis.totalDarkDistance > 0 ? "moon.fill" : "sun.max.fill", label: "Lighting", value: analysis.daylightAnalysis.visibilityRating.label, color: analysis.daylightAnalysis.visibilityRating.color)
                        QuickInsightChip(icon: "thermometer", label: "Weather", value: analysis.weatherSafety.overallSafetyRating == .safe ? "Good" : "Caution", color: analysis.weatherSafety.overallSafetyRating.color)
                    }
                    
                    Button {
                        showingFullAnalysis = true
                    } label: {
                        Label("View Complete Analysis", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(analysis.overallScore.rating.color)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .sheet(isPresented: $showingFullAnalysis) {
                    OptimizedUnifiedRouteAnalyticsDashboard()
                        .environmentObject(viewModel)
                }
            }
        }
        // This .task modifier is the key to the fix.
        // It runs when the view appears OR when the weather data count changes.
        .task(id: viewModel.weatherDataForRoute.count) {
            guard !viewModel.weatherDataForRoute.isEmpty else {
                analysisResult = nil
                return
            }

            isLoading = true
            
            // The engine is created and used safely within the task.
             let analytics = UnifiedRouteAnalyticsEngine(
               weatherPoints: viewModel.weatherDataForRoute,
               rideStartTime: viewModel.rideDate,
               averageSpeed: viewModel.averageSpeedMetersPerSecond,
               settings: viewModel.settings,
               location: viewModel.routePoints.first ?? CLLocationCoordinate2D(),
               hourlyForecasts: viewModel.allHourlyData,
               elevationAnalysis: viewModel.elevationAnalysis
            )
                // The calculation happens here.
            self.analysisResult = analytics.comprehensiveAnalysis
            
            isLoading = false
        }
        .animation(.default, value: isLoading)
        .animation(.default, value: analysisResult?.overallScore.overall)
    }
}

struct QuickInsightChip: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

