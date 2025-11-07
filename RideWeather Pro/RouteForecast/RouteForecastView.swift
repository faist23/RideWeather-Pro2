//
// RouteForecastView.swift — Improved UX with state-based views
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers
import CoreLocation

struct RouteForecastView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var wahooService: WahooService
    
    @State private var isImporting = false
    @State private var showingStravaImport = false
    @State private var showingWahooImport = false
    @State private var showingSettings = false
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
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
                // Background color for empty state
                if currentView == .empty {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }
                
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
            .animation(.smooth, value: currentView)
            .navigationTitle("Route Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Show different toolbar items based on state
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
            VStack(spacing: 32) {
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
                    
                    Text("Get weather forecasts and analytics for your cycling route")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
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
    }
    
    // MARK: - Route Loaded View
    
    private var routeLoadedView: some View {
        GeometryReader { geometry in
            ZStack {
                // Map with route
                RouteMapView(cameraPosition: $cameraPosition)
                    .environmentObject(viewModel)
                    .ignoresSafeArea()
                
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
        // Try to get distance from last weather point (already calculated)
        if let lastPoint = viewModel.weatherDataForRoute.last {
            let distanceMeters = lastPoint.distance
            if viewModel.settings.units == .metric {
                let km = distanceMeters / 1000
                return String(format: "%.1f km", km)
            } else {
                let miles = distanceMeters / 1609.34
                return String(format: "%.1f mi", miles)
            }
        }
        
        // Fallback: Calculate from route points
        guard viewModel.routePoints.count > 1 else {
            return viewModel.settings.units == .metric ? "0.0 km" : "0.0 mi"
        }
        
        var totalMeters: Double = 0
        for i in 0..<(viewModel.routePoints.count - 1) {
            let loc1 = CLLocation(latitude: viewModel.routePoints[i].latitude,
                                 longitude: viewModel.routePoints[i].longitude)
            let loc2 = CLLocation(latitude: viewModel.routePoints[i + 1].latitude,
                                 longitude: viewModel.routePoints[i + 1].longitude)
            totalMeters += loc1.distance(from: loc2)
        }
        
        if viewModel.settings.units == .metric {
            let km = totalMeters / 1000
            return String(format: "%.1f km", km)
        } else {
            let miles = totalMeters / 1609.34
            return String(format: "%.1f mi", miles)
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
                .foregroundStyle(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
