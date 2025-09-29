//
//  UnifiedRouteAnalyticsEngine.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/19/25.
//


//
//  CombinedRouteAnalytics.swift
//  RideWeather Pro
//
//  Unified analytics combining safety and weather insights
//

import SwiftUI
import CoreLocation

// MARK: - Unified Analytics Engine

struct UnifiedRouteAnalyticsEngine {
    let weatherPoints: [RouteWeatherPoint]
    let rideStartTime: Date
    let averageSpeed: Double
    let units: UnitSystem
    let location: CLLocationCoordinate2D
    
    // Initialize both analytics engines
    private var safetyEngine: SafetyAnalyticsEngine {
        SafetyAnalyticsEngine(
            weatherPoints: weatherPoints,
            rideStartTime: rideStartTime,
            averageSpeed: averageSpeed,
            units: units,
            location: location
        )
    }
    
    private var enhancedInsights: EnhancedRouteInsights {
        EnhancedRouteInsights(
            weatherPoints: weatherPoints,
            rideStartTime: rideStartTime,
            averageSpeed: averageSpeed,
            units: units
        )
    }
    
    // MARK: - Combined Analytics
    
    var comprehensiveAnalysis: ComprehensiveRouteAnalysis {
        let safetyAnalysis = safetyEngine.combinedSafetyScore
        let daylightAnalysis = safetyEngine.daylightAnalysis
        let weatherSafety = safetyEngine.weatherSafetyAnalysis
        let criticalInsights = enhancedInsights.criticalInsights
        let segments = enhancedInsights.detailedSegments
        
        return ComprehensiveRouteAnalysis(
            overallScore: calculateOverallScore(),
            safetyScore: safetyAnalysis,
            daylightAnalysis: daylightAnalysis,
            weatherSafety: weatherSafety,
            criticalInsights: criticalInsights,
            routeSegments: segments,
            unifiedRecommendations: generateUnifiedRecommendations(),
            betterStartTimes: findOptimalStartTimes()
        )
    }
    
    // MARK: - Private Methods
    
    private func calculateOverallScore() -> UnifiedRouteScore {
        let safetyScore = safetyEngine.combinedSafetyScore.score
        let weatherScore = calculateWeatherComfortScore()
        let daylightScore = calculateDaylightScore()
        
        let overallScore = (safetyScore * 0.4) + (weatherScore * 0.4) + (daylightScore * 0.2)
        
        return UnifiedRouteScore(
            overall: overallScore,
            safety: safetyScore,
            weather: weatherScore,
            daylight: daylightScore,
            rating: UnifiedRating.from(score: overallScore)
        )
    }
    
    private func calculateWeatherComfortScore() -> Double {
        guard !weatherPoints.isEmpty else { return 0 }
        
        var totalScore = 0.0
        let idealTemp = units == .metric ? 21.0 : 70.0
        
        for point in weatherPoints {
            var pointScore = 100.0
            
            // Temperature comfort
            let tempDiff = abs(point.weather.temp - idealTemp)
            pointScore -= tempDiff * 1.5
            
            // Wind penalty
            pointScore -= point.weather.windSpeed * 2.0
            
            // Humidity penalty
            pointScore -= Double(point.weather.humidity - 50) * 0.8
            
            totalScore += max(0, pointScore)
        }
        
        return totalScore / Double(weatherPoints.count)
    }
    
    private func calculateDaylightScore() -> Double {
        let analysis = safetyEngine.daylightAnalysis
        let totalDistance = enhancedInsights.totalDistance
        
        guard totalDistance > 0 else { return 100 }
        
        let darkPercentage = analysis.totalDarkDistance / totalDistance
        let goldenHourDistance = analysis.goldenHourSegments.reduce(0) { $0 + $1.distance }
        let goldenPercentage = goldenHourDistance / totalDistance
        
        var score = 100.0
        
        // Heavy penalty for darkness
        score -= darkPercentage * 60
        
        // Bonus for golden hour
        score += goldenPercentage * 20
        
        return max(0, min(100, score))
    }
    
    private func generateUnifiedRecommendations() -> [UnifiedRecommendation] {
        var recommendations: [UnifiedRecommendation] = []
        
        // Get recommendations from both systems
        let safetyRecs = safetyEngine.safetyRecommendations
        let insights = enhancedInsights.criticalInsights
        
        // Convert safety recommendations
        for safetyRec in safetyRecs {
            recommendations.append(UnifiedRecommendation(
                category: mapSafetyToUnified(safetyRec.type),
                priority: mapSafetyPriorityToUnified(safetyRec.priority),
                title: safetyRec.title,
                message: safetyRec.message,
                action: safetyRec.action,
                icon: safetyRec.icon,
                affectedDistance: safetyRec.affectedDistance,
                source: .safety
            ))
        }
        
        // Convert critical insights
        for insight in insights {
            recommendations.append(UnifiedRecommendation(
                category: .weather,
                priority: mapInsightPriorityToUnified(insight.priority),
                title: insight.title,
                message: insight.message,
                action: insight.recommendation,
                icon: insight.icon,
                affectedDistance: insight.affectedMileRange.end - insight.affectedMileRange.start,
                source: .weather
            ))
        }
        
        // Sort by priority and remove duplicates
        return recommendations
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
            .prefix(8)
            .map { $0 }
    }
    
    private func findOptimalStartTimes() -> [OptimalStartTime] {
        // Combine better start times with safety considerations
        let betterTimes = EnhancedRouteWeatherEngine.findBetterStartTimes(
            weatherPoints: weatherPoints,
            currentStartTime: rideStartTime,
            averageSpeed: averageSpeed,
            units: units
        )
        
        return betterTimes.map { betterTime in
            // Calculate safety score for this alternative time
            let altSafetyEngine = SafetyAnalyticsEngine(
                weatherPoints: weatherPoints,
                rideStartTime: betterTime.startTime,
                averageSpeed: averageSpeed,
                units: units,
                location: location
            )
            
            let altSafetyScore = altSafetyEngine.combinedSafetyScore
            
            return OptimalStartTime(
                startTime: betterTime.startTime,
                weatherImprovement: betterTime.improvementPercentage,
                safetyScore: altSafetyScore.score,
                primaryBenefit: betterTime.primaryBenefit,
                safetyBenefit: determineSafetyBenefit(altSafetyScore, vs: safetyEngine.combinedSafetyScore),
                overallImprovement: Int((altSafetyScore.score + betterTime.weatherScore.overallScore) / 2)
            )
        }.sorted { $0.overallImprovement > $1.overallImprovement }
    }
    
    // MARK: - Mapping Helpers
    
    private func mapSafetyToUnified(_ type: RecommendationType) -> UnifiedRecommendationCategory {
        switch type {
        case .lighting: return .lighting
        case .weather: return .weather
        case .timing: return .timing
        case .equipment: return .equipment
        case .optimal: return .optimal
        }
    }
    
    private func mapSafetyPriorityToUnified(_ priority: RecommendationPriority) -> UnifiedPriority {
        switch priority {
        case .positive: return .positive
        case .moderate: return .moderate
        case .important: return .important
        case .critical: return .critical
        }
    }
    
    private func mapInsightPriorityToUnified(_ priority: CriticalRideInsight.InsightPriorityLevel) -> UnifiedPriority {
        switch priority {
        case .critical: return .critical
        case .important: return .important
        case .moderate: return .moderate
        }
    }
    
    private func determineSafetyBenefit(_ newScore: SafetyScore, vs currentScore: SafetyScore) -> String {
        let improvement = newScore.score - currentScore.score
        if improvement > 10 {
            return "Significantly safer conditions"
        } else if improvement > 5 {
            return "Moderately improved safety"
        } else {
            return "Similar safety profile"
        }
    }
}

// MARK: - Unified Data Models

struct ComprehensiveRouteAnalysis {
    let overallScore: UnifiedRouteScore
    let safetyScore: SafetyScore
    let daylightAnalysis: DaylightAnalysis
    let weatherSafety: WeatherSafetyAnalysis
    let criticalInsights: [CriticalRideInsight]
    let routeSegments: [EnhancedRouteSegment]
    let unifiedRecommendations: [UnifiedRecommendation]
    let betterStartTimes: [OptimalStartTime]
}

struct UnifiedRouteScore {
    let overall: Double
    let safety: Double
    let weather: Double
    let daylight: Double
    let rating: UnifiedRating
}

enum UnifiedRating {
    case excellent, good, fair, caution, dangerous
    
    var color: Color {
        switch self {
        case .excellent: return .mint
        case .good: return .green
        case .fair: return .yellow
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
    
    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .caution: return "Use Caution"
        case .dangerous: return "Not Recommended"
        }
    }
    
    var emoji: String {
        switch self {
        case .excellent: return "🌟"
        case .good: return "✅"
        case .fair: return "⚠️"
        case .caution: return "🚨"
        case .dangerous: return "❌"
        }
    }
    
    static func from(score: Double) -> UnifiedRating {
        switch score {
        case 85...100: return .excellent
        case 70..<85: return .good
        case 55..<70: return .fair
        case 30..<55: return .caution
        default: return .dangerous
        }
    }
}

struct UnifiedRecommendation {
    let category: UnifiedRecommendationCategory
    let priority: UnifiedPriority
    let title: String
    let message: String
    let action: String
    let icon: String
    let affectedDistance: Double
    let source: RecommendationSource
}

enum UnifiedRecommendationCategory {
    case lighting, weather, timing, equipment, optimal
    
    var label: String {
        switch self {
        case .lighting: return "Lighting"
        case .weather: return "Weather"
        case .timing: return "Timing"
        case .equipment: return "Equipment"
        case .optimal: return "Optimization"
        }
    }
}

enum UnifiedPriority: Int {
    case positive = 0
    case moderate = 1
    case important = 2
    case critical = 3
    
    var color: Color {
        switch self {
        case .positive: return .mint
        case .moderate: return .blue
        case .important: return .orange
        case .critical: return .red
        }
    }
    
    var label: String {
        switch self {
        case .positive: return "GOOD NEWS"
        case .moderate: return "MODERATE"
        case .important: return "IMPORTANT"
        case .critical: return "CRITICAL"
        }
    }
}

enum RecommendationSource {
    case safety, weather
}

struct OptimalStartTime {
    let startTime: Date
    let weatherImprovement: Int
    let safetyScore: Double
    let primaryBenefit: String
    let safetyBenefit: String
    let overallImprovement: Int
}

// MARK: - Unified Dashboard View

struct UnifiedRouteAnalyticsDashboard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    private var analytics: UnifiedRouteAnalyticsEngine {
        UnifiedRouteAnalyticsEngine(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units,
            location: viewModel.routePoints.first ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Overall score header
                    OverallScoreHeader(analysis: analytics.comprehensiveAnalysis)
                    
                    // Critical recommendations
                    CriticalRecommendationsSection(recommendations: analytics.comprehensiveAnalysis.unifiedRecommendations)
                    
                    // Safety & Daylight analysis
                    SafetyDaylightSection(analysis: analytics.comprehensiveAnalysis)
                    
                    // Weather insights
                    WeatherInsightsSection(insights: analytics.comprehensiveAnalysis.criticalInsights)
                    
                    // Better start times
                    if !analytics.comprehensiveAnalysis.betterStartTimes.isEmpty {
                        OptimalTimingSection(times: analytics.comprehensiveAnalysis.betterStartTimes)
                    }
                    
                    // Route segments
                    RouteSegmentsSection(segments: analytics.comprehensiveAnalysis.routeSegments)
                }
                .padding()
                .padding(.bottom, 100)
            }
            .background(dynamicBackground.ignoresSafeArea())
            .navigationTitle("Complete Analysis")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    private var dynamicBackground: LinearGradient {
        let rating = analytics.comprehensiveAnalysis.overallScore.rating
        
        switch rating {
        case .excellent:
            return LinearGradient(colors: [.mint, .green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .good:
            return LinearGradient(colors: [.green, .blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .fair:
            return LinearGradient(colors: [.yellow, .orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .caution:
            return LinearGradient(colors: [.orange, .red, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dangerous:
            return LinearGradient(colors: [.red, .purple, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Section Views

struct OverallScoreHeader: View {
    let analysis: ComprehensiveRouteAnalysis
    
    var body: some View {
        VStack(spacing: 20) {
            // Main score display
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: analysis.overallScore.overall / 100)
                    .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1), value: analysis.overallScore.overall)
                
                VStack(spacing: 8) {
                    Text(analysis.overallScore.rating.emoji)
                        .font(.system(size: 32))
                    
                    Text("\(Int(analysis.overallScore.overall))")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text(analysis.overallScore.rating.label)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: 140, height: 140)
            
            // Score breakdown
            HStack(spacing: 20) {
                ScoreBreakdownItem(
                    label: "Safety",
                    score: analysis.overallScore.safety,
                    icon: "shield.fill"
                )
                
                ScoreBreakdownItem(
                    label: "Weather",
                    score: analysis.overallScore.weather,
                    icon: "cloud.fill"
                )
                
                ScoreBreakdownItem(
                    label: "Daylight",
                    score: analysis.overallScore.daylight,
                    icon: "sun.max.fill"
                )
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ScoreBreakdownItem: View {
    let label: String
    let score: Double
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
            
            Text("\(Int(score))")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct CriticalRecommendationsSection: View {
    let recommendations: [UnifiedRecommendation]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Key Recommendations", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            let criticalRecs = recommendations.filter { $0.priority == .critical || $0.priority == .important }
            
            if criticalRecs.isEmpty {
                Text("🎉 No critical issues identified! You're all set for a great ride.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(16)
                    .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(criticalRecs.indices, id: \.self) { index in
                        UnifiedRecommendationCard(recommendation: criticalRecs[index])
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct UnifiedRecommendationCard: View {
    let recommendation: UnifiedRecommendation
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: recommendation.icon)
                .font(.title3)
                .foregroundStyle(recommendation.priority.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(recommendation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Text(recommendation.priority.label)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(recommendation.priority.color.opacity(0.3), in: Capsule())
                        .foregroundStyle(recommendation.priority.color)
                }
                
                Text(recommendation.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                
                Text("💡 \(recommendation.action)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(12)
        .background(recommendation.priority.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(recommendation.priority.color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct SafetyDaylightSection: View {
    let analysis: ComprehensiveRouteAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Safety & Lighting", systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            HStack(spacing: 16) {
                // Daylight info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sun.and.horizon.fill")
                            .foregroundStyle(.orange)
                        Text("Daylight")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    
                    Text("Sunrise: \(analysis.daylightAnalysis.sunrise.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    
                    Text("Sunset: \(analysis.daylightAnalysis.sunset.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    
                    if analysis.daylightAnalysis.totalDarkDistance > 0 {
                        Text("⚠️ \(String(format: "%.1f", analysis.daylightAnalysis.totalDarkDistance)) mi in darkness")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(12)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                // Safety score
                VStack {
                    Text("\(Int(analysis.safetyScore.score))")
                        .font(.title.weight(.bold))
                        .foregroundStyle(analysis.safetyScore.level.color)
                    
                    Text("Safety Score")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct WeatherInsightsSection: View {
    let insights: [CriticalRideInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weather Insights", systemImage: "cloud.sun.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            if insights.isEmpty {
                Text("Stable weather conditions throughout your ride")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(insights.indices, id: \.self) { index in
                        WeatherInsightCompactCard(insight: insights[index])
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct WeatherInsightCompactCard: View {
    let insight: CriticalRideInsight
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: insight.icon)
                .foregroundStyle(insight.priority.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(insight.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(10)
        .background(insight.priority.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct OptimalTimingSection: View {
    let times: [OptimalStartTime]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Better Start Times", systemImage: "clock.arrow.2.circlepath")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            LazyVStack(spacing: 12) {
                ForEach(times.indices, id: \.self) { index in
                    OptimalTimeCard(time: times[index])
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct OptimalTimeCard: View {
    let time: OptimalStartTime
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(time.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text("Safety: \(Int(time.safetyScore))/100")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("+\(time.overallImprovement)%")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                    
                    Text("Better Overall")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green.opacity(0.8))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(time.primaryBenefit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green.opacity(0.9))
                
                Text(time.safetyBenefit)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
    }
}

struct RouteSegmentsSection: View {
    let segments: [EnhancedRouteSegment]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Route Breakdown", systemImage: "road.lanes")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            LazyVStack(spacing: 8) {
                ForEach(segments.prefix(6).indices, id: \.self) { index in
                    CompactSegmentCard(segment: segments[index])
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct CompactSegmentCard: View {
    let segment: EnhancedRouteSegment
    
    var body: some View {
        HStack {
            Text("Seg \(segment.segmentNumber)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.blue, in: Capsule())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "Miles %.1f-%.1f", segment.startMile, segment.endMile))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text("\(Int(segment.analysis.averageTemp))° • \(Int(segment.analysis.maxWind)) \(segment.units.speedUnitAbbreviation) winds")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            Circle()
                .fill(segment.analysis.riskLevel.color)
                .frame(width: 12, height: 12)
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Compact Card for Main View

struct UnifiedRouteAnalyticsCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var showingFullAnalysis = false
    
    private var analytics: UnifiedRouteAnalyticsEngine? {
        guard !viewModel.weatherDataForRoute.isEmpty else { return nil }
        
        return UnifiedRouteAnalyticsEngine(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units,
            location: viewModel.routePoints.first ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        )
    }
    
    var body: some View {
        guard let analytics = analytics else {
            return AnyView(EmptyView())
        }
        
        let analysis = analytics.comprehensiveAnalysis
        
        return AnyView(
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
                    
                    // Overall score ring
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 4)
                        
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
                
                // Quick insights row
                HStack(spacing: 16) {
                    QuickInsightChip(
                        icon: "shield.fill",
                        label: "Safety",
                        value: "\(Int(analysis.safetyScore.score))",
                        color: analysis.safetyScore.level.color
                    )
                    
                    QuickInsightChip(
                        icon: analysis.daylightAnalysis.totalDarkDistance > 0 ? "moon.fill" : "sun.max.fill",
                        label: "Lighting",
                        value: analysis.daylightAnalysis.visibilityRating.label,
                        color: analysis.daylightAnalysis.visibilityRating.color
                    )
                    
                    QuickInsightChip(
                        icon: "thermometer",
                        label: "Weather",
                        value: analysis.weatherSafety.overallSafetyRating == .safe ? "Good" : "Caution",
                        color: analysis.weatherSafety.overallSafetyRating.color
                    )
                }
                
                // Top recommendation preview
                if let topRec = analysis.unifiedRecommendations.first {
                    HStack(spacing: 8) {
                        Image(systemName: topRec.icon)
                            .font(.caption)
                            .foregroundStyle(topRec.priority.color)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topRec.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            
                            Text(topRec.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(topRec.priority.color.opacity(0.1), in: Capsule())
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
                UnifiedRouteAnalyticsDashboard()
                    .environmentObject(viewModel)
            }
        )
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

// MARK: - Integration Helper Functions

extension UnifiedRouteAnalyticsEngine {
    
    /// Quick summary for displaying in compact views
    var quickSummary: RouteQuickSummary {
        let analysis = comprehensiveAnalysis
        
        return RouteQuickSummary(
            overallRating: analysis.overallScore.rating,
            overallScore: analysis.overallScore.overall,
            primaryConcern: analysis.unifiedRecommendations.first?.title ?? "No major concerns",
            hasLightingIssues: analysis.daylightAnalysis.totalDarkDistance > 0,
            hasSafetyConcerns: analysis.safetyScore.score < 70,
            hasWeatherConcerns: !analysis.criticalInsights.isEmpty,
            recommendationCount: analysis.unifiedRecommendations.count
        )
    }
}

struct RouteQuickSummary {
    let overallRating: UnifiedRating
    let overallScore: Double
    let primaryConcern: String
    let hasLightingIssues: Bool
    let hasSafetyConcerns: Bool
    let hasWeatherConcerns: Bool
    let recommendationCount: Int
    
    var statusMessage: String {
        switch overallRating {
        case .excellent:
            return "Perfect conditions for cycling! 🌟"
        case .good:
            return "Great conditions with minor considerations"
        case .fair:
            return "Good conditions with some planning needed"
        case .caution:
            return "Manageable with proper preparation"
        case .dangerous:
            return "Consider postponing or route changes"
        }
    }
}

// MARK: - Updated RouteBottomControlsView Integration

extension RouteBottomControlsView {
    
    /// Updated version that uses the unified analytics
    var unifiedAnalyticsBody: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                ModernLoadingView()
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }
            
            // Use unified analytics instead of separate ones
            if !viewModel.weatherDataForRoute.isEmpty {
                UnifiedRouteAnalyticsCard()
                    .environmentObject(viewModel)
            }
            
            // Rest of the existing inputs and buttons...
            VStack(spacing: 0) {
                LabeledContent {
                    DatePicker(
                        "",
                        selection: $viewModel.rideDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                } label: {
                    Label("Ride Time", systemImage: "clock")
                        .font(.headline)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("Speed", text: $viewModel.averageSpeedInput)
                            .keyboardType(.decimalPad)
                            .focused($isSpeedFieldFocused)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        
                        Text(viewModel.settings.units.speedUnitAbbreviation)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Avg. Speed", systemImage: "speedometer")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            Button {
                isSpeedFieldFocused = false
                withAnimation(.smooth) {
                    showBottomControls = false
                }
                Task { await viewModel.calculateAndFetchWeather() }
            } label: {
                Label("Generate Forecast", systemImage: "cloud.sun.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.routePoints.isEmpty)
            .padding(.top, 8)
            
            Button {
                isImporting = true
            } label: {
                Label("Import New Route", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .shadow(color: .black.opacity(0.1), radius: 16, y: 4)
        .animation(.smooth, value: viewModel.weatherDataForRoute.count)
    }
}

// MARK: - Smart Notification Banner

struct SmartRouteBanner: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    private var analytics: UnifiedRouteAnalyticsEngine? {
        guard !viewModel.weatherDataForRoute.isEmpty else { return nil }
        
        return UnifiedRouteAnalyticsEngine(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units,
            location: viewModel.routePoints.first ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        )
    }
    
    var body: some View {
        if let analytics = analytics {
            let summary = analytics.quickSummary
            
            if summary.overallRating == .caution || summary.overallRating == .dangerous {
                HStack(spacing: 12) {
                    Image(systemName: summary.overallRating == .dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(summary.overallRating.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.overallRating.label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(summary.overallRating.color)
                        
                        Text(summary.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    Text("\(summary.recommendationCount) tips")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(summary.overallRating.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(summary.overallRating.color)
                }
                .padding(12)
                .background(summary.overallRating.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(summary.overallRating.color.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}