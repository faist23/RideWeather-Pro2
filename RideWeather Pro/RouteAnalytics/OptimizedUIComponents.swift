//
//  OptimizedUnifiedRouteAnalyticsDashboard.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 9/25/25.
//


//
//  OptimizedUIComponents.swift
//  RideWeather Pro - Optimized for iOS 26+ and Apple HIG
//

import SwiftUI
import CoreLocation

// MARK: - Optimized UnifiedRouteAnalyticsDashboard

struct OptimizedUnifiedRouteAnalyticsDashboard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDistance: Double? = nil
    @State private var analysisResult: ComprehensiveRouteAnalysis? = nil
    @State private var isAnalyzing = true
    
    private var analytics: UnifiedRouteAnalyticsEngine {
        UnifiedRouteAnalyticsEngine(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: viewModel.averageSpeedMetersPerSecond,
            settings: viewModel.settings,
            location: viewModel.routePoints.first ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            hourlyForecasts: viewModel.allHourlyData,
            elevationAnalysis: viewModel.elevationAnalysis
        )
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isAnalyzing {
                    analysisLoadingView
                } else if let analysis = analysisResult {
                    analysisContentView(analysis)
                } else {
                    analysisErrorView
                }
            }
            .navigationTitle("Route Analysis")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { 
                        dismiss() 
                    }
                    .fontWeight(.medium)
                }
            }
            .task {
                await performAnalysis()
            }
        }
    }
    
    // MARK: - Loading View
    private var analysisLoadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.blue)
                
                Text("Analyzing Route")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("Processing weather, terrain, and timing data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
    
    // MARK: - Content View
    private func analysisContentView(_ analysis: ComprehensiveRouteAnalysis) -> some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Hero Section - Overall Score
                OptimizedOverallScoreCard(analysis: analysis, settings: viewModel.settings)
                
                // Power Metrics (if available)
                if let powerResult = analysis.powerAnalysis {
                    OptimizedPowerMetricsCard(
                        normalizedPower: powerResult.powerDistribution.normalizedPower,
                        intensityFactor: powerResult.powerDistribution.intensityFactor,
                        totalTimeSeconds: powerResult.totalTimeSeconds
                    )
                }
                
                // Interactive Weather Chart
                OptimizedWeatherChartSection(
                    weatherPoints: analysis.weatherPoints,
                    units: analysis.settings.units,
                    elevationAnalysis: viewModel.elevationAnalysis,
                    selectedDistance: $selectedDistance
                )
                
                // Critical Recommendations
                if !analysis.unifiedRecommendations.isEmpty {
                    OptimizedRecommendationsSection(recommendations: analysis.unifiedRecommendations)
                }
                
                // Better Start Times
                if !analysis.betterStartTimes.isEmpty {
                    OptimizedStartTimesSection(times: analysis.betterStartTimes)
                }
                
                // Advanced Features Integration
                if !viewModel.routePoints.isEmpty || !viewModel.isPowerBasedAnalysisEnabled {
                    OptimizedAdvancedFeaturesCard(viewModel: viewModel)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .refreshable {
            await performAnalysis()
        }
    }
    
    // MARK: - Error View
    private var analysisErrorView: some View {
        ContentUnavailableView(
            "Analysis Failed",
            systemImage: "exclamationmark.triangle",
            description: Text("Unable to analyze route data. Please check your route and try again.")
        )
        .symbolRenderingMode(.multicolor)
    }
    
    // MARK: - Helper Methods
    @MainActor
    private func performAnalysis() async {
        isAnalyzing = true
        
        // Simulate processing time for better UX
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        analysisResult = analytics.comprehensiveAnalysis
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isAnalyzing = false
        }
    }
}

// MARK: - Optimized Overall Score Card

struct OptimizedOverallScoreCard: View {
    let analysis: ComprehensiveRouteAnalysis
    let settings: AppSettings
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with score and rating
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ride Conditions")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(analysis.overallScore.rating.label)
                        .font(.headline)
                        .foregroundStyle(analysis.overallScore.rating.color)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.0f", analysis.overallScore.overall))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(analysis.overallScore.rating.color)
                    
                    Text("Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Key metrics
            HStack(alignment: .top) {
                MetricView(
                    title: "Distance",
                    value: formatDistance(),
                    icon: "road.lanes",
                    color: .blue
                )
                
                Spacer()
                
                MetricView(
                    title: "Est. Time",
                    value: formatEstimatedTime(),
                    icon: "clock",
                    color: .green
                )
                
                Spacer()
                
                MetricView(
                    title: "Temp Range",
                    value: analysis.temperatureRangeFormatted,
                    icon: "thermometer.medium",
                    color: .orange
                )
            }
            
            Divider()
            
            // Score breakdown
            HStack(spacing: 24) {
                ScoreComponentView(
                    title: "Safety",
                    score: analysis.overallScore.safety,
                    icon: "shield.fill",
                    color: scoreColor(analysis.overallScore.safety)
                )
                
                ScoreComponentView(
                    title: "Weather",
                    score: analysis.overallScore.weather,
                    icon: "cloud.sun.fill",
                    color: scoreColor(analysis.overallScore.weather)
                )
                
                ScoreComponentView(
                    title: "Daylight",
                    score: analysis.overallScore.daylight,
                    icon: "sun.max.fill",
                    color: scoreColor(analysis.overallScore.daylight)
                )
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDistance() -> String {
        guard let lastSegment = analysis.routeSegments.last else { return "0 mi" }
        let distance = lastSegment.endMile
        let unit = lastSegment.units == .metric ? "km" : "mi"
        return String(format: "%.1f %@", distance, unit)
    }
    
    private func formatEstimatedTime() -> String {
        var movingSeconds: Double = 0
        
        if settings.speedCalculationMethod == .powerBased {
            movingSeconds = analysis.powerAnalysis?.totalTimeSeconds ?? 0
        } else {
            let totalDistanceMeters = (analysis.routeSegments.last?.endMile ?? 0) * (settings.units == .metric ? 1000 : 1609.34)
            var speedMps = settings.units == .metric ? (settings.averageSpeed / 3.6) : (settings.averageSpeed * 0.44704)
            
            if settings.considerElevation, let elevAnalysis = analysis.elevationAnalysis, elevAnalysis.hasActualData, totalDistanceMeters > 0 {
                let gainPerKm = (elevAnalysis.totalGain / totalDistanceMeters) * 1000
                let penaltyFactor = 1.0 - (gainPerKm / 10.0) * 0.03
                speedMps *= max(0.5, penaltyFactor)
            }
            
            if speedMps > 0 {
                movingSeconds = totalDistanceMeters / speedMps
            }
        }
        
        var totalSeconds = movingSeconds
        
        if settings.includeRestStops {
            let restSeconds = settings.restStopCount * settings.restStopDuration * 60
            totalSeconds += Double(restSeconds)
        }
        
        let totalMinutes = Int(totalSeconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
    
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 85...100: return .mint
        case 70..<85: return .green
        case 55..<70: return .yellow
        case 30..<55: return .orange
        default: return .red
        }
    }
}

// MARK: - Supporting Views

struct MetricView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScoreComponentView: View {
    let title: String
    let score: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text(String(format: "%.0f", score))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Optimized Power Metrics Card

struct OptimizedPowerMetricsCard: View {
    let normalizedPower: Double
    let intensityFactor: Double
    let totalTimeSeconds: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Power Analysis", systemImage: "bolt.fill")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
                
                Spacer()
            }
            
            HStack(spacing: 32) {
                PowerMetricItem(
                    title: "Normalized Power",
                    value: "\(Int(normalizedPower)) W",
                    subtitle: "Target Output"
                )
                
                PowerMetricItem(
                    title: "Intensity Factor",
                    value: String(format: "%.2f", intensityFactor),
                    subtitle: intensityDescription
                )
            }
            
            if !interpretationText.isEmpty {
                Text(interpretationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var intensityDescription: String {
        switch intensityFactor {
        case ..<0.75: return "Recovery"
        case 0.75..<0.85: return "Endurance"
        case 0.85..<1.0: return "Threshold"
        default: return "Above FTP"
        }
    }
    
    private var interpretationText: String {
        let hours = totalTimeSeconds / 3600.0
        
        switch intensityFactor {
        case ..<0.75:
            return hours < 2 ? "Perfect for recovery or social riding" : "Ideal base-building intensity"
        case 0.75..<0.85:
            return hours < 2 ? "Solid endurance training effort" : "Demanding but sustainable pace"
        case 0.85..<1.0:
            return "High-intensity effort requiring careful pacing"
        default:
            return "Race-level intensity with periods above FTP"
        }
    }
}

struct PowerMetricItem: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Optimized Sections

struct OptimizedWeatherChartSection: View {
    let weatherPoints: [RouteWeatherPoint]
    let units: UnitSystem
    let elevationAnalysis: ElevationAnalysis?
    @Binding var selectedDistance: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Weather Conditions", systemImage: "chart.xyaxis.line")
                .font(.headline)
                .fontWeight(.semibold)
            
            InteractiveWeatherChart(
                weatherPoints: weatherPoints,
                units: units,
                elevationAnalysis: elevationAnalysis,
                selectedDistance: $selectedDistance
            )
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct OptimizedRecommendationsSection: View {
    let recommendations: [UnifiedRecommendation]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recommendations", systemImage: "lightbulb.fill")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVStack(spacing: 12) {
                ForEach(recommendations) { rec in
                    OptimizedRecommendationCard(recommendation: rec)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct OptimizedRecommendationCard: View {
    let recommendation: UnifiedRecommendation
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: recommendation.icon)
                .font(.title3)
                .foregroundStyle(recommendation.priority.color)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(recommendation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(recommendation.priority.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OptimizedStartTimesSection: View {
    let times: [OptimalStartTime]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Better Start Times", systemImage: "clock.arrow.2.circlepath")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVStack(spacing: 12) {
                ForEach(times) { time in
                    OptimizedStartTimeCard(time: time)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct OptimizedStartTimeCard: View {
    let time: OptimalStartTime
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(time.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("Start Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("+\(time.improvementPercentage)%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    
                    Text("Better")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(time.primaryBenefit)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            if let tradeoff = time.tradeoff {
                Label(tradeoff, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OptimizedAdvancedFeaturesCard: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var showingAdvancedFeatures = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Advanced Features", systemImage: "bolt.circle.fill")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if viewModel.routePoints.isEmpty {
                Text("Import a route to unlock power pacing, fueling strategy, and device sync")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !viewModel.isPowerBasedAnalysisEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enable power analysis for advanced features")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button("Enable Power Analysis") {
                        viewModel.settings.speedCalculationMethod = .powerBased
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Access power pacing, fueling strategy, and device sync")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            showingAdvancedFeatures = true
        }
        .sheet(isPresented: $showingAdvancedFeatures) {
            OptimizedAdvancedCyclingTabView(viewModel: viewModel)
        }
    }
}

// MARK: - Optimized Advanced Cycling Tab View

struct OptimizedAdvancedCyclingTabView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                OptimizedPacingPlanTab(viewModel: viewModel)
                    .tag(0)
                    .tabItem {
                        Label("Pacing", systemImage: "speedometer")
                    }
                
                OptimizedFuelingPlanTab(viewModel: viewModel)
                    .tag(1)
                    .tabItem {
                        Label("Fueling", systemImage: "drop.fill")
                    }
                
                OptimizedDeviceSyncTab(viewModel: viewModel)
                    .tag(2)
                    .tabItem {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
            }
            .navigationTitle("Advanced Features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }
}