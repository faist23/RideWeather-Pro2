
//
//  SafetyAndDaylightAnalytics.swift
//  RideWeather Pro
//
//  Enhanced safety-focused analytics for daylight and weather conditions
//

import SwiftUI
import CoreLocation
import Solar

// MARK: - Safety Analytics Engine

struct SafetyAnalyticsEngine {
    let weatherPoints: [RouteWeatherPoint]
    let rideStartTime: Date
    let averageSpeed: Double
    let units: UnitSystem
    let location: CLLocationCoordinate2D
    
    // MARK: - Daylight Analysis
    
    var daylightAnalysis: DaylightAnalysis {
        let sunrise = calculateSunrise()
        let sunset = calculateSunset()
        let rideEnd = estimatedEndTime()
        
        let darkSegments = calculateDarkSegments(sunrise: sunrise, sunset: sunset, rideEnd: rideEnd)
        let goldenHourSegments = calculateGoldenHourSegments(sunrise: sunrise, sunset: sunset, rideEnd: rideEnd)
        
        return DaylightAnalysis(
            sunrise: sunrise,
            sunset: sunset,
            rideStartTime: rideStartTime,
            rideEndTime: rideEnd,
            darkSegments: darkSegments,
            goldenHourSegments: goldenHourSegments,
            totalDarkDistance: darkSegments.reduce(0) { $0 + $1.distance },
            visibilityRating: calculateVisibilityRating(darkSegments: darkSegments, goldenHour: goldenHourSegments)
        )
    }
    
    // MARK: - Weather Safety Analysis
    
    var weatherSafetyAnalysis: WeatherSafetyAnalysis {
        let dangerousConditions = identifyDangerousWeatherSegments()
        let cautionaryConditions = identifyCautionaryWeatherSegments()
        let optimalConditions = identifyOptimalWeatherSegments()
        
        return WeatherSafetyAnalysis(
            dangerousSegments: dangerousConditions,
            cautionarySegments: cautionaryConditions,
            optimalSegments: optimalConditions,
            overallSafetyRating: calculateOverallSafetyRating(dangerous: dangerousConditions, cautionary: cautionaryConditions),
            primaryConcerns: identifyPrimaryConcerns(dangerous: dangerousConditions, cautionary: cautionaryConditions)
        )
    }
    
    // MARK: - Combined Safety Score
    
    var combinedSafetyScore: SafetyScore {
        let daylight = daylightAnalysis
        let weather = weatherSafetyAnalysis
        
        var score: Double = 100
        
        // Deduct for darkness
        if daylight.totalDarkDistance > 0 {
            let darkPercentage = daylight.totalDarkDistance / totalDistance()
            score -= darkPercentage * 40 // Heavy penalty for darkness
        }
        
        // Deduct for dangerous weather
        let dangerousDistance = weather.dangerousSegments.reduce(0) { $0 + $1.distance }
        if dangerousDistance > 0 {
            let dangerousPercentage = dangerousDistance / totalDistance()
            score -= dangerousPercentage * 50 // Severe penalty for dangerous weather
        }
        
        // Deduct for cautionary weather
        let cautionaryDistance = weather.cautionarySegments.reduce(0) { $0 + $1.distance }
        if cautionaryDistance > 0 {
            let cautionaryPercentage = cautionaryDistance / totalDistance()
            score -= cautionaryPercentage * 25 // Moderate penalty for cautionary weather
        }
        
        return SafetyScore(
            score: max(0, score),
            level: SafetyLevel.from(score: score),
            primaryFactors: combinePrimaryFactors(daylight: daylight, weather: weather)
        )
    }
    
    // MARK: - Recommendations
    
    var safetyRecommendations: [SafetyRecommendation] {
        var recommendations: [SafetyRecommendation] = []
        
        let daylight = daylightAnalysis
        let weather = weatherSafetyAnalysis
        
        // Darkness recommendations
        if daylight.totalDarkDistance > 0 {
            if daylight.totalDarkDistance / totalDistance() > 0.5 {
                recommendations.append(SafetyRecommendation(
                    type: .lighting,
                    priority: .critical,
                    title: "Major Darkness Concerns",
                    message: "Over 50% of your ride will be in darkness",
                    action: "Consider starting earlier or postponing until tomorrow",
                    icon: "moon.fill",
                    affectedDistance: daylight.totalDarkDistance
                ))
            } else {
                recommendations.append(SafetyRecommendation(
                    type: .lighting,
                    priority: .important,
                    title: "Lighting Required",
                    message: "Portions of your ride will be in low light conditions",
                    action: "Bring front/rear lights and reflective gear",
                    icon: "lightbulb.fill",
                    affectedDistance: daylight.totalDarkDistance
                ))
            }
        }
        
        // Weather recommendations
        for segment in weather.dangerousSegments {
            recommendations.append(SafetyRecommendation(
                type: .weather,
                priority: .critical,
                title: segment.condition.title,
                message: segment.condition.description,
                action: segment.condition.recommendation,
                icon: segment.condition.icon,
                affectedDistance: segment.distance
            ))
        }
        
        // Golden hour recommendations (positive)
        if daylight.goldenHourSegments.count > 0 {
            let goldenDistance = daylight.goldenHourSegments.reduce(0) { $0 + $1.distance }
            if goldenDistance / totalDistance() > 0.3 {
                recommendations.append(SafetyRecommendation(
                    type: .optimal,
                    priority: .positive,
                    title: "Perfect Lighting",
                    message: "You'll ride during golden hour with excellent visibility",
                    action: "Bring a camera for scenic shots!",
                    icon: "sun.and.horizon.fill",
                    affectedDistance: goldenDistance
                ))
            }
        }
        
        return recommendations.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    // MARK: - Private Helper Methods
    
    private func calculateSunrise() -> Date {
        // Use the Solar library to get the real sunrise time for the ride's location and date
        guard let solar = Solar(for: rideStartTime, coordinate: self.location) else {
            // Fallback for safety, but should not happen
            return rideStartTime
        }
        return solar.sunrise ?? rideStartTime
    }

    private func calculateSunset() -> Date {
        // Use the Solar library to get the real sunset time
        guard let solar = Solar(for: rideStartTime, coordinate: self.location) else {
            return rideStartTime
        }
        return solar.sunset ?? rideStartTime
    }
    
    private func estimatedEndTime() -> Date {
        let durationHours = totalDistance() / averageSpeed
        return rideStartTime.addingTimeInterval(durationHours * 3600)
    }
    
    private func totalDistance() -> Double {
        guard let lastPoint = weatherPoints.last else { return 0 }
        return units == .metric ? lastPoint.distance / 1000 : lastPoint.distance / 1609.34
    }
    
    private func calculateDarkSegments(sunrise: Date, sunset: Date, rideEnd: Date) -> [DaylightSegment] {
        var segments: [DaylightSegment] = []
        
        // Pre-sunrise darkness
        if rideStartTime < sunrise {
            let darkEnd = min(sunrise, rideEnd)
            let darkDuration = darkEnd.timeIntervalSince(rideStartTime) / 3600
            let darkDistance = darkDuration * averageSpeed
            
            segments.append(DaylightSegment(
                type: .darkness,
                startTime: rideStartTime,
                endTime: darkEnd,
                distance: darkDistance,
                description: "Pre-dawn darkness"
            ))
        }
        
        // Post-sunset darkness
        if rideEnd > sunset {
            let darkStart = max(sunset, rideStartTime)
            let darkDuration = rideEnd.timeIntervalSince(darkStart) / 3600
            let darkDistance = darkDuration * averageSpeed
            
            segments.append(DaylightSegment(
                type: .darkness,
                startTime: darkStart,
                endTime: rideEnd,
                distance: darkDistance,
                description: "Evening darkness"
            ))
        }
        
        return segments
    }
    
    private func calculateGoldenHourSegments(sunrise: Date, sunset: Date, rideEnd: Date) -> [DaylightSegment] {
        var segments: [DaylightSegment] = []
        
        let morningGoldenStart = sunrise.addingTimeInterval(-30 * 60) // 30 min before sunrise
        let morningGoldenEnd = sunrise.addingTimeInterval(60 * 60)    // 60 min after sunrise
        
        let eveningGoldenStart = sunset.addingTimeInterval(-60 * 60)  // 60 min before sunset
        let eveningGoldenEnd = sunset.addingTimeInterval(30 * 60)     // 30 min after sunset
        
        // Morning golden hour
        let morningStart = max(rideStartTime, morningGoldenStart)
        let morningEnd = min(rideEnd, morningGoldenEnd)
        if morningStart < morningEnd {
            let duration = morningEnd.timeIntervalSince(morningStart) / 3600
            segments.append(DaylightSegment(
                type: .goldenHour,
                startTime: morningStart,
                endTime: morningEnd,
                distance: duration * averageSpeed,
                description: "Morning golden hour"
            ))
        }
        
        // Evening golden hour
        let eveningStart = max(rideStartTime, eveningGoldenStart)
        let eveningEnd = min(rideEnd, eveningGoldenEnd)
        if eveningStart < eveningEnd && eveningStart >= morningEnd {
            let duration = eveningEnd.timeIntervalSince(eveningStart) / 3600
            segments.append(DaylightSegment(
                type: .goldenHour,
                startTime: eveningStart,
                endTime: eveningEnd,
                distance: duration * averageSpeed,
                description: "Evening golden hour"
            ))
        }
        
        return segments
    }
    
    private func calculateVisibilityRating(darkSegments: [DaylightSegment], goldenHour: [DaylightSegment]) -> VisibilityRating {
        let totalDist = totalDistance()
        guard totalDist > 0 else { return .excellent }
        
        let darkDist = darkSegments.reduce(0) { $0 + $1.distance }
        let goldenDist = goldenHour.reduce(0) { $0 + $1.distance }
        
        let darkPercentage = darkDist / totalDist
        let goldenPercentage = goldenDist / totalDist
        
        if darkPercentage > 0.5 { return .poor }
        if darkPercentage > 0.25 { return .fair }
        if goldenPercentage > 0.3 { return .excellent }
        return .good
    }
    
    private func identifyDangerousWeatherSegments() -> [WeatherSafetySegment] {
        // Implementation for identifying dangerous weather conditions
        // This would analyze windSpeed, temperature, humidity, etc.
        return []
    }
    
    private func identifyCautionaryWeatherSegments() -> [WeatherSafetySegment] {
        // Implementation for identifying cautionary weather conditions
        return []
    }
    
    private func identifyOptimalWeatherSegments() -> [WeatherSafetySegment] {
        // Implementation for identifying optimal weather conditions
        return []
    }
    
    private func calculateOverallSafetyRating(dangerous: [WeatherSafetySegment], cautionary: [WeatherSafetySegment]) -> WeatherSafetyRating {
        if !dangerous.isEmpty { return .dangerous }
        if cautionary.count > 2 { return .cautionary }
        return .safe
    }
    
    private func identifyPrimaryConcerns(dangerous: [WeatherSafetySegment], cautionary: [WeatherSafetySegment]) -> [WeatherConcern] {
        return []
    }
    
    private func combinePrimaryFactors(daylight: DaylightAnalysis, weather: WeatherSafetyAnalysis) -> [SafetyFactor] {
        var factors: [SafetyFactor] = []
        
        if daylight.totalDarkDistance > 0 {
            factors.append(.darkness)
        }
        
        if !weather.dangerousSegments.isEmpty {
            factors.append(.severeWeather)
        }
        
        return factors
    }
}

// MARK: - Data Models

struct DaylightAnalysis {
    let sunrise: Date
    let sunset: Date
    let rideStartTime: Date
    let rideEndTime: Date
    let darkSegments: [DaylightSegment]
    let goldenHourSegments: [DaylightSegment]
    let totalDarkDistance: Double
    let visibilityRating: VisibilityRating
}

struct DaylightSegment {
    let type: DaylightType
    let startTime: Date
    let endTime: Date
    let distance: Double
    let description: String
}

enum DaylightType {
    case darkness, goldenHour, daylight
    
    var color: Color {
        switch self {
        case .darkness: return .purple
        case .goldenHour: return .orange
        case .daylight: return .yellow
        }
    }
    
    var icon: String {
        switch self {
        case .darkness: return "moon.fill"
        case .goldenHour: return "sun.and.horizon.fill"
        case .daylight: return "sun.max.fill"
        }
    }
}

enum VisibilityRating {
    case poor, fair, good, excellent
    
    var color: Color {
        switch self {
        case .poor: return .red
        case .fair: return .orange
        case .good: return .green
        case .excellent: return .mint
        }
    }
    
    var label: String {
        switch self {
        case .poor: return "Poor Visibility"
        case .fair: return "Fair Visibility"
        case .good: return "Good Visibility"
        case .excellent: return "Excellent Visibility"
        }
    }
}

struct WeatherSafetyAnalysis {
    let dangerousSegments: [WeatherSafetySegment]
    let cautionarySegments: [WeatherSafetySegment]
    let optimalSegments: [WeatherSafetySegment]
    let overallSafetyRating: WeatherSafetyRating
    let primaryConcerns: [WeatherConcern]
}

struct WeatherSafetySegment {
    let startMile: Double
    let endMile: Double
    let distance: Double
    let condition: DangerousCondition
    let severity: ConditionSeverity
}

struct DangerousCondition {
    let type: WeatherHazard
    let title: String
    let description: String
    let recommendation: String
    let icon: String
}

enum WeatherHazard {
    case highWinds, extremeTemperature, heavyRain, lowVisibility, ice
}

enum ConditionSeverity {
    case moderate, high, extreme
}

enum WeatherSafetyRating {
    case safe, cautionary, dangerous
    
    var color: Color {
        switch self {
        case .safe: return .green
        case .cautionary: return .orange
        case .dangerous: return .red
        }
    }
}

enum WeatherConcern {
    case wind, temperature, precipitation, visibility
}

struct SafetyScore {
    let score: Double // 0-100
    let level: SafetyLevel
    let primaryFactors: [SafetyFactor]
}

enum SafetyLevel {
    case excellent, good, fair, poor, dangerous
    
    var color: Color {
        switch self {
        case .excellent: return .mint
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .orange
        case .dangerous: return .red
        }
    }
    
    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .dangerous: return "Dangerous"
        }
    }
    
    static func from(score: Double) -> SafetyLevel {
        switch score {
        case 85...100: return .excellent
        case 70..<85: return .good
        case 55..<70: return .fair
        case 30..<55: return .poor
        default: return .dangerous
        }
    }
}

enum SafetyFactor {
    case darkness, severeWeather, extremeTemperature, highWinds
}

struct SafetyRecommendation {
    let type: RecommendationType
    let priority: RecommendationPriority
    let title: String
    let message: String
    let action: String
    let icon: String
    let affectedDistance: Double
}

enum RecommendationType {
    case lighting, weather, timing, equipment, optimal
}

enum RecommendationPriority: Int, CaseIterable {
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
}

struct SafetyScoreRing: View {
    let score: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: score / 100)
                .stroke(SafetyLevel.from(score: score).color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: score)
            
            Text("\(Int(score))")
                .font(.caption.weight(.bold))
                .foregroundStyle(SafetyLevel.from(score: score).color)
        }
        .frame(width: 36, height: 36)
    }
}

struct SafetyInsightChip: View {
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
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SafetyAnalyticsDetailView: View {
    let engine: SafetyAnalyticsEngine
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Overall safety score
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(.quaternary, lineWidth: 8)
                            
                            Circle()
                                .trim(from: 0, to: engine.combinedSafetyScore.score / 100)
                                .stroke(engine.combinedSafetyScore.level.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            
                            VStack {
                                Text("\(Int(engine.combinedSafetyScore.score))")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(engine.combinedSafetyScore.level.color)
                                
                                Text("Safety Score")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 120, height: 120)
                        
                        Text(engine.combinedSafetyScore.level.label)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(engine.combinedSafetyScore.level.color)
                    }
                    
                    // Daylight analysis
                    DaylightAnalysisSection(analysis: engine.daylightAnalysis)
                    
                    // Weather safety
                    WeatherSafetySection(analysis: engine.weatherSafetyAnalysis)
                    
                    // Recommendations
                    RecommendationsSection(recommendations: engine.safetyRecommendations)
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .navigationTitle("Safety Analysis")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct DaylightAnalysisSection: View {
    let analysis: DaylightAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Daylight Analysis", systemImage: "sun.and.horizon.fill")
                    .font(.headline.weight(.bold))
                Spacer()
            }
            
            // Daylight timeline visualization could go here
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sunrise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(analysis.sunrise.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sunset")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(analysis.sunset.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(analysis.visibilityRating.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(analysis.visibilityRating.color)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WeatherSafetySection: View {
    let analysis: WeatherSafetyAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weather Safety", systemImage: "cloud.fill")
                    .font(.headline.weight(.bold))
                Spacer()
                
                Text(analysis.overallSafetyRating == .safe ? "Safe" : "Caution")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(analysis.overallSafetyRating.color.opacity(0.2), in: Capsule())
                    .foregroundStyle(analysis.overallSafetyRating.color)
            }
            
            // Weather conditions summary would go here
            Text("Weather conditions analysis based on wind speed, temperature, and precipitation risk.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct RecommendationsSection: View {
    let recommendations: [SafetyRecommendation]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Recommendations", systemImage: "lightbulb.fill")
                    .font(.headline.weight(.bold))
                Spacer()
            }
            
            if recommendations.isEmpty {
                Text("No specific safety concerns identified for your planned route!")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .padding()
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(recommendations.indices, id: \.self) { index in
                        SafetyRecommendationCard(recommendation: recommendations[index])
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SafetyRecommendationCard: View {
    let recommendation: SafetyRecommendation
    
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
                    
                    Spacer()
                    
                    Text(recommendation.priority == .critical ? "CRITICAL" : recommendation.priority == .important ? "IMPORTANT" : "INFO")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(recommendation.priority.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(recommendation.priority.color)
                }
                
                Text(recommendation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("💡 \(recommendation.action)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(recommendation.priority.color)
            }
        }
        .padding(12)
        .background(recommendation.priority.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(recommendation.priority.color.opacity(0.2), lineWidth: 1)
        )
    }
}
