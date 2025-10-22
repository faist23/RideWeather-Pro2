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
                RouteInfoCardView(viewModel: viewModel)
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
                InteractiveWeatherChart(
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
//            RideAnalysisTabView(viewModel: viewModel)
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
                OptimizedPacingPlanTab(viewModel: viewModel, selectedTab: $selectedTab)
                    .tag(0)
                    .tabItem {
                        Label("Pacing", systemImage: "speedometer")
                    }
                
                FuelingPlanTab(viewModel: viewModel)
                    .tag(1)
                    .tabItem {
                        Label("Fueling", systemImage: "drop.fill")
                    }
                
                UpdatedOptimizedExportTab(viewModel: viewModel)
                    .tag(2)
                    .tabItem {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                RideAnalysisView(weatherViewModel: viewModel)
                    .tag(3)
                    .tabItem {
                        Label("Analysis", systemImage: "chart.xyaxis.line")
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

// MARK: - Optimized Pacing Plan Tab

struct OptimizedPacingPlanTab: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var showingExport = false
    @State private var showingDetails = false
    @State private var exportText = ""
    @State private var isGenerating = false
    
    @Binding var selectedTab: Int
    
    private var hasNewStrategySelection: Bool {
        guard let lastPlan = viewModel.advancedController?.pacingPlan else {
            return false
        }
        return viewModel.selectedPacingStrategy != lastPlan.strategy  // Use viewModel property
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                RouteInfoCardView(viewModel: viewModel)
                // Strategy Selection Card
                strategySelectionCard
                
                // Plan Content
                Group {
                    if isGenerating || viewModel.isGeneratingAdvancedPlan {
                        PacingPlanLoadingCard()
                    } else if let error = viewModel.advancedPlanError {
                        ErrorStateCard(
                            title: "Generation Failed",
                            message: error,
                            retryAction: { await generatePlan() }
                        )
                    } else if let pacing = adjustedPacingPlan { // <-- Use the ADJUSTED plan
                        OptimizedPacingPlanCard(
                            pacing: pacing, // <-- Now it gets the tweaked version
                            settings: viewModel.settings,
                            controller: viewModel.advancedController!, // Use ! because we know it exists if adjustedPacingPlan isn't nil
                            onViewDetails: { showingDetails = true },
                            onExportPlan: {
                                if let plan = adjustedPacingPlan {
                                    exportText = viewModel.advancedController!.exportPacingPlanCSV(using: plan)
                                    showingExport = true
                                }
                            }
                        )
                    } else {
                        EmptyPacingPlanCard()
                    }
                }
            }
            .padding()
        }
        .onChange(of: viewModel.selectedPacingStrategy) { oldValue, newValue in
            // Reset intensity adjustment when strategy changes
            viewModel.intensityAdjustment = 0
        }
        .refreshable {
            await generatePlan()
        }
        .sheet(isPresented: $showingExport) {
            ShareSheet(activityItems: [exportText])
        }
        .sheet(isPresented: $showingDetails) {
            if let pacing = adjustedPacingPlan, let controller = viewModel.advancedController {
                DetailedPacingPlanView(
                    viewModel: viewModel,
                    pacing: pacing,
                    controller: controller,
                    onGoToExportTab: {
                        // Set the selected tab to 2 (the Export tab)
                        selectedTab = 2
                    }
                )
            }
        }
    }
        
    // MARK: - Strategy Selection Card
    
    private var strategySelectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Pacing Strategy", systemImage: "target")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Strategy Picker (iOS native)
            Picker("Strategy", selection: $viewModel.selectedPacingStrategy) {
                ForEach(PacingStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.description)
                        .tag(strategy)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Strategy Description
            Text(strategyDescription(for: viewModel.selectedPacingStrategy))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Status Message
            if hasNewStrategySelection {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("New strategy selected. Generate to see updated plan.")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                .padding(12)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Generate Button
            Button(action: { Task { await generatePlan() } }) {
                HStack {
                    if isGenerating || viewModel.isGeneratingAdvancedPlan {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Generating Plan...")
                    } else {
                        Text(hasNewStrategySelection ? "Regenerate Plan" : "Generate Pacing Plan")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || viewModel.isGeneratingAdvancedPlan)
            
            Divider()

            Stepper(
                "Intensity Adjustment: \(viewModel.intensityAdjustment, specifier: "%.0f")%",
                value: $viewModel.intensityAdjustment,
                in: -20...20, // Allow adjusting +/- 20%
                step: 1
            )
            .disabled(viewModel.advancedController?.pacingPlan == nil) // Disable if no plan exists

        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func generatePlan() async {
        isGenerating = true
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        await viewModel.generateAdvancedCyclingPlan(
            strategy: viewModel.selectedPacingStrategy,  // Use viewModel property
            startTime: viewModel.rideDate
        )

        isGenerating = false
    }
    
    private func strategyDescription(for strategy: PacingStrategy) -> String {
        switch strategy {
        case .balanced:
            return "Well-rounded approach balancing speed and sustainability for most riders"
        case .conservative:
            return "Start easier and maintain energy reserves for the latter portion of the ride"
        case .aggressive:
            return "A race-pace effort that starts hard, maintains a high tempo, and finishes by emptying the tank for the fastest possible time."
        case .negativeSplit:
            return "Build power output progressively throughout the ride duration"
        case .evenEffort:
            return "Adjust power for terrain to maintain constant physiological stress"
        }
    }
    
    private var adjustedPacingPlan: PacingPlan? {
        viewModel.finalPacingPlan // <-- Just pass through the value from the viewModel
    }
    
}

// MARK: - Optimized Pacing Plan Card

struct OptimizedPacingPlanCard: View {
    let pacing: PacingPlan
    let settings: AppSettings
    let controller: AdvancedCyclingController
    let onViewDetails: () -> Void
    let onExportPlan: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generated Plan")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(pacing.strategy.description)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                DifficultyBadge(difficulty: pacing.difficulty)
            }
            
            // Key Metrics
            HStack(spacing: 24) {
                PlanMetricView(
                    title: "Distance",
                    value: formatDistance(pacing.totalDistance),
                    icon: "road.lanes"
                )
                
                PlanMetricView(
                    title: "Duration",
                    value: formatDuration(pacing.totalTimeMinutes * 60),
                    icon: "clock"
                )
                
                VStack(spacing: 4) {
                    Image(systemName: "bolt")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    
                    Text("Power")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 1) {
                        Text("\(Int(pacing.normalizedPower))W")
                            .font(.callout)
                            .fontWeight(.semibold)
                        Text("NP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            // Intensity Warning
            if pacing.intensityFactor > 0.85 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("High intensity ride (IF \(String(format: "%.2f", pacing.intensityFactor))) - pace carefully")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            
            // Actions
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button("View Details") {
                        onViewDetails()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDistance(_ distanceKm: Double) -> String {
        if settings.units == .metric {
            return String(format: "%.1f km", distanceKm)
        } else {
            let miles = distanceKm * 0.621371
            return String(format: "%.1f mi", miles)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Supporting Views for Pacing

struct PlanMetricView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.blue)
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DifficultyBadge: View {
    let difficulty: DifficultyRating  // This matches your enum from PacingEngine.swift
    
    var body: some View {
        Text(difficulty.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: difficulty.color).opacity(0.2))
            .foregroundStyle(Color(hex: difficulty.color))
            .clipShape(Capsule())
    }
}

struct PacingPlanLoadingCard: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                ProgressView()
                    .controlSize(.regular)
                Text("Generating pacing plan...")
                    .font(.headline)
                Spacer()
            }
            
            Text("Analyzing route segments and optimizing power distribution")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct EmptyPacingPlanCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "speedometer")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
            
            Text("No Pacing Plan")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Generate a power-based pacing plan to optimize your ride performance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Optimized Export Tab 

struct UpdatedOptimizedExportTab: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var exportingFIT = false
    @State private var exportingCSV = false
    @State private var exportingSummary = false
    @State private var exportError: String?
    @State private var currentShareItem: URL? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Route Info Card
                if !viewModel.routeDisplayName.isEmpty {
                    RouteInfoCardView(viewModel: viewModel)
                }
                
                // Export Status Card
                exportStatusCard
                
                // Available Export Options
                if viewModel.advancedController?.pacingPlan != nil {
                    exportOptionsCard
                } else {
                    exportUnavailableCard
                }
                
                // Help & Tips
                exportTipsCard
            }
            .padding()
        }
        .sheet(item: Binding<ShareableItem?>(
            get: { currentShareItem.map { ShareableItem(url: $0) } },
            set: { _ in currentShareItem = nil }
        )) { item in
            ShareSheet(activityItems: [item.url])
        }
    }
    
    // MARK: - View Components
    
    private var exportStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Export Status", systemImage: "info.circle.fill")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 8) {
                ExportStatusRow(
                    title: "Garmin Course FIT",
                    status: .available,
                    description: "GPS route with power targets for Garmin Edge/Forerunner"
                )
                
                ExportStatusRow(
                    title: "CSV Export",
                    status: .available,
                    description: "Spreadsheet format for analysis and custom integrations"
                )
                
                ExportStatusRow(
                    title: "Device Sync",
                    status: .comingSoon,
                    description: "Direct sync to Garmin Connect, Wahoo, and Zwift (coming soon)"
                )
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var exportOptionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Export Workout", systemImage: "square.and.arrow.up.fill")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ExportOptionButton(
                    title: "Export Garmin Course FIT",
                    subtitle: "GPS route with power guidance for Garmin devices",
                    icon: "doc.fill",
                    isLoading: exportingFIT
                ) {
                    await exportFitFile()
                }
                
                ExportOptionButton(
                    title: "Export CSV Data",
                    subtitle: "Detailed segment-by-segment breakdown",
                    icon: "tablecells.fill",
                    isLoading: exportingCSV
                ) {
                    await exportCSVFile()
                }
                
                ExportOptionButton(
                    title: "Pacing Plan Summary",
                    subtitle: "Printable summary with key information",
                    icon: "doc.text.fill",
                    isLoading: exportingSummary
                ) {
                    await exportPlanSummary()
                }
            }
            
            if let error = exportError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(8)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var exportUnavailableCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
            
            Text("No Workout to Export")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Generate a pacing plan first to create exportable workout files")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var exportTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Export Tips", systemImage: "lightbulb.fill")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 8) {
                TipRow(
                    icon: "desktopcomputer",
                    text: "Upload FIT files to Garmin Connect, then sync to your device"
                )
                
                TipRow(
                    icon: "map",
                    text: "Course files show GPS route + power targets on your bike computer"
                )
                
                TipRow(
                    icon: "iphone",
                    text: "Use AirDrop to quickly transfer files to your cycling computer"
                )
                
                TipRow(
                    icon: "printer.fill",
                    text: "Print the race summary for easy reference during your ride"
                )
                
                if !viewModel.routeDisplayName.isEmpty {
                    TipRow(
                        icon: "tag.fill",
                        text: "Exported files will be named: '\(viewModel.routeDisplayName)-course-power.fit'"
                    )
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Export Methods
    
    private func exportFitFile() async {
        await MainActor.run {
            exportingFIT = true
            exportError = nil
        }
        
        // Give UI time to show loading indicator
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        guard viewModel.advancedController != nil else {
            await MainActor.run {
                exportError = "No workout data available"
                exportingFIT = false
            }
            return
        }
        
        do {
            // Use the new Garmin Course FIT export
            guard let tempFile = try await viewModel.exportGarminCourseFIT() else {
                await MainActor.run {
                    exportError = "Failed to generate Garmin Course FIT file"
                    exportingFIT = false
                }
                return
            }
            
            await MainActor.run {
                currentShareItem = tempFile
                exportingFIT = false
            }
            
        } catch {
            await MainActor.run {
                exportError = "Export failed: \(error.localizedDescription)"
                exportingFIT = false
            }
        }
    }
    
    private func exportCSVFile() async {
        await MainActor.run {
            exportingCSV = true
            exportError = nil
        }
        
        // Give UI time to show loading indicator
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        guard let controller = viewModel.advancedController else {
            await MainActor.run {
                exportError = "No workout data available"
                exportingCSV = false
            }
            return
        }
        
        do {
            guard let planToExport = viewModel.finalPacingPlan else {
                await MainActor.run { exportError = "No plan available to export." }
                exportingCSV = false
                return
            }
            
            let csvData = await MainActor.run {
                controller.exportPacingPlanCSV(using: planToExport) // <-- Pass the adjusted plan
            }

            let tempDir = FileManager.default.temporaryDirectory
            let customFilename = viewModel.generateExportFilename(
                baseName: nil,
                suffix: "pacing",
                extension: "csv"
            )
            let tempFile = tempDir.appendingPathComponent(customFilename)
            
            try csvData.write(to: tempFile, atomically: true, encoding: .utf8)
            
            await MainActor.run {
                currentShareItem = tempFile
                exportingCSV = false
            }
            
        } catch {
            await MainActor.run {
                exportError = "Failed to save CSV file: \(error.localizedDescription)"
                exportingCSV = false
            }
        }
    }

    private func exportPlanSummary() async {
        await MainActor.run {
            exportingSummary = true
            exportError = nil
        }
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        guard let controller = viewModel.advancedController,
              let pacingPlan = controller.pacingPlan else {  // Get the pacing plan
            await MainActor.run {
                exportError = "No workout data available"
                exportingSummary = false
            }
            return
        }
        
        do {
            guard let planToExport = viewModel.finalPacingPlan, // <-- Get the final plan
                  let controller = viewModel.advancedController else {
                await MainActor.run { exportError = "No plan available to export." }
                exportingSummary = false
                return
            }
            
            let summary = await MainActor.run {
                // Call the correct, detailed summary function on the controller
                controller.generateRaceDaySummary(using: planToExport)
            }

            let tempDir = FileManager.default.temporaryDirectory
            let customFilename = viewModel.generateExportFilename(
                baseName: nil,
                suffix: "pacing-summary",  // Better name
                extension: "txt"
            )
            let tempFile = tempDir.appendingPathComponent(customFilename)
            
            try summary.write(to: tempFile, atomically: true, encoding: .utf8)
            
            await MainActor.run {
                currentShareItem = tempFile
                exportingSummary = false
            }
            
        } catch {
            await MainActor.run {
                exportError = "Failed to save summary file: \(error.localizedDescription)"
                exportingSummary = false
            }
        }
    }
}

// MARK: - Shared Error State Card

struct ErrorStateCard: View {
    let title: String
    let message: String
    let retryAction: () async -> Void
    
    @State private var isRetrying = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.red)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                Task {
                    isRetrying = true
                    await retryAction()
                    isRetrying = false
                }
            }) {
                HStack {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Retrying...")
                    } else {
                        Text("Try Again")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ShareableItem: Identifiable {
    let id = UUID()
    let url: URL
    
    init(url: URL) {
        self.url = url
    }
}

enum ExportStatus {
    case available
    case comingSoon
    case unavailable
    
    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .comingSoon: return "clock.fill"
        case .unavailable: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .available: return .green
        case .comingSoon: return .orange
        case .unavailable: return .red
        }
    }
}

struct ExportStatusRow: View {
    let title: String
    let status: ExportStatus
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

struct ExportOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isLoading: Bool
    let action: () async -> Void
    
    @State private var isPerformingAction = false
    
    var body: some View {
        Button(action: {
            Task {
                isPerformingAction = true
                await action()
                isPerformingAction = false
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isPerformingAction || isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        
                        Text("Working...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .opacity((isPerformingAction || isLoading) ? 0.8 : 1.0)
        }
        .disabled(isPerformingAction || isLoading)
        .buttonStyle(.plain)
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FuelingTimelineView: View {
    let schedule: [FuelPoint]
    @State private var selectedPoint: FuelPoint?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(schedule.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline connector
                    VStack(spacing: 0) {
                        if index > 0 {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 2, height: 20)
                        }
                        
                        // Time marker
                        ZStack {
                            Circle()
                                .fill(fuelTypeColor(point.fuelType))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: fuelTypeIcon(point.fuelType))
                                .foregroundStyle(.white)
                                .font(.system(size: 14))
                        }
                        
                        if index < schedule.count - 1 {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 2, height: 20)
                        }
                    }
                    
                    // Fuel point content
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(Int(point.timeMinutes))min")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Text(point.fuelType.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(fuelTypeColor(point.fuelType).opacity(0.2))
                                .foregroundStyle(fuelTypeColor(point.fuelType))
                                .clipShape(Capsule())
                        }
                        
                        Text(point.product)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Text(point.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Label("\(Int(point.intensity))% intensity", systemImage: "flame")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text("Segment \(point.segmentIndex + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.bottom, index < schedule.count - 1 ? 0 : 12)
            }
        }
    }
    
    private func fuelTypeColor(_ type: FuelType) -> Color {
        switch type {
        case .gel: return .orange
        case .drink: return .blue
        case .bar: return .brown
        case .solid: return .green
        case .electrolytes: return .purple
        }
    }
    
    private func fuelTypeIcon(_ type: FuelType) -> String {
        switch type {
        case .gel: return "drop.fill"
        case .drink: return "cup.and.saucer.fill"
        case .bar: return "rectangle.fill"
        case .solid: return "leaf.fill"
        case .electrolytes: return "bolt.fill"
        }
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

