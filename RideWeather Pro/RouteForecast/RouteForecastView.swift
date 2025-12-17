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
    @EnvironmentObject var garminService: GarminService
    
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
                // 1. Main Content
                switch currentView {
                case .empty:
                    emptyStateView
                case .routeLoaded:
                    routeLoadedView
                case .analysis:
                    analysisView
                }
                
                // 2. Success Banner
                if showImportSuccess {
                    VStack {
                        importSuccessBanner
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // 3. Smart Loading Overlay with Context
                if viewModel.isLoading {
                    loadingOverlay
                        .zIndex(100)
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
                    GarminRouteImportView()
                        .environmentObject(garminService)
                        .environmentObject(viewModel)*/
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
    
    
     // MARK: - Smart Loading Overlay
     
     /// Context-aware loading overlay that shows appropriate messages
     @ViewBuilder
     private var loadingOverlay: some View {
         Group {
             if viewModel.routePoints.isEmpty {
                 // Importing route file
                 ProcessingOverlay.importing(
                     "Route File",
                     subtitle: viewModel.processingStatus.isEmpty ?
                         "Reading GPS coordinates and elevation" :
                         viewModel.processingStatus
                 )
             } else if viewModel.weatherDataForRoute.isEmpty {
                 // Initial forecast generation
                 let distance = formatRouteDistance()
                 ProcessingOverlay.generating(
                     "Route Forecast",
                     subtitle: viewModel.processingStatus.isEmpty ?
                         "Analyzing \(distance) of terrain and weather" :
                         viewModel.processingStatus
                 )
             } else {
                 // Updating existing forecast
                 ProcessingOverlay.analyzing(
                     "Updating Forecast",
                     subtitle: viewModel.processingStatus.isEmpty ?
                         "Fetching conditions for \(formattedTime)" :
                         viewModel.processingStatus
                 )
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
            
/*            if viewModel.isLoading {
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
            }*/
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

