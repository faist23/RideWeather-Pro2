//
// RouteForecastView.swift — Improved UX with state-based views
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers
import CoreLocation

// 1. Define RouteViewState
enum RouteViewState {
    case empty
    case routeLoaded
    case analysis
}

// 2. Define Sheet Enum
enum RouteForecastSheet: Identifiable {
    case stravaImport
    case wahooImport
//    case garminImport
    case settings
    case datePicker
    case timePicker
    case reschedule
    
    var id: Self { self }
}

struct RouteForecastView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var wahooService: WahooService
//    @EnvironmentObject var garminService: GarminService
    
    @State private var isImporting = false
    
    // Single sheet state
    @State private var activeSheet: RouteForecastSheet?
    
    @State private var showImportSuccess = false
    @State private var screenHeight: CGFloat = 0
    
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
    
    private var currentView: RouteViewState {
        if !viewModel.weatherDataForRoute.isEmpty {
            return .analysis
        } else if !viewModel.routePoints.isEmpty {
            return .routeLoaded
        } else {
            return .empty
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                switch currentView {
                case .empty:
                    emptyStateView
                case .routeLoaded:
                    routeLoadedView
                case .analysis:
                    analysisView
                }
                
                if showImportSuccess {
                    VStack {
                        importSuccessBanner
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
 
            .animatedBackground(
                gradient: currentView == .empty ? .routeBackground :
                         LinearGradient(colors: [Color(.systemGroupedBackground)],
                                      startPoint: .top,
                                      endPoint: .bottom),
                showDecoration: currentView == .empty,
                decorationColor: .white,
                decorationIntensity: 0.08
            )
            .animation(.smooth, value: currentView)
            
            .navigationTitle("Route Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    toolbarContent
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: supportedTypes) { result in
                handleFileImport(result)
            }
            .sheet(item: $activeSheet) { item in
                switch item {
                case .stravaImport:
                    StravaRouteImportView()
                        .environmentObject(stravaService)
                        .environmentObject(viewModel)
                case .wahooImport:
                    WahooRouteImportView(onDismiss: { activeSheet = nil })
                        .environmentObject(wahooService)
                        .environmentObject(viewModel)
/*                case .garminImport:
                    GarminImportExplainerView()
                        .environmentObject(garminService)
                        .environmentObject(stravaService)
                        .environmentObject(viewModel) */
                case .settings:
                    SettingsView()
                        .environmentObject(viewModel)
                case .datePicker:
                    datePickerSheet
                case .timePicker:
                    timePickerSheet
                case .reschedule:
                    RescheduleRideSheet()
                        .environmentObject(viewModel)
                }
            }
            .onChange(of: viewModel.routePoints.count) { oldCount, newCount in
                handleRouteChange(oldCount: oldCount, newCount: newCount)
            }
        }
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                Spacer().frame(height: 40)
                
                VStack(spacing: 16) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue.gradient)
                        .symbolEffect(.bounce, value: isImporting)
                    
                    Text("Import Your Route")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text("Get weather forecasts and analytics for your cycling route")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                VStack(spacing: 12) {
                    Button { isImporting = true } label: {
                        importButtonLabel(icon: "square.and.arrow.down", title: "Import GPX or FIT File", gradient: [.blue.opacity(0.8), .blue.opacity(0.6)])
                    }
                    .buttonStyle(.plain)
                    
                    if stravaService.isAuthenticated {
                        Button { activeSheet = .stravaImport } label: {
                            importButtonLabel(icon: "figure.outdoor.cycle", title: "Import from Strava", gradient: [.orange.opacity(0.9), .orange.opacity(0.7)])
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if wahooService.isAuthenticated {
                        Button { activeSheet = .wahooImport } label: {
                            importButtonLabel(icon: "figure.outdoor.cycle", title: "Import from Wahoo", gradient: [.blue.opacity(0.9), .cyan.opacity(0.7)])
                        }
                        .buttonStyle(.plain)
                    }
/*                    if garminService.isAuthenticated {
                        Button { activeSheet = .garminImport } label: {
                            importButtonLabel(
                                icon: "figure.outdoor.cycle",
                                title: "Import from Garmin",
                                gradient: [Color.black.opacity(0.8), Color.gray.opacity(0.6)]
                            )
                        }
                        .buttonStyle(.plain)
                    }*/
                }
                .padding(.horizontal, 12)
                
                VStack(spacing: 1) {
                    FeatureRow(icon: "cloud.sun.fill", title: "Weather Forecast", description: "Hour-by-hour conditions along your route")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Route Analytics", description: "Comfort scores, safety insights, and timing")
                    FeatureRow(icon: "bolt.fill", title: "Power Pacing", description: "AI-generated pacing strategies for optimal performance")
                }
                .padding(.horizontal, 12)
                
                Spacer()
            }
        }
    }
    
    private func importButtonLabel(icon: String, title: String, gradient: [Color]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
    
    // MARK: - Route Loaded View
    private var routeLoadedView: some View {
        GeometryReader { geometry in
            ZStack {
                RouteMapView(
                    cameraPosition: $cameraPosition,
                    routePolyline: viewModel.routePoints,
                    displayedAnnotations: [],
                    scrubbingMarkerCoordinate: nil
                )
                .environmentObject(viewModel)
                .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    routeControlsCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .onAppear {
                screenHeight = geometry.size.height
                centerMapWithOffset(screenHeight: geometry.size.height)
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                screenHeight = newHeight
            }
        }
    }
    
    private var routeControlsCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.routeDisplayName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(formatRouteDistance())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation { centerMapWithOffset(screenHeight: screenHeight) }
                } label: {
                    Image(systemName: "scope").font(.title3)
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Ride Time").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button { activeSheet = .datePicker } label: {
                        Text(formattedDate).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.regular)
                    
                    Button { activeSheet = .timePicker } label: {
                        Text(formattedTime).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.regular)
                }
            }
            
            Button {
                Task { await viewModel.calculateAndFetchWeather() }
            } label: {
                HStack {
                    Image(systemName: viewModel.isLoading ? "hourglass" : "play.fill")
                        .symbolEffect(.pulse, isActive: viewModel.isLoading)
                    Text(viewModel.isLoading ? "Generating..." : "Generate Forecast")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isLoading)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 10)
    }
    
    // MARK: - Analysis View
    private var analysisView: some View {
        ZStack {
            OptimizedUnifiedRouteAnalyticsDashboard()
                .environmentObject(viewModel)
            
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Updating Forecast...")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - Toolbar Content
    @ViewBuilder
    private var toolbarContent: some View {
        switch currentView {
        case .empty:
            Button { activeSheet = .settings } label: {
                Image(systemName: "gearshape.fill")
            }
            
        case .routeLoaded:
            Button { clearRoute() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            Button { activeSheet = .settings } label: {
                Image(systemName: "gearshape.fill")
            }
            
        case .analysis:
            Button {
                activeSheet = .reschedule
            } label: {
                Label("Reschedule", systemImage: "calendar")
            }
            Button { clearRoute() } label: {
                Label("New Route", systemImage: "plus.circle.fill")
            }
            Button { activeSheet = .settings } label: {
                Image(systemName: "gearshape.fill")
            }
        }
    }
    
    // MARK: - Import Success Banner
    private var importSuccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Route imported successfully!")
                    .font(.subheadline.weight(.semibold))
                
                if !viewModel.routeDisplayName.isEmpty {
                    Text(viewModel.routeDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Date/Time Sheets
    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $viewModel.rideDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { activeSheet = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var timePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Time",
                    selection: $viewModel.rideDate,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .padding()
                Spacer()
            }
            .navigationTitle("Select Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { activeSheet = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Helpers
    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let fileName = url.lastPathComponent
            viewModel.lastImportedFileName = fileName
//            importedFileName = viewModel.routeDisplayName -------no longer using local filename
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            viewModel.importRoute(from: url)
        case .failure(let error):
            print("File import failed: \(error.localizedDescription)")
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.error)
        }
    }
    
    private func handleRouteChange(oldCount: Int, newCount: Int) {
        if oldCount == 0 && newCount > 0 {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showImportSuccess = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.screenHeight > 0 { self.centerMapWithOffset(screenHeight: self.screenHeight) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.5)) { showImportSuccess = false }
            }
        }
    }
    
    private func clearRoute() {
        withAnimation {
            viewModel.clearRoute()
            // ✅ FIXED: Removed setting local 'importedFileName'
        }
    }
    
    private func formatRouteDistance() -> String {
        let totalMeters: Double
        if let authoritativeDistance = viewModel.authoritativeRouteDistanceMeters, authoritativeDistance > 0 {
            totalMeters = authoritativeDistance
        } else if let lastPoint = viewModel.weatherDataForRoute.last {
            totalMeters = lastPoint.distance
        } else if viewModel.routePoints.count > 1 {
            var calculatedMeters: Double = 0
            for i in 0..<(viewModel.routePoints.count - 1) {
                let loc1 = CLLocation(latitude: viewModel.routePoints[i].latitude, longitude: viewModel.routePoints[i].longitude)
                let loc2 = CLLocation(latitude: viewModel.routePoints[i + 1].latitude, longitude: viewModel.routePoints[i + 1].longitude)
                calculatedMeters += loc1.distance(from: loc2)
            }
            totalMeters = calculatedMeters
        } else {
            totalMeters = 0
        }
        if viewModel.settings.units == .metric {
            let km = totalMeters / 1000
            return String(format: "%.2f km", km)
        } else {
            let miles = totalMeters / 1609.34
            return String(format: "%.2f mi", miles)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter.string(from: viewModel.rideDate)
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: viewModel.rideDate)
    }
    
    private func centerMapWithOffset(screenHeight: CGFloat) {
        guard !viewModel.routePoints.isEmpty else { return }
        
        let effectiveHeight = screenHeight > 0 ? screenHeight : 800.0
        self.screenHeight = effectiveHeight
        
        let coords = viewModel.routePoints
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLon = coords.map(\.longitude).min() ?? 0
        let maxLon = coords.map(\.longitude).max() ?? 0
        let centerLat = (minLat + maxLat) / 2.0
        let centerLon = (minLon + maxLon) / 2.0
        let latDelta = max(abs(maxLat - minLat) * 1.4, 0.01)
        let lonDelta = max(abs(maxLon - minLon) * 1.4, 0.01)
        let cardHeight: CGFloat = 320
        let cardPercentage = cardHeight / effectiveHeight
        let offsetLat = centerLat - (latDelta * cardPercentage * 0.5)
        let adjustedCenter = CLLocationCoordinate2D(latitude: offsetLat, longitude: centerLon)
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        cameraPosition = .region(MKCoordinateRegion(center: adjustedCenter, span: span))
    }
}

// MARK: - Reschedule Ride Sheet

struct RescheduleRideSheet: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    DatePicker(
                        "Ride Start Time",
                        selection: $viewModel.rideDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                }
            }
            .navigationTitle("Reschedule Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel Button (Top Left)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                // Update Button (Top Right) - ALWAYS VISIBLE
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        Task {
                            await viewModel.calculateAndFetchWeather()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isLoading)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    }
                }
            }
        }
        // Allows the sheet to expand, preventing cramping
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.3)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}

/*
import SwiftUI
import MapKit
import UniformTypeIdentifiers
import CoreLocation

struct RouteForecastView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var wahooService: WahooService
    @EnvironmentObject var garminService: GarminService
    
    @State private var isImporting = false
    @State private var showingStravaImport = false
    @State private var showingWahooImport = false
    @State private var showingGarminImport = false
    @State private var showingSettings = false
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var showingReschedule = false
    @State private var importedFileName: String = ""
    @State private var showImportSuccess = false
    @State private var screenHeight: CGFloat = 0
    
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
    
    // Determine which view to show based on state
    private var currentView: RouteViewState {
        if !viewModel.weatherDataForRoute.isEmpty {
            return .analysis
        } else if !viewModel.routePoints.isEmpty {
            return .routeLoaded
        } else {
            return .empty
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Main content based on state
                switch currentView {
                case .empty:
                    emptyStateView
                    
                case .routeLoaded:
                    routeLoadedView
                    
                case .analysis:
                    analysisView
                }
                
                // Import success banner (shows over any state)
                if showImportSuccess {
                    VStack {
                        importSuccessBanner
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animatedBackground(
                gradient: currentView == .empty ? .routeBackground :
                         LinearGradient(colors: [Color(.systemGroupedBackground)],
                                      startPoint: .top,
                                      endPoint: .bottom),
                showDecoration: currentView == .empty, // Only show animation on empty state
                decorationColor: .white,
                decorationIntensity: 0.08 // Increased for better visibility on dark background
            )
            .animation(.smooth, value: currentView)
            .navigationTitle("Route Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    toolbarContent
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: supportedTypes) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showingStravaImport) {
                StravaRouteImportView()
                    .environmentObject(stravaService)
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showingWahooImport) {
                WahooRouteImportView(onDismiss: { showingWahooImport = false })
                    .environmentObject(wahooService)
                    .environmentObject(viewModel)
            }
/*            .sheet(isPresented: $showingGarminImport) {
                GarminRouteImportView()
                    .environmentObject(garminService)
                    .environmentObject(viewModel)
            }*/
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showingDatePicker) {
                datePickerSheet
            }
            .sheet(isPresented: $showingTimePicker) {
                timePickerSheet
            }
            .onChange(of: viewModel.routePoints.count) { oldCount, newCount in
                handleRouteChange(oldCount: oldCount, newCount: newCount)
            }
        }
    }

    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        ScrollView {
            LazyVStack(spacing: 32) {
                Spacer()
                    .frame(height: 40)
                
                // Hero illustration
                VStack(spacing: 16) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue.gradient)
                        .symbolEffect(.bounce, value: isImporting)
                    
                    Text("Import Your Route")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white) // Change to white for visibility
                    
                    Text("Get weather forecasts and analytics for your cycling route")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9)) // Change to white
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Import options
                VStack(spacing: 12) {
                    // Local file import
                    Button {
                        isImporting = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title3)
                            Text("Import GPX or FIT File")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue.opacity(0.8), .blue.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    
                    // Strava import (if authenticated)
                    if stravaService.isAuthenticated {
                        Button {
                            showingStravaImport = true
                        } label: {
                            HStack(spacing: 12) {
                                Image("strava_logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 16)
                                Text("Import from Strava")
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.orange.opacity(0.9), .orange.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Wahoo import (if authenticated)
                    if wahooService.isAuthenticated {
                        Button {
                            showingWahooImport = true
                        } label: {
                            HStack(spacing: 12) {
                                Image("wahoo_logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                Text("Import from Wahoo")
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.blue.opacity(0.9), .cyan.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
/*                    if garminService.isAuthenticated {
                        Button {
                            showingGarminImport = true
                        } label: {
                            HStack(spacing: 12) {
                                Image("garmin_logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 24)
                                    .foregroundColor(.primary)
                                Text("Import from Garmin")
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.8), Color.gray.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }*/
                }
                .padding(.horizontal, 24)
                
                // Feature highlights
                VStack(spacing: 16) {
                    FeatureRow(icon: "cloud.sun.fill", title: "Weather Forecast", description: "Hour-by-hour conditions along your route")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Route Analytics", description: "Comfort scores, safety insights, and timing")
                    FeatureRow(icon: "bolt.fill", title: "Power Pacing", description: "AI-generated pacing strategies for optimal performance")
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
        // Remove the old background color here - now handled by the parent
    }

    
    // MARK: - Route Loaded View
    
    private var routeLoadedView: some View {
        GeometryReader { geometry in
            ZStack {
                // Map with route
                // --- THIS IS THE FIX ---
                RouteMapView(
                    cameraPosition: $cameraPosition,
                    routePolyline: viewModel.routePoints,
                    displayedAnnotations: [], // No annotations before analysis
                    scrubbingMarkerCoordinate: nil // No scrubbing on this view
                )
                .environmentObject(viewModel)
                .ignoresSafeArea()
                // --- END FIX ---
                
                // Floating controls at bottom
                VStack {
                    Spacer()
                    
                    routeControlsCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .onAppear {
                // Store screen height and center map
                screenHeight = geometry.size.height
                centerMapWithOffset(screenHeight: geometry.size.height)
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                // Update if screen size changes (rotation, etc.)
                screenHeight = newHeight
            }
        }
    }
    
    private var routeControlsCard: some View {
        VStack(spacing: 16) {
            // Route info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.routeDisplayName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    
                    Text(formatRouteDistance())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        centerMapWithOffset(screenHeight: screenHeight)
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            // Ride time controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Ride Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Button {
                        showingDatePicker = true
                    } label: {
                        Text(formattedDate)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button {
                        showingTimePicker = true
                    } label: {
                        Text(formattedTime)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            
            // Generate button
            Button {
                Task {
                    await viewModel.calculateAndFetchWeather()
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.isLoading ? "hourglass" : "play.fill")
                        .symbolEffect(.pulse, isActive: viewModel.isLoading)
                    Text(viewModel.isLoading ? "Generating..." : "Generate Forecast")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 10)
    }
    
    // MARK: - Analysis View
    
    private var analysisView: some View {
        OptimizedUnifiedRouteAnalyticsDashboard()
            .environmentObject(viewModel)
    }
    
    // MARK: - Toolbar Content
    
    @ViewBuilder
    private var toolbarContent: some View {
        switch currentView {
        case .empty:
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            
        case .routeLoaded:
            Button {
                clearRoute()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            
        case .analysis:
            // ✅ ADDED: Reschedule button
            Button {
                showingReschedule = true
            } label: {
                Label("Reschedule", systemImage: "calendar")
            }
            
            Button {
                clearRoute()
            } label: {
                Label("New Route", systemImage: "plus.circle.fill")
            }
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
        }
    }
    
    // MARK: - Supporting Views
    
    private var importSuccessBanner: some View {
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Helper Methods
    
    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let fileName = url.lastPathComponent
            viewModel.lastImportedFileName = fileName
            importedFileName = viewModel.routeDisplayName
            
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            viewModel.importRoute(from: url)
            
        case .failure(let error):
            print("File import failed: \(error.localizedDescription)")
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.error)
        }
    }
    
    private func handleRouteChange(oldCount: Int, newCount: Int) {
        if oldCount == 0 && newCount > 0 {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showImportSuccess = true
            }
            
            // Center map with a small delay to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.screenHeight > 0 {
                    self.centerMapWithOffset(screenHeight: self.screenHeight)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showImportSuccess = false
                }
            }
        }
    }
    
    private func clearRoute() {
        withAnimation {
            viewModel.clearRoute()
            importedFileName = ""
        }
    }
    
    private func formatRouteDistance() -> String {
        let totalMeters: Double
        
        // 1. Try to use the authoritative distance first
        if let authoritativeDistance = viewModel.authoritativeRouteDistanceMeters, authoritativeDistance > 0 {
            totalMeters = authoritativeDistance
            
            // 2. Fallback: Try to get distance from generated weather points
        } else if let lastPoint = viewModel.weatherDataForRoute.last {
            totalMeters = lastPoint.distance
            
            // 3. Fallback: Manually calculate from routePoints (the original, buggy method)
        } else if viewModel.routePoints.count > 1 {
            var calculatedMeters: Double = 0
            for i in 0..<(viewModel.routePoints.count - 1) {
                let loc1 = CLLocation(latitude: viewModel.routePoints[i].latitude,
                                      longitude: viewModel.routePoints[i].longitude)
                let loc2 = CLLocation(latitude: viewModel.routePoints[i + 1].latitude,
                                      longitude: viewModel.routePoints[i + 1].longitude)
                calculatedMeters += loc1.distance(from: loc2)
            }
            totalMeters = calculatedMeters
        } else {
            totalMeters = 0
        }
        
        // Format the final value
        if viewModel.settings.units == .metric {
            let km = totalMeters / 1000
            return String(format: "%.2f km", km)
        } else {
            let miles = totalMeters / 1609.34
            return String(format: "%.2f mi", miles)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter.string(from: viewModel.rideDate)
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: viewModel.rideDate)
    }
    
    // MARK: - Map Centering with Offset
    
    private func centerMapWithOffset(screenHeight: CGFloat) {
        guard !viewModel.routePoints.isEmpty else { return }
        
        // Use provided height or fallback to typical iPhone screen height
        let effectiveHeight = screenHeight > 0 ? screenHeight : UIScreen.main.bounds.height
        
        // Store screen height for re-center button
        self.screenHeight = effectiveHeight
        
        let coords = viewModel.routePoints
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLon = coords.map(\.longitude).min() ?? 0
        let maxLon = coords.map(\.longitude).max() ?? 0
        
        // Calculate the geographical center
        let centerLat = (minLat + maxLat) / 2.0
        let centerLon = (minLon + maxLon) / 2.0
        
        // Calculate span with padding
        let latDelta = max(abs(maxLat - minLat) * 1.4, 0.01)
        let lonDelta = max(abs(maxLon - minLon) * 1.4, 0.01)
        
        // Estimate card height (approximately 280-320 points depending on content)
        let cardHeight: CGFloat = 320
        
        // Calculate what percentage of screen the card covers
        let cardPercentage = cardHeight / effectiveHeight
        
        // Shift the center UP (subtract from latitude) by half the card's coverage
        // This moves the visual center to account for the bottom obstruction
        let offsetLat = centerLat - (latDelta * cardPercentage * 0.5)
        
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: offsetLat,
            longitude: centerLon
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: latDelta,
            longitudeDelta: lonDelta
        )
        
        cameraPosition = .region(MKCoordinateRegion(center: adjustedCenter, span: span))
    }
    
    // MARK: - Date/Time Picker Sheets
    
    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $viewModel.rideDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var timePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Time",
                    selection: $viewModel.rideDate,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingTimePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Reschedule Ride Sheet

struct RescheduleRideSheet: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Date and Time Picker
                DatePicker(
                    "Ride Start Time",
                    selection: $viewModel.rideDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding()
                
                // Action Button
                Button {
                    Task {
                        // Recalculate with new time
                        await viewModel.calculateAndFetchWeather()
                        dismiss()
                    }
                } label: {
                    Text("Update Forecast")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .disabled(viewModel.isLoading)
                
                Spacer()
            }
            .navigationTitle("Reschedule Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            // Optional: Show loading state
            .overlay {
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Supporting Types

enum RouteViewState {
    case empty
    case routeLoaded
    case analysis
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.3)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}
*/
