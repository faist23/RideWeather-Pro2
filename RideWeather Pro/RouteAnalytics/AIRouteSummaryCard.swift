//
//  AIRouteSummaryCard.swift
//  RideWeather Pro
//
//  Universal AI route summary card for both forecast and analysis views
//

import SwiftUI
import MapKit

// MARK: - Main Universal Card Component

struct AIRouteSummaryCard: View {
    let summaryResult: RouteSummaryResult?
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon and route type
            HStack {
                Image(systemName: "map.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Route Overview")
                        .font(.headline)
                        .fontWeight(.semibold)
                        
                    if let routeType = summaryResult?.routeType {
                        HStack(spacing: 4) {
                            Text(routeType.emoji)
                                .font(.subheadline)
                            Text(routeType.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                Spacer()
                
                // Cache indicator (subtle)
                if let result = summaryResult, result.fromCache {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green.opacity(0.6))
                }
            }
            
            // Content: Loading, Summary, or Empty
            if isLoading {
                loadingView
            } else if let summary = summaryResult?.summary {
                summaryContentView(summary)
            } else {
                emptyStateView
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Analyzing route geography...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("Detecting route type, climbs, and terrain")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
    
    // MARK: - Summary Content
    
    private func summaryContentView(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Optional: Route type explanation
            if let routeType = summaryResult?.routeType {
                Divider()
                
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    
                    Text(routeTypeExplanation(routeType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("Route summary will appear after importing a route")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
    
    // MARK: - Route Type Explanations
    
    private func routeTypeExplanation(_ type: CyclingRouteType) -> String {
        switch type {
        case .loop:
            return "Loop routes offer varied scenery while returning to your starting point."
        case .outAndBack:
            return "You'll see the same scenery twice but from opposite perspectives."
        case .pointToPoint:
            return "Requires transportation planning for start and finish locations."
        case .figure8:
            return "Two connected loops maximize variety while returning to start."
        case .lollipop:
            return "Combines familiar out-and-back terrain with a loop section."
        }
    }
}

// MARK: - Forecast Route Integration

extension AIRouteSummaryCard {
    /// Create card for forecast routes
    static func forForecast(viewModel: WeatherViewModel) -> some View {
        AIRouteSummaryCardContainer(
            source: .forecast(viewModel)
        )
    }
}

// MARK: - Ride Analysis Integration

extension AIRouteSummaryCard {
    /// Create card for completed ride analysis
    static func forAnalysis(
        analysis: RideAnalysis,
        weatherViewModel: WeatherViewModel
    ) -> some View {
        AIRouteSummaryCardContainer(
            source: .analysis(analysis, weatherViewModel)
        )
    }
}

// MARK: - Container with Data Loading Logic

private struct AIRouteSummaryCardContainer: View {
    enum DataSource {
        case forecast(WeatherViewModel)
        case analysis(RideAnalysis, WeatherViewModel)
    }
    
    let source: DataSource
    
    @State private var summaryResult: RouteSummaryResult?
    @State private var isLoading = false
    
    var body: some View {
        AIRouteSummaryCard(
            summaryResult: summaryResult,
            isLoading: isLoading
        )
        .task {
            await loadSummary()
        }
        .onChange(of: dataChangeKey) { _, _ in
            Task { await loadSummary() }
        }
    }
    
    // MARK: - Data Loading
    
    @MainActor
    func loadSummary() async {
        switch source {
        case .forecast(let viewModel):
            await loadForecastSummary(viewModel: viewModel)
            
        case .analysis(let analysis, _):
            await loadAnalysisSummary(analysis: analysis)
        }
    }
    
    @MainActor
        private func loadForecastSummary(viewModel: WeatherViewModel) async {
            guard let powerAnalysis = viewModel.getPowerAnalysisResult(),
                  let elevationAnalysis = viewModel.elevationAnalysis,
                  !viewModel.weatherDataForRoute.isEmpty else {
                summaryResult = nil
                return
            }
            
            isLoading = true
            
            // FIX: Use dense route points for accurate geometry (Turnarounds/Loops)
            // Fallback to weather points only if routePoints is empty
            let coords: [CLLocationCoordinate2D]
            if !viewModel.routePoints.isEmpty {
                coords = viewModel.routePoints
            } else {
                coords = viewModel.weatherDataForRoute.map { $0.coordinate }
            }
            
            let dist = powerAnalysis.segments.last?.endPoint.distance ?? 0
            
            summaryResult = await RouteIntelligenceEngine.shared.generateSummary(
                coordinates: coords,
                distance: dist,
                elevationGain: elevationAnalysis.totalGain,
                startCoord: coords.first,
                endCoord: coords.last
            )
            
            isLoading = false
        }
    
    @MainActor
    private func loadAnalysisSummary(analysis: RideAnalysis) async {
        // Need coordinates to do intelligence work
        guard let breadcrumbs = analysis.metadata?.routeBreadcrumbs, !breadcrumbs.isEmpty else {
            // Fallback if no breadcrumbs (e.g. manual entry or really old file)
            summaryResult = nil
            return
        }
        
        isLoading = true
        
        // Call the smart engine with Analysis data!
        summaryResult = await RouteIntelligenceEngine.shared.generateSummary(
            coordinates: breadcrumbs,
            distance: analysis.distance,
            elevationGain: analysis.metadata?.elevationGain ?? 0,
            startCoord: analysis.metadata?.startCoordinate,
            endCoord: analysis.metadata?.endCoordinate
        )
        
        isLoading = false
    }
    
    // MARK: - Helper: Simple Summary for Completed Rides
    
    private func generateSimpleSummary(
        metadata: RideMetadata,
        analysis: RideAnalysis
    ) async -> RouteSummaryResult? {
        var summary: [String] = []
        
        // Detect basic route type from coordinates
        let routeType: CyclingRouteType
        if let start = metadata.startCoordinate,
           let end = metadata.endCoordinate {
            let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
            let distance = endLoc.distance(from: startLoc)
            
            if distance < 200 {
                routeType = .loop
            } else if distance < 1000 {
                // Check if it's a lollipop by looking at terrain segments
                if hasLoopInMiddle(analysis: analysis) {
                    routeType = .lollipop
                } else {
                    routeType = .outAndBack
                }
            } else {
                routeType = .pointToPoint
            }
        } else {
            routeType = .loop
        }
        
        // Location description
        if let startName = await locationName(for: metadata.startCoordinate),
           let endName = await locationName(for: metadata.endCoordinate) {
            
            switch routeType {
            case .loop, .lollipop:
                summary.append("\(routeType.emoji) \(routeType.rawValue) route starting and finishing in \(startName)")
            case .outAndBack:
                summary.append("\(routeType.emoji) \(routeType.rawValue) route starting in \(startName)")
                
                // Add turnaround info if we can determine it
                if let turnaroundDist = estimateTurnaroundDistance(analysis: analysis, metadata: metadata) {
                    summary.append("with a turnaround point at \(turnaroundDist)")
                }
            case .pointToPoint:
                if startName != endName {
                    summary.append("\(routeType.emoji) \(routeType.rawValue) route from \(startName) to \(endName)")
                } else {
                    summary.append("\(routeType.emoji) Route in \(startName)")
                }
            case .figure8:
                summary.append("\(routeType.emoji) \(routeType.rawValue) route in \(startName)")
            }
        }
        
        // Climb analysis from terrain segments
        if let terrainSegments = analysis.terrainSegments {
            let climbDescriptions = describeClimbsFromTerrainSegments(
                segments: terrainSegments,
                units: metadata.distanceUnit
            )
            summary.append(contentsOf: climbDescriptions)
        }
        
        // Overall stats
        let distanceStr = String(format: "%.1f %@", metadata.totalDistance, metadata.distanceUnit)
        let elevationStr = String(format: "%.0f%@", metadata.elevation, metadata.elevationUnit)
        
        let climbDensity = metadata.elevationGain / (analysis.distance / 1000.0)
        let terrainDesc: String
        
        if climbDensity > 25 {
            terrainDesc = "making it a very hilly mountain route"
        } else if climbDensity > 15 {
            terrainDesc = "featuring continuous rolling terrain"
        } else if metadata.elevationGain > 1000 {
            terrainDesc = "with climbing concentrated in specific sections"
        } else {
            terrainDesc = "relatively flat overall"
        }
        
        summary.append("The route covers \(distanceStr) with \(elevationStr) of climbing, \(terrainDesc)")
        
        let fullSummary = summary.joined(separator: ". ") + "."
        
        // Cache for future use
        RouteSummaryCacheManager.shared.cacheSummary(
            fullSummary,
            start: metadata.startCoordinate,
            end: metadata.endCoordinate,
            distance: analysis.distance,
            routeType: routeType
        )
        
        return RouteSummaryResult(
            summary: fullSummary,
            routeType: routeType,
            fromCache: false
        )
    }
    
    // MARK: - Helper: Check for Loop in Middle
    
    private func hasLoopInMiddle(analysis: RideAnalysis) -> Bool {
        guard let segments = analysis.terrainSegments,
              segments.count > 10 else {
            return false
        }
        
        // Look at middle third of ride
        let startIdx = segments.count / 3
        let endIdx = (segments.count * 2) / 3
        
        let middleSegments = segments[startIdx..<endIdx]
        
        // If there are multiple direction changes in middle, might be a loop
        var directionChanges = 0
        var lastGrade: Double = 0
        
        for segment in middleSegments {
            if (lastGrade > 0 && segment.gradient < 0) ||
               (lastGrade < 0 && segment.gradient > 0) {
                directionChanges += 1
            }
            lastGrade = segment.gradient
        }
        
        return directionChanges > 5
    }
    
    // MARK: - Helper: Estimate Turnaround Distance
    
    private func estimateTurnaroundDistance(
        analysis: RideAnalysis,
        metadata: RideMetadata
    ) -> String? {
        // For out-and-back, turnaround is roughly at halfway point
        let halfDistance = analysis.distance / 2.0
        
        let distanceStr: String
        if metadata.distanceUnit == "km" {
            distanceStr = String(format: "%.1f km", halfDistance / 1000)
        } else {
            distanceStr = String(format: "%.1f mi", halfDistance / 1609.34)
        }
        
        return distanceStr
    }
    
    // MARK: - Helper: Describe Climbs from Terrain Segments
    
    private func describeClimbsFromTerrainSegments(
        segments: [TerrainSegment],
        units: String
    ) -> [String] {
        var descriptions: [String] = []
        
        // Find all significant climbs
        let climbs = segments.filter { segment in
            segment.type == .climb &&
            segment.elevationGain > (units == "km" ? 100 : 91.44) // 100m or 300ft
        }
        
        // Sort by elevation gain and take top 3
        let majorClimbs = climbs.sorted { $0.elevationGain > $1.elevationGain }.prefix(3)
        
        for (index, climb) in majorClimbs.enumerated() {
            let startDist: String
            let climbLength: String
            let gainStr: String
            
            if units == "km" {
                startDist = String(format: "%.1f km", climb.distance / 1000)
                climbLength = String(format: "%.2f km", (climb.distance) / 1000)
                gainStr = String(format: "%.0fm", climb.elevationGain)
            } else {
                startDist = String(format: "%.1f mi", climb.distance / 1609.34)
                climbLength = String(format: "%.2f mi", (climb.distance) / 1609.34)
                gainStr = String(format: "%.0fft", climb.elevationGain * 3.28084)
            }
            
            var desc = index == 0 ? "There is a" : "Another"
            
            let grade = abs(climb.gradient) * 100
            if grade > 12 {
                desc += " very steep"
            } else if grade > 10 {
                desc += " steep"
            } else if grade > 7 {
                desc += " challenging"
            } else {
                desc += " moderate"
            }
            
            desc += " climb starting at \(startDist), lasting \(climbLength)"
            desc += " with \(gainStr) of elevation gain"
            
            if grade > 8 {
                desc += " (max grade \(String(format: "%.0f", grade))%)"
            }
            
            descriptions.append(desc)
        }
        
        return descriptions
    }
        
    // MARK: - Helper: Geocoding (Optimized with Manager)
    
    private func locationName(for coordinate: CLLocationCoordinate2D?) async -> String? {
        guard let coord = coordinate else { return nil }
        
        // 1. Check existing cache (Fastest)
        if let cached = RouteSummaryCacheManager.shared.getCachedLocationName(for: coord) {
            return cached
        }
        
        // 2. Use the GeocodingManager Actor (Safe & Rate Limited)
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        
        do {
            // Ensure your GeocodingManager.swift has a function like 'reverseGeocode(location:)'
            if let placemark = try await GeocodingManager.shared.reverseGeocode(location: location) {
                
                // Construct readable name
                let name = [placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                
                if !name.isEmpty {
                    // Cache the result to prevent future network calls
                    RouteSummaryCacheManager.shared.cacheLocationName(name, for: coord)
                    return name
                }
            }
        } catch {
            // If we hit Error 4 (Rate Limit), we return nil.
            // This tells the UI to fallback to "Physical Description" instead of "Generic Location".
            print("⚠️ Geocoding Skipped: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: - Change Detection Key
    
    private var dataChangeKey: String {
        switch source {
        case .forecast(let viewModel):
            return "\(viewModel.weatherDataForRoute.count)"
        case .analysis(let analysis, _):
            return analysis.id.uuidString
        }
    }
}
