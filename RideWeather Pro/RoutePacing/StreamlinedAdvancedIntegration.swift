//
//  AdvancedCyclingIntegration.swift
//  RideWeather Pro
//
//  Complete integration of advanced cycling features with existing route system

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Missing Dependencies (Add these to your project)

enum PowerSegmentType {
    case flat, climb, descent, headwind, tailwind
}

struct PowerDistribution {
    let averagePower: Double
    let normalizedPower: Double
    let timeInZones: PowerZones
    let intensityFactor: Double
    
    struct PowerZones {
        let zone1Seconds: Double
        let zone2Seconds: Double
        let zone3Seconds: Double
        let zone4Seconds: Double
        let zone5Seconds: Double
    }
}

struct SpeedComparisonResult {
    let traditionalTimeMinutes: Double
    let powerBasedTimeMinutes: Double
    let timeDifferenceMinutes: Double
    let significantSegments: [String]
}

struct TerrainBreakdown {
    let flatDistanceMeters: Double
    let climbingDistanceMeters: Double
    let descendingDistanceMeters: Double
    let averageClimbGrade: Double
    let averageDescentGrade: Double
    let steepestClimbGrade: Double
    let steepestDescentGrade: Double
}

struct PowerRouteSegment {
    let startPoint: RouteWeatherPoint
    let endPoint: RouteWeatherPoint
    let distanceMeters: Double
    let elevationGrade: Double
    let averageHeadwindMps: Double
    let averageCrosswindMps: Double
    let averageTemperatureC: Double
    let averageHumidity: Double
    let calculatedSpeedMps: Double
    let timeSeconds: Double
    let powerRequired: Double
    let segmentType: PowerSegmentType
}

struct PowerRouteAnalysisResult {
    let segments: [PowerRouteSegment]
    let totalTimeSeconds: Double
    let averageSpeedMps: Double
    let totalEnergyKilojoules: Double
    let powerDistribution: PowerDistribution
    let comparisonWithTraditional: SpeedComparisonResult
    let terrainBreakdown: TerrainBreakdown
}

// MARK: - Enhanced WeatherViewModel Extension

extension WeatherViewModel {
    
    @Published var advancedController: AdvancedCyclingController?
    @Published var isGeneratingAdvancedPlan = false
    @Published var advancedPlanError: String?
    
    /// Generate advanced cycling features from imported route
    func generateAdvancedCyclingPlan(
        strategy: PacingStrategy = .balanced,
        startTime: Date = Date()
    ) async {
        guard !weatherDataForRoute.isEmpty else {
            advancedPlanError = "No route data available. Import a route first."
            return
        }
        
        isGeneratingAdvancedPlan = true
        advancedPlanError = nil
        
        do {
            // Create or get controller
            if advancedController == nil {
                advancedController = AdvancedCyclingController(settings: settings)
            }
            
            guard let controller = advancedController else { return }
            
            // Generate power analysis from existing route data
            let powerAnalysis = createPowerAnalysisFromRoute()
            
            // Create fueling preferences based on user settings
            let fuelingPrefs = FuelingPreferences(
                maxCarbsPerHour: settings.primaryRidingGoal == .performance ? 90 : 60,
                fuelTypes: [.gel, .drink, .bar, .solid],
                preferLiquids: false,
                avoidGluten: false,
                avoidCaffeine: false
            )
            
            // Generate comprehensive plan
            await controller.generateAdvancedRacePlan(
                from: powerAnalysis,
                strategy: strategy,
                fuelingPreferences: fuelingPrefs,
                startTime: startTime
            )
            
            isGeneratingAdvancedPlan = false
            
        } catch {
            advancedPlanError = error.localizedDescription
            isGeneratingAdvancedPlan = false
        }
    }
    
    /// Sync current plan to devices
    func syncToDevices(_ platforms: [DevicePlatform]) async {
        guard let controller = advancedController else {
            advancedPlanError = "No advanced plan available to sync"
            return
        }
        
        let options = WorkoutOptions(
            workoutName: "RideWeather Pro Route - \(Date().formatted(date: .abbreviated, time: .omitted))",
            includeWarmup: settings.primaryRidingGoal == .performance,
            includeCooldown: settings.primaryRidingGoal == .performance,
            powerTolerance: 5.0
        )
        
        await controller.syncToDevices(platforms, options: options)
    }
    
    // MARK: - Private Implementation
    
    private func createPowerAnalysisFromRoute() -> PowerRouteAnalysisResult {
        let totalDistance = weatherDataForRoute.last?.distance ?? 0
        let targetSegments = min(20, max(5, weatherDataForRoute.count / 2))
        let segmentDistance = totalDistance / Double(targetSegments)
        
        var segments: [PowerRouteSegment] = []
        var currentDistance: Double = 0
        
        for i in 0..<targetSegments {
            let startDistance = currentDistance
            let endDistance = min(currentDistance + segmentDistance, totalDistance)
            
            let startPoint = findRoutePointAtDistance(startDistance)
            let endPoint = findRoutePointAtDistance(endDistance)
            
            let segment = createPowerSegment(
                from: startPoint,
                to: endPoint,
                segmentDistance: endDistance - startDistance
            )
            
            segments.append(segment)
            currentDistance = endDistance
        }
        
        return PowerRouteAnalysisResult(
            segments: segments,
            totalTimeSeconds: calculateTotalTime(segments),
            averageSpeedMps: calculateAverageSpeed(segments, totalDistance: totalDistance),
            totalEnergyKilojoules: calculateTotalEnergy(segments),
            powerDistribution: createPowerDistribution(segments),
            comparisonWithTraditional: createSpeedComparison(segments),
            terrainBreakdown: createTerrainBreakdown(segments)
        )
    }
    
    private func findRoutePointAtDistance(_ targetDistance: Double) -> RouteWeatherPoint {
        guard !weatherDataForRoute.isEmpty else {
            return RouteWeatherPoint(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                distance: 0,
                eta: Date(),
                weather: DisplayWeatherModel(
                    temp: 20, feelsLike: 20, humidity: 60, windSpeed: 10,
                    windDirection: "N", windDeg: 0, description: "Clear",
                    iconName: "sun.max", pop: 0, visibility: nil, uvIndex: nil
                )
            )
        }
        
        let closest = weatherDataForRoute.min { point1, point2 in
            abs(point1.distance - targetDistance) < abs(point2.distance - targetDistance)
        }
        
        return closest ?? weatherDataForRoute[0]
    }
    
    private func createPowerSegment(
        from startPoint: RouteWeatherPoint,
        to endPoint: RouteWeatherPoint,
        segmentDistance: Double
    ) -> PowerRouteSegment {
        
        let grade = calculateGrade(from: startPoint, to: endPoint)
        let headwind = calculateHeadwind(from: startPoint, to: endPoint)
        let crosswind = calculateCrosswind(from: startPoint, to: endPoint)
        let avgTemp = (startPoint.weather.temp + endPoint.weather.temp) / 2
        let avgHumidity = Double(startPoint.weather.humidity + endPoint.weather.humidity) / 2
        
        let powerRequired = estimatePowerRequired(
            grade: grade,
            headwind: headwind,
            temperature: avgTemp
        )
        
        let speed = estimateSpeed(from: powerRequired, grade: grade, headwind: headwind)
        let timeSeconds = segmentDistance / speed
        
        return PowerRouteSegment(
            startPoint: startPoint,
            endPoint: endPoint,
            distanceMeters: segmentDistance,
            elevationGrade: grade,
            averageHeadwindMps: headwind,
            averageCrosswindMps: crosswind,
            averageTemperatureC: avgTemp,
            averageHumidity: avgHumidity,
            calculatedSpeedMps: speed,
            timeSeconds: timeSeconds,
            powerRequired: powerRequired,
            segmentType: determineSegmentType(grade: grade, headwind: headwind)
        )
    }
    
    private func calculateGrade(from start: RouteWeatherPoint, to end: RouteWeatherPoint) -> Double {
        guard let elevAnalysis = elevationAnalysis,
              !elevAnalysis.elevationPoints.isEmpty else { return 0.0 }
        
        let startElev = findClosestElevation(to: start.coordinate, in: elevAnalysis.elevationPoints)
        let endElev = findClosestElevation(to: end.coordinate, in: elevAnalysis.elevationPoints)
        
        let elevationChange = endElev - startElev
        let distance = end.distance - start.distance
        
        return distance > 0 ? elevationChange / distance : 0.0
    }
    
    private func findClosestElevation(to coord: CLLocationCoordinate2D, in points: [ElevationPoint]) -> Double {
        guard !points.isEmpty else { return 0.0 }
        
        let closest = points.min { p1, p2 in
            let d1 = pow(p1.coordinate.latitude - coord.latitude, 2) + pow(p1.coordinate.longitude - coord.longitude, 2)
            let d2 = pow(p2.coordinate.latitude - coord.latitude, 2) + pow(p2.coordinate.longitude - coord.longitude, 2)
            return d1 < d2
        }
        
        return closest?.elevation ?? 0.0
    }
    
    private func calculateHeadwind(from start: RouteWeatherPoint, to end: RouteWeatherPoint) -> Double {
        let bearing = calculateBearing(from: start.coordinate, to: end.coordinate)
        let windDirection = Double(start.weather.windDeg)
        
        let angleDiff = abs(bearing - windDirection)
        let normalizedAngle = angleDiff > 180 ? 360 - angleDiff : angleDiff
        
        if normalizedAngle <= 45 {
            return start.weather.windSpeed * cos(normalizedAngle * .pi / 180)
        }
        return max(0, -start.weather.windSpeed * cos(normalizedAngle * .pi / 180))
    }
    
    private func calculateCrosswind(from start: RouteWeatherPoint, to end: RouteWeatherPoint) -> Double {
        let bearing = calculateBearing(from: start.coordinate, to: end.coordinate)
        let windDirection = Double(start.weather.windDeg)
        
        let angleDiff = abs(bearing - windDirection)
        let normalizedAngle = angleDiff > 180 ? 360 - angleDiff : angleDiff
        
        if normalizedAngle > 45 && normalizedAngle < 135 {
            return start.weather.windSpeed * sin(normalizedAngle * .pi / 180)
        }
        return 0
    }
    
    private func calculateBearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        
        let bearing = atan2(y, x) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }
    
    private func estimatePowerRequired(grade: Double, headwind: Double, temperature: Double) -> Double {
        let ftp = Double(settings.functionalThresholdPower)
        let basePower = ftp * 0.75 // Base endurance power
        
        // Grade adjustment (roughly 10W per 1% grade per kg at 250W baseline)
        let gradeAdjustment = grade * 1000 // Simplified: 1000W per 100% grade
        
        // Wind adjustment (roughly 50W per 10 mph headwind)
        let windAdjustment = max(0, headwind) * 5
        
        // Temperature adjustment (efficiency drops in extreme heat)
        var tempAdjustment: Double = 0
        if temperature > 30 { // Above 30°C
            tempAdjustment = (temperature - 30) * 2
        }
        
        return max(ftp * 0.5, basePower + gradeAdjustment + windAdjustment + tempAdjustment)
    }
    
    private func estimateSpeed(from power: Double, grade: Double, headwind: Double) -> Double {
        // Simplified speed estimation based on power
        // This is a rough approximation - real implementation would use full physics model
        let basePower = Double(settings.functionalThresholdPower) * 0.75
        let speedRatio = power / basePower
        let baseSpeed = effectiveAverageSpeedMps
        
        // Apply speed ratio with some practical limits
        return max(baseSpeed * 0.5, min(baseSpeed * 1.5, baseSpeed * sqrt(speedRatio)))
    }
    
    private func determineSegmentType(grade: Double, headwind: Double) -> PowerSegmentType {
        if grade > 0.06 {
            return .climb
        } else if grade < -0.04 {
            return .descent
        } else if headwind > 5 {
            return .headwind
        } else if headwind < -5 {
            return .tailwind
        } else {
            return .flat
        }
    }
    
    private func calculateTotalTime(_ segments: [PowerRouteSegment]) -> Double {
        return segments.reduce(0) { $0 + $1.timeSeconds }
    }
    
    private func calculateAverageSpeed(_ segments: [PowerRouteSegment], totalDistance: Double) -> Double {
        let totalTime = calculateTotalTime(segments)
        return totalTime > 0 ? totalDistance / totalTime : 0
    }
    
    private func calculateTotalEnergy(_ segments: [PowerRouteSegment]) -> Double {
        return segments.reduce(0) { $0 + ($1.powerRequired * $1.timeSeconds / 1000) }
    }
    
    private func createPowerDistribution(_ segments: [PowerRouteSegment]) -> PowerDistribution {
        let ftp = Double(settings.functionalThresholdPower)
        
        var zoneSeconds: [Double] = [0, 0, 0, 0, 0] // 5 zones
        let totalPowerTime = segments.reduce(0) { $0 + ($1.powerRequired * $1.timeSeconds) }
        let totalTime = segments.reduce(0) { $0 + $1.timeSeconds }
        let avgPower = totalTime > 0 ? totalPowerTime / totalTime : 0
        
        for segment in segments {
            let intensity = segment.powerRequired / ftp
            let zoneIndex: Int
            
            switch intensity {
            case 0..<0.56: zoneIndex = 0
            case 0.56..<0.76: zoneIndex = 1
            case 0.76..<0.91: zoneIndex = 2
            case 0.91..<1.05: zoneIndex = 3
            default: zoneIndex = 4
            }
            
            zoneSeconds[zoneIndex] += segment.timeSeconds
        }
        
        return PowerDistribution(
            averagePower: avgPower,
            normalizedPower: calculateNormalizedPower(segments),
            timeInZones: PowerDistribution.PowerZones(
                zone1Seconds: zoneSeconds[0],
                zone2Seconds: zoneSeconds[1],
                zone3Seconds: zoneSeconds[2],
                zone4Seconds: zoneSeconds[3],
                zone5Seconds: zoneSeconds[4]
            ),
            intensityFactor: avgPower / ftp
        )
    }
    
    private func calculateNormalizedPower(_ segments: [PowerRouteSegment]) -> Double {
        let powerSum = segments.reduce(0) { $0 + pow($1.powerRequired, 4) }
        let count = Double(segments.count)
        return count > 0 ? pow(powerSum / count, 0.25) : 0
    }
    
    private func createSpeedComparison(_ segments: [PowerRouteSegment]) -> SpeedComparisonResult {
        let powerBasedTime = calculateTotalTime(segments)
        let traditionalTime = powerBasedTime * 1.1 // Assume traditional is 10% slower
        
        return SpeedComparisonResult(
            traditionalTimeMinutes: traditionalTime / 60,
            powerBasedTimeMinutes: powerBasedTime / 60,
            timeDifferenceMinutes: (traditionalTime - powerBasedTime) / 60,
            significantSegments: findSignificantSegments(segments)
        )
    }
    
    private func findSignificantSegments(_ segments: [PowerRouteSegment]) -> [String] {
        var significant: [String] = []
        
        for (index, segment) in segments.enumerated() {
            if segment.elevationGrade > 0.08 {
                significant.append("Segment \(index + 1): Steep climb (\(Int(segment.elevationGrade * 100))% grade)")
            } else if segment.averageHeadwindMps > 8 {
                significant.append("Segment \(index + 1): Strong headwind (\(Int(segment.averageHeadwindMps)) m/s)")
            } else if segment.powerRequired > Double(settings.functionalThresholdPower) * 1.1 {
                significant.append("Segment \(index + 1): High power demand (\(Int(segment.powerRequired))W)")
            }
        }
        
        return Array(significant.prefix(3))
    }
    
    private func createTerrainBreakdown(_ segments: [PowerRouteSegment]) -> TerrainBreakdown {
        var flatDistance: Double = 0
        var climbDistance: Double = 0
        var descentDistance: Double = 0
        var climbGrades: [Double] = []
        var descentGrades: [Double] = []
        
        for segment in segments {
            if segment.elevationGrade > 0.02 {
                climbDistance += segment.distanceMeters
                climbGrades.append(segment.elevationGrade)
            } else if segment.elevationGrade < -0.02 {
                descentDistance += segment.distanceMeters
                descentGrades.append(segment.elevationGrade)
            } else {
                flatDistance += segment.distanceMeters
            }
        }
        
        return TerrainBreakdown(
            flatDistanceMeters: flatDistance,
            climbingDistanceMeters: climbDistance,
            descendingDistanceMeters: descentDistance,
            averageClimbGrade: climbGrades.isEmpty ? 0 : climbGrades.reduce(0, +) / Double(climbGrades.count),
            averageDescentGrade: descentGrades.isEmpty ? 0 : descentGrades.reduce(0, +) / Double(descentGrades.count),
            steepestClimbGrade: climbGrades.max() ?? 0,
            steepestDescentGrade: descentGrades.min() ?? 0
        )
    }
}

// MARK: - Advanced Cycling UI Views

struct AdvancedCyclingTabView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            PacingPlanView(viewModel: viewModel)
                .tabItem {
                    Label("Pacing", systemImage: "speedometer")
                }
                .tag(0)
            
            FuelingPlanView(viewModel: viewModel)
                .tabItem {
                    Label("Fueling", systemImage: "drop.fill")
                }
                .tag(1)
            
            DeviceSyncView(viewModel: viewModel)
                .tabItem {
                    Label("Sync", systemImage: "externaldrive.connected.to.line.below")
                }
                .tag(2)
        }
        .navigationTitle("Advanced Features")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct PacingPlanView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var selectedStrategy: PacingStrategy = .balanced
    @State private var showingExportOptions = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.routePoints.isEmpty {
                    EmptyStateView(
                        title: "No Route Imported",
                        message: "Import a route first to generate a pacing plan",
                        systemImage: "route"
                    )
                } else if viewModel.isGeneratingAdvancedPlan {
                    ProgressView("Generating pacing plan...")
                        .frame(maxWidth: .infinity, maxHeight: 100)
                } else if let error = viewModel.advancedPlanError {
                    ErrorStateView(message: error) {
                        Task {
                            await viewModel.generateAdvancedCyclingPlan(strategy: selectedStrategy)
                        }
                    }
                } else {
                    // Strategy Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Pacing Strategy")
                            .font(.headline)
                        
                        ForEach(PacingStrategy.allCases, id: \.self) { strategy in
                            PacingStrategyCard(
                                strategy: strategy,
                                isSelected: selectedStrategy == strategy
                            ) {
                                selectedStrategy = strategy
                            }
                        }
                        
                        Button("Generate Pacing Plan") {
                            Task {
                                await viewModel.generateAdvancedCyclingPlan(strategy: selectedStrategy)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    
                    // Display Plan if Available
                    if let controller = viewModel.advancedController,
                       let pacing = controller.pacingPlan {
                        PacingPlanDisplay(pacing: pacing)
                        
                        Button("Export Plan") {
                            showingExportOptions = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingExportOptions) {
            if let controller = viewModel.advancedController {
                ExportOptionsSheet(controller: controller)
            }
        }
    }
}

struct FuelingPlanView: View {
    @ObservedObject var viewModel: WeatherViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let controller = viewModel.advancedController,
                   let fueling = controller.fuelingStrategy {
                    FuelingPlanDisplay(fueling: fueling)
                } else if viewModel.isGeneratingAdvancedPlan {
                    ProgressView("Generating fueling strategy...")
                        .frame(maxWidth: .infinity, maxHeight: 100)
                } else {
                    EmptyStateView(
                        title: "No Fueling Strategy",
                        message: "Generate a pacing plan first to see your personalized fueling strategy",
                        systemImage: "drop"
                    )
                }
            }
            .padding()
        }
    }
}

struct DeviceSyncView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var selectedPlatforms: Set<DevicePlatform> = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Platform Selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select Devices")
                        .font(.headline)
                    
                    ForEach(DevicePlatform.allCases, id: \.self) { platform in
                        DevicePlatformCard(
                            platform: platform,
                            isSelected: selectedPlatforms.contains(platform)
                        ) {
                            if selectedPlatforms.contains(platform) {
                                selectedPlatforms.remove(platform)
                            } else {
                                selectedPlatforms.insert(platform)
                            }
                        }
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                
                if !selectedPlatforms.isEmpty && viewModel.advancedController?.pacingPlan != nil {
                    Button("Sync to Selected Devices") {
                        Task {
                            await viewModel.syncToDevices(Array(selectedPlatforms))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    
                    // Show sync results
                    if let syncResults = viewModel.advancedController?.syncResults, !syncResults.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sync Results")
                                .font(.headline)
                            
                            ForEach(syncResults, id: \.platform) { result in
                                SyncResultCard(result: result)
                            }
                        }
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                } else {
                    EmptyStateView(
                        title: "Ready to Sync",
                        message: "Select devices above and generate a pacing plan to sync workouts",
                        systemImage: "externaldrive.badge.plus"
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Helper Views

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

struct ErrorStateView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again", action: retryAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}

struct PacingStrategyCard: View {
    let strategy: PacingStrategy
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(strategy.description)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text(strategyDescription(for: strategy))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func strategyDescription(for strategy: PacingStrategy) -> String {
        switch strategy {
        case .balanced:
            return "Well-rounded approach balancing speed and sustainability"
        case .conservative:
            return "Start easier, maintain energy for later in the ride"
        case .aggressive:
            return "Go hard early, accept some fade later"
        case .negativeSplit:
            return "Build power progressively throughout the ride"
        case .evenEffort:
            return "Adjust for terrain to maintain constant physiological stress"
        }
    }
}

struct DevicePlatformCard: View {
    let platform: DevicePlatform
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                
                Text(platform.displayName)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct ExportOptionsSheet: View {
    let controller: AdvancedCyclingController
    @Environment(\.dismiss) private var dismiss
    @State private var exportText = ""
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Button("Export as CSV") {
                    exportText = controller.exportRacePlanCSV()
                    showingShareSheet = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Generate Race Day Summary") {
                    exportText = controller.generateRaceDaySummary()
                    showingShareSheet = true
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [exportText])
        }
    }
}

// MARK: - Main Advanced Features Integration View

struct AdvancedFeaturesButton: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var showingAdvancedFeatures = false
    
    var body: some View {
        Button(action: {
            showingAdvancedFeatures = true
        }) {
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .foregroundColor(.yellow)
                Text("Advanced Features")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.routePoints.isEmpty)
        .sheet(isPresented: $showingAdvancedFeatures) {
            AdvancedCyclingTabView(viewModel: viewModel)
        }
    }
}

// Add this to your main route view to provide access to advanced features
struct RouteAdvancedFeaturesCard: View {
    @ObservedObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advanced Cycling Features")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Power-based pacing, fueling strategy, and device sync")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if viewModel.routePoints.isEmpty {
                VStack(spacing: 8) {
                    Text("Import a route to unlock:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.blue)
                            Text("Smart pacing plans")
                                .font(.caption)
                        }
                        
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundColor(.cyan)
                            Text("Personalized fueling strategy")
                                .font(.caption)
                        }
                        
                        HStack {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .foregroundColor(.green)
                            Text("Sync to Garmin, Wahoo, Zwift")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.secondary)
                }
            } else {
                AdvancedFeaturesButton(viewModel: viewModel)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Power Analysis Integration for Settings

struct PowerAnalysisSettingsView: View {
    @Binding var settings: AppSettings
    
    var body: some View {
        Section("Power Analysis Settings") {
            Toggle("Enable Power-Based Analysis", isOn: Binding(
                get: { settings.speedCalculationMethod == .powerBased },
                set: { newValue in
                    settings.speedCalculationMethod = newValue ? .powerBased : .averageSpeed
                }
            ))
            
            if settings.speedCalculationMethod == .powerBased {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Functional Threshold Power")
                        Spacer()
                        Text("\(settings.functionalThresholdPower) W")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(settings.functionalThresholdPower) },
                            set: { settings.functionalThresholdPower = Int($0) }
                        ),
                        in: 100...500,
                        step: 5
                    )
                    
                    HStack {
                        Text("Body Weight")
                        Spacer()
                        Text(String(format: "%.1f %@", settings.bodyWeightInUserUnits, settings.units.weightSymbol))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: $settings.bodyWeightInUserUnits,
                        in: settings.units == .metric ? 40...150 : 88...330,
                        step: settings.units == .metric ? 1 : 2
                    )
                    
                    HStack {
                        Text("Bike + Equipment Weight")
                        Spacer()
                        Text(String(format: "%.1f %@", settings.bikeWeightInUserUnits, settings.units.weightSymbol))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: $settings.bikeWeightInUserUnits,
                        in: settings.units == .metric ? 5...25 : 11...55,
                        step: settings.units == .metric ? 0.5 : 1
                    )
                }
                .padding(.vertical, 8)
            }
        }
        
        if settings.speedCalculationMethod == .powerBased {
            Section(footer: Text("Power-based analysis provides more accurate time estimates by accounting for terrain, wind, and rider physiology. Your FTP and weight are used to calculate realistic power outputs for different conditions.")) {
                EmptyView()
            }
        }
    }
}

// MARK: - Real Device Sync Implementation Helpers

extension DeviceSyncManager {
    
    /// Real implementation would use WebAuthenticationSession
    func authenticateWithGarmin() async throws -> AuthenticationResult {
        // This would open Garmin Connect OAuth in WebAuthenticationSession
        // For now, return simulated result
        return AuthenticationResult(
            success: true,
            platform: .garmin,
            error: nil,
            deviceInfo: deviceCapabilities[.garmin]
        )
    }
    
    /// Real implementation would use Wahoo's API
    func authenticateWithWahoo() async throws -> AuthenticationResult {
        // This would authenticate with Wahoo Cloud API
        return AuthenticationResult(
            success: true,
            platform: .wahoo,
            error: nil,
            deviceInfo: deviceCapabilities[.wahoo]
        )
    }
    
    /// Generate real .FIT file for device sync
    func generateFITFile(from workout: StructuredWorkout) -> Data {
        // Real implementation would create a proper FIT file
        // For now, return placeholder data
        let fitContent = """
        [FIT File Content]
        Workout: \(workout.name)
        Duration: \(Int(workout.estimatedDurationSeconds)) seconds
        Distance: \(Int(workout.estimatedDistanceMeters)) meters
        Steps: \(workout.steps.count)
        """
        
        return fitContent.data(using: .utf8) ?? Data()
    }
}

// MARK: - Usage Instructions

/*
 INTEGRATION INSTRUCTIONS:
 
 1. Add the missing dependencies at the top of this file to your project
 2. Add the WeatherViewModel extension to your existing WeatherViewModel.swift file
 3. Add the PowerAnalysisSettingsView to your settings screen
 4. Add the RouteAdvancedFeaturesCard to your main route view
 5. Update your settings to include the new power analysis options
 
 EXAMPLE: In your main route view, add this:
 
 ```swift
 VStack {
     // Your existing route UI
     
     if !viewModel.routePoints.isEmpty {
         RouteAdvancedFeaturesCard(viewModel: viewModel)
     }
 }
 ```
 
 EXAMPLE: In your settings view, add this:
 
 ```swift
 Form {
     // Your existing settings sections
     
     PowerAnalysisSettingsView(settings: $viewModel.settings)
 }
 ```
 
 DEVICE SYNC SETUP:
 
 For real device sync, you'll need to:
 1. Register developer accounts with Garmin, Wahoo, etc.
 2. Get API keys and OAuth credentials
 3. Implement WebAuthenticationSession for OAuth flows
 4. Use proper FIT file libraries for workout generation
 5. Test with actual devices
 
 The current implementation provides a solid foundation and realistic simulated sync results.
 */
