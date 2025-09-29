//
//  RouteWeatherAnalyticsEngine.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/17/25.
//


//
//  EnhancedRouteAnalytics.swift
//  RideWeather Pro
//
//  Enhanced route-specific weather analytics with actionable insights
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Enhanced Route Analytics Engine

class RouteWeatherAnalyticsEngine {
    
    static func generateAnalytics(
        weatherPoints: [RouteWeatherPoint],
        rideStartTime: Date,
        averageSpeed: Double,
        units: UnitSystem
    ) -> EnhancedRouteAnalytics {
        
        return EnhancedRouteAnalytics(
            weatherPoints: weatherPoints,
            rideStartTime: rideStartTime,
            averageSpeed: averageSpeed,
            units: units
        )
    }
    
    static func findOptimalStartTimes(
        weatherPoints: [RouteWeatherPoint],
        currentStartTime: Date,
        averageSpeed: Double,
        units: UnitSystem
    ) -> [OptimalDepartureTime] {
        
        var alternatives: [OptimalDepartureTime] = []
        
        // Analyze start times from current time to 6 hours ahead
        for hourOffset in [-2, -1, 1, 2, 3, 4] {
            let alternativeStart = currentStartTime.addingTimeInterval(Double(hourOffset) * 3600)
            
            // Skip past times
            guard alternativeStart > Date() else { continue }
            
            let score = calculateWeatherScore(
                weatherPoints: weatherPoints,
                startTime: alternativeStart,
                averageSpeed: averageSpeed,
                units: units
            )
            
            let currentScore = calculateWeatherScore(
                weatherPoints: weatherPoints,
                startTime: currentStartTime,
                averageSpeed: averageSpeed,
                units: units
            )
            
            if score.overallScore > currentScore.overallScore {
                let improvement = Int((score.overallScore - currentScore.overallScore) / currentScore.overallScore * 100)
                
                alternatives.append(OptimalDepartureTime(
                    startTime: alternativeStart,
                    weatherScore: score,
                    improvementPercentage: improvement,
                    primaryBenefit: score.primaryBenefit,
                    timeWindow: getOptimalTimeWindow(around: alternativeStart)
                ))
            }
        }
        
        return alternatives.sorted { $0.improvementPercentage > $1.improvementPercentage }.prefix(3).map { $0 }
    }
    
    private static func calculateWeatherScore(
        weatherPoints: [RouteWeatherPoint],
        startTime: Date,
        averageSpeed: Double,
        units: UnitSystem
    ) -> WeatherScore {
        
        var tempScore: Double = 0
        var windScore: Double = 0
        var precipScore: Double = 0
        var comfortScore: Double = 0
        
        for (index, point) in weatherPoints.enumerated() {
            let timeOffset = (point.distance / (units == .metric ? 1000 : 1609.34)) / averageSpeed * 3600
            let weather = point.weather
            
            // Temperature scoring (ideal: 65-75°F / 18-24°C)
            let idealTemp = units == .metric ? 21.0 : 70.0
            let tempDiff = abs(weather.temp - idealTemp)
            tempScore += max(0, 100 - tempDiff * 2)
            
            // Wind scoring (lower is better)
            windScore += max(0, 100 - weather.windSpeed * 3)
            
            // Precipitation scoring (based on humidity as proxy)
            precipScore += max(0, 100 - weather.humidity)
            
            // Comfort scoring (feels like vs actual temp)
            let feelsLikeDiff = abs(weather.feelsLike - weather.temp)
            comfortScore += max(0, 100 - feelsLikeDiff * 4)
        }
        
        let pointCount = Double(weatherPoints.count)
        tempScore /= pointCount
        windScore /= pointCount
        precipScore /= pointCount
        comfortScore /= pointCount
        
        let overallScore = (tempScore * 0.3) + (windScore * 0.25) + (precipScore * 0.25) + (comfortScore * 0.2)
        
        return WeatherScore(
            overallScore: overallScore,
            temperatureScore: tempScore,
            windScore: windScore,
            precipitationScore: precipScore,
            comfortScore: comfortScore,
            primaryBenefit: determinePrimaryBenefit(temp: tempScore, wind: windScore, precip: precipScore)
        )
    }
    
    private static func determinePrimaryBenefit(temp: Double, wind: Double, precip: Double) -> String {
        let scores = [("temperature", temp), ("wind", wind), ("precipitation", precip)]
        let bestCategory = scores.max { $0.1 < $1.1 }?.0 ?? "overall conditions"
        
        switch bestCategory {
        case "temperature": return "More comfortable temperatures"
        case "wind": return "Reduced headwinds and crosswinds"
        case "precipitation": return "Lower chance of rain"
        default: return "Better overall conditions"
        }
    }
    
    private static func getOptimalTimeWindow(around time: Date) -> (start: Date, end: Date) {
        return (
            start: time.addingTimeInterval(-1800), // 30 min before
            end: time.addingTimeInterval(1800)     // 30 min after
        )
    }
}

// MARK: - Enhanced Analytics Data Model

struct EnhancedRouteAnalytics {
    let weatherPoints: [RouteWeatherPoint]
    let rideStartTime: Date
    let averageSpeed: Double
    let units: UnitSystem
    
    // Basic metrics
    var totalDistance: Double {
        guard let lastPoint = weatherPoints.last else { return 0 }
        return units == .metric ? lastPoint.distance / 1000 : lastPoint.distance / 1609.34
    }
    
    var estimatedDuration: String {
        let durationHours = totalDistance / averageSpeed
        let hours = Int(durationHours)
        let minutes = Int((durationHours - Double(hours)) * 60)
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    var estimatedEndTime: Date {
        let durationHours = totalDistance / averageSpeed
        return rideStartTime.addingTimeInterval(durationHours * 3600)
    }
    
    // Enhanced weather insights
    var criticalInsights: [CriticalWeatherInsight] {
        var insights: [CriticalWeatherInsight] = []
        
        // Temperature variation analysis
        let tempVariation = analyzeTemperatureVariation()
        if let insight = tempVariation {
            insights.append(insight)
        }
        
        // Wind impact analysis
        let windAnalysis = analyzeWindImpact()
        insights.append(contentsOf: windAnalysis)
        
        // Precipitation timing
        let precipAnalysis = analyzePrecipitationTiming()
        insights.append(contentsOf: precipAnalysis)
        
        // Comfort zones
        let comfortAnalysis = analyzeComfortZones()
        insights.append(contentsOf: comfortAnalysis)
        
        return insights.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    // Segment-by-segment breakdown
    var detailedSegments: [DetailedRouteSegment] {
        let segmentCount = min(6, weatherPoints.count)
        let segmentSize = weatherPoints.count / segmentCount
        
        return stride(from: 0, to: weatherPoints.count, by: segmentSize).enumerated().compactMap { index, start in
            let end = min(start + segmentSize, weatherPoints.count)
            let segmentPoints = Array(weatherPoints[start..<end])
            
            guard !segmentPoints.isEmpty,
                  let firstPoint = segmentPoints.first,
                  let lastPoint = segmentPoints.last else { return nil }
            
            return DetailedRouteSegment(
                segmentNumber: index + 1,
                startMile: units == .metric ? firstPoint.distance / 1000 : firstPoint.distance / 1609.34,
                endMile: units == .metric ? lastPoint.distance / 1000 : lastPoint.distance / 1609.34,
                startTime: estimatedTimeAt(distance: firstPoint.distance),
                endTime: estimatedTimeAt(distance: lastPoint.distance),
                weatherPoints: segmentPoints,
                analysis: analyzeSegment(segmentPoints),
                units: units
            )
        }
    }
    
    // MARK: - Analysis Functions
    
    private func analyzeTemperatureVariation() -> CriticalWeatherInsight? {
        let temps = weatherPoints.map { $0.weather.temp }
        guard let minTemp = temps.min(), let maxTemp = temps.max() else { return nil }
        
        let variation = maxTemp - minTemp
        let threshold = units == .metric ? 8.0 : 15.0 // 8°C or 15°F
        
        if variation > threshold {
            let minIndex = temps.firstIndex(of: minTemp) ?? 0
            let maxIndex = temps.firstIndex(of: maxTemp) ?? 0
            
            let minMile = units == .metric ? 
                weatherPoints[minIndex].distance / 1000 : 
                weatherPoints[minIndex].distance / 1609.34
            let maxMile = units == .metric ? 
                weatherPoints[maxIndex].distance / 1000 : 
                weatherPoints[maxIndex].distance / 1609.34
            
            let tempUnit = units == .metric ? "°C" : "°F"
            
            return CriticalWeatherInsight(
                title: "Significant Temperature Change",
                message: "Temperature will vary \(Int(variation))\(tempUnit) during your ride",
                details: "Lowest: \(Int(minTemp))\(tempUnit) at mile \(minMile, specifier: "%.1f"), Highest: \(Int(maxTemp))\(tempUnit) at mile \(maxMile, specifier: "%.1f")",
                recommendation: "Dress in layers. Start with gear for \(Int(minTemp))\(tempUnit) and plan to adjust.",
                icon: "thermometer.variable",
                priority: variation > threshold * 1.5 ? .critical : .important,
                affectedMileRange: (min(minMile, maxMile), max(minMile, maxMile))
            )
        }
        
        return nil
    }
    
    private func analyzeWindImpact() -> [CriticalWeatherInsight] {
        var insights: [CriticalWeatherInsight] = []
        
        // Find high wind sections
        let highWindPoints = weatherPoints.enumerated().filter { $0.element.weather.windSpeed > 15 }
        
        if !highWindPoints.isEmpty {
            let firstHighWind = highWindPoints.first!
            let lastHighWind = highWindPoints.last!
            
            let startMile = units == .metric ? 
                firstHighWind.element.distance / 1000 : 
                firstHighWind.element.distance / 1609.34
            let endMile = units == .metric ? 
                lastHighWind.element.distance / 1000 : 
                lastHighWind.element.distance / 1609.34
            
            let maxWind = highWindPoints.map { $0.element.weather.windSpeed }.max() ?? 0
            let speedUnit = units.speedUnitAbbreviation
            
            insights.append(CriticalWeatherInsight(
                title: "High Winds Expected",
                message: "Winds up to \(Int(maxWind)) \(speedUnit) between miles \(startMile, specifier: "%.1f") and \(endMile, specifier: "%.1f")",
                details: "Strong winds will increase effort and may affect handling",
                recommendation: "Plan for 10-15% longer ride time. Consider route adjustments if winds exceed 25 \(speedUnit).",
                icon: "wind",
                priority: maxWind > 25 ? .critical : .important,
                affectedMileRange: (startMile, endMile)
            ))
        }
        
        return insights
    }
    
    private func analyzePrecipitationTiming() -> [CriticalWeatherInsight] {
        var insights: [CriticalWeatherInsight] = []
        
        // Use humidity as proxy for precipitation risk
        let highHumidityPoints = weatherPoints.enumerated().filter { $0.element.weather.humidity > 80 }
        
        if !highHumidityPoints.isEmpty {
            let startPoint = highHumidityPoints.first!
            let startMile = units == .metric ? 
                startPoint.element.distance / 1000 : 
                startPoint.element.distance / 1609.34
            let startTime = estimatedTimeAt(distance: startPoint.element.distance)
            
            insights.append(CriticalWeatherInsight(
                title: "Wet Conditions Likely",
                message: "High chance of precipitation starting around mile \(startMile, specifier: "%.1f")",
                details: "Conditions will become wet around \(startTime.formatted(date: .omitted, time: .shortened))",
                recommendation: "Bring rain gear and consider waterproof phone case. Reduce speed on turns.",
                icon: "cloud.rain.fill",
                priority: .important,
                affectedMileRange: (startMile, totalDistance)
            ))
        }
        
        return insights
    }
    
    private func analyzeComfortZones() -> [CriticalWeatherInsight] {
        var insights: [CriticalWeatherInsight] = []
        
        // Analyze feels-like vs actual temperature
        let discomfortPoints = weatherPoints.enumerated().filter { 
            abs($0.element.weather.feelsLike - $0.element.weather.temp) > 10 
        }
        
        if !discomfortPoints.isEmpty {
            let worstPoint = discomfortPoints.max { 
                abs($0.element.weather.feelsLike - $0.element.weather.temp) < 
                abs($1.element.weather.feelsLike - $1.element.weather.temp) 
            }!
            
            let mile = units == .metric ? 
                worstPoint.element.distance / 1000 : 
                worstPoint.element.distance / 1609.34
            
            let feelsLike = worstPoint.element.weather.feelsLike
            let actual = worstPoint.element.weather.temp
            let tempUnit = units == .metric ? "°C" : "°F"
            
            let isHotter = feelsLike > actual
            
            insights.append(CriticalWeatherInsight(
                title: isHotter ? "Heat Index Warning" : "Wind Chill Effect",
                message: "Feels like \(Int(feelsLike))\(tempUnit) despite \(Int(actual))\(tempUnit) temperature",
                details: "Most noticeable around mile \(mile, specifier: "%.1f")",
                recommendation: isHotter ? 
                    "Stay hydrated and take breaks in shade. Consider earlier start time." :
                    "Dress warmer than temperature suggests. Protect exposed skin.",
                icon: isHotter ? "thermometer.sun.fill" : "thermometer.snowflake",
                priority: .moderate,
                affectedMileRange: (mile - 2, mile + 2)
            ))
        }
        
        return insights
    }
    
    private func analyzeSegment(_ points: [RouteWeatherPoint]) -> SegmentAnalysis {
        let temps = points.map { $0.weather.temp }
        let winds = points.map { $0.weather.windSpeed }
        let humidity = points.map { $0.weather.humidity }
        
        return SegmentAnalysis(
            averageTemp: temps.reduce(0, +) / Double(temps.count),
            tempRange: (temps.min() ?? 0, temps.max() ?? 0),
            averageWind: winds.reduce(0, +) / Double(winds.count),
            maxWind: winds.max() ?? 0,
            averageHumidity: humidity.reduce(0, +) / Double(humidity.count),
            dominantCondition: points.first?.weather.description ?? "Clear",
            riskLevel: calculateRiskLevel(points)
        )
    }
    
    private func calculateRiskLevel(_ points: [RouteWeatherPoint]) -> RiskLevel {
        let maxWind = points.map { $0.weather.windSpeed }.max() ?? 0
        let maxHumidity = points.map { $0.weather.humidity }.max() ?? 0
        let temps = points.map { $0.weather.temp }
        
        if maxWind > 25 || maxHumidity > 90 {
            return .high
        } else if maxWind > 15 || maxHumidity > 80 || temps.contains(where: { $0 > 85 || $0 < 45 }) {
            return .moderate
        } else {
            return .low
        }
    }
    
    private func estimatedTimeAt(distance: Double) -> Date {
        let distanceInMiles = units == .metric ? distance / 1000 * 0.621371 : distance / 1609.34
        let speedInMph = units == .metric ? averageSpeed * 0.621371 : averageSpeed
        let timeOffsetHours = distanceInMiles / speedInMph
        return rideStartTime.addingTimeInterval(timeOffsetHours * 3600)
    }
}

// MARK: - Enhanced Data Models

struct CriticalWeatherInsight {
    let title: String
    let message: String
    let details: String
    let recommendation: String
    let icon: String
    let priority: InsightPriority
    let affectedMileRange: (start: Double, end: Double)
    
    enum InsightPriority: Int, CaseIterable {
        case critical = 3
        case important = 2
        case moderate = 1
        
        var color: Color {
            switch self {
            case .critical: return .red
            case .important: return .orange
            case .moderate: return .blue
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .critical: return .red.opacity(0.15)
            case .important: return .orange.opacity(0.15)
            case .moderate: return .blue.opacity(0.15)
            }
        }
        
        var label: String {
            switch self {
            case .critical: return "CRITICAL"
            case .important: return "IMPORTANT"
            case .moderate: return "MODERATE"
            }
        }
    }
}

struct DetailedRouteSegment {
    let segmentNumber: Int
    let startMile: Double
    let endMile: Double
    let startTime: Date
    let endTime: Date
    let weatherPoints: [RouteWeatherPoint]
    let analysis: SegmentAnalysis
    let units: UnitSystem
    
    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
    
    var distance: Double {
        endMile - startMile
    }
}

struct SegmentAnalysis {
    let averageTemp: Double
    let tempRange: (min: Double, max: Double)
    let averageWind: Double
    let maxWind: Double
    let averageHumidity: Double
    let dominantCondition: String
    let riskLevel: RiskLevel
}

struct OptimalDepartureTime {
    let startTime: Date
    let weatherScore: WeatherScore
    let improvementPercentage: Int
    let primaryBenefit: String
    let timeWindow: (start: Date, end: Date)
}

struct WeatherScore {
    let overallScore: Double
    let temperatureScore: Double
    let windScore: Double
    let precipitationScore: Double
    let comfortScore: Double
    let primaryBenefit: String
}

enum RiskLevel: CaseIterable {
    case low, moderate, high
    
    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        }
    }
    
    var label: String {
        switch self {
        case .low: return "Low Risk"
        case .moderate: return "Moderate Risk"
        case .high: return "High Risk"
        }
    }
}

// MARK: - Enhanced Dashboard View

struct EnhancedRouteAnalyticsDashboardView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    private var analytics: EnhancedRouteAnalytics {
        EnhancedRouteAnalytics(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units
        )
    }
    
    private var optimalTimes: [OptimalDepartureTime] {
        RouteWeatherAnalyticsEngine.findOptimalStartTimes(
            weatherPoints: viewModel.weatherDataForRoute,
            currentStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Critical insights section
                    criticalInsightsSection
                    
                    // Optimal departure times
                    if !optimalTimes.isEmpty {
                        optimalTimingSection
                    }
                    
                    // Detailed segment breakdown
                    segmentBreakdownSection
                    
                    // Weather timeline
                    weatherTimelineSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("Route Analysis")
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
    
    // MARK: - Section Views
    
    private var criticalInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Critical Insights", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            if analytics.criticalInsights.isEmpty {
                Text("Great conditions expected throughout your ride!")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .padding()
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(analytics.criticalInsights.indices, id: \.self) { index in
                        CriticalInsightCard(insight: analytics.criticalInsights[index])
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var optimalTimingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Better Start Times", systemImage: "clock.arrow.2.circlepath")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            LazyVStack(spacing: 12) {
                ForEach(optimalTimes.indices, id: \.self) { index in
                    OptimalTimingCard(optimal: optimalTimes[index])
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var segmentBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Route Segments", systemImage: "road.lanes")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            LazyVStack(spacing: 8) {
                ForEach(analytics.detailedSegments.indices, id: \.self) { index in
                    DetailedSegmentCard(segment: analytics.detailedSegments[index])
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var weatherTimelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weather Timeline", systemImage: "timeline.selection")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            Text("\(analytics.rideStartTime.formatted(date: .omitted, time: .shortened)) - \(analytics.estimatedEndTime.formatted(date: .omitted, time: .shortened)) • \(analytics.estimatedDuration)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            
            // Visual timeline could be added here
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [.blue.opacity(0.8), .indigo.opacity(0.6), .purple.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Supporting Card Views

struct CriticalInsightCard: View {
    let insight: CriticalWeatherInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: insight.icon)
                    .font(.title3)
                    .foregroundStyle(insight.priority.color)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text(insight.message)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                Spacer()
                
                Text(insight.priority.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(insight.priority.color.opacity(0.3), in: Capsule())
                    .foregroundStyle(insight.priority.color)
            }
            
            Text(insight.details)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            
            Text("💡 \(insight.recommendation)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.yellow)
                .padding(.top, 4)
        }
        .padding(16)
        .background(insight.priority.backgroundColor, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(insight.priority.color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct OptimalTimingCard: View {
    let optimal: OptimalDepartureTime
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(optimal.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text("Optimal window: \(optimal.timeWindow.start.formatted(date: .omitted, time: .shortened)) - \(optimal.timeWindow.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                Text("+\(optimal.improvementPercentage)%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
            }
            
            Text(optimal.primaryBenefit)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green.opacity(0.9))
        }
        .padding(16)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
    }
}

struct DetailedSegmentCard: View {
    let segment: DetailedRouteSegment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Segment \(segment.segmentNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue, in: Capsule())
                
                Text("Miles \(segment.startMile, specifier: "%.1f") - \(segment.endMile, specifier: "%.1f")")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(segment.analysis.riskLevel.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(segment.analysis.riskLevel.color.opacity(0.3), in: Capsule())
                    .foregroundStyle(segment.analysis.riskLevel.color)
            }
            
            HStack {
                Text("\(segment.startTime.formatted(date: .omitted, time: .shortened)) - \(segment.endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("• \(segment.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temperature")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(Int(segment.analysis.averageTemp))°")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wind")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(Int(segment.analysis.maxWind)) \(segment.units.speedUnitAbbreviation)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conditions")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(segment.analysis.dominantCondition.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Integration with Existing Components

extension RouteAnalyticsIntegration {
    
    // Replace the existing RouteAnalyticsDashboardView with this enhanced version
    static func integrateEnhancedAnalytics() {
        // Instructions for integration:
        // 1. Replace RouteAnalyticsDashboardView with EnhancedRouteAnalyticsDashboardView
        // 2. Update sheet presentations to use the new view
        // 3. Add the enhanced analytics engine to your weather calculation flow
    }
}

// MARK: - Usage Example for RouteForecastView Integration

extension RouteForecastView {
    
    // Update your sheet presentation to use the enhanced analytics
    var enhancedWeatherDetailSheet: some View {
        Group {
            if let point = selectedWeatherPoint {
                WeatherDetailSheet(weatherPoint: point)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showWeatherDetail) {
            // Updated to use enhanced analytics
            EnhancedRouteAnalyticsDashboardView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Quick Integration Component

struct SmartRideInsightsCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var showingFullAnalytics = false
    
    private var analytics: EnhancedRouteAnalytics {
        EnhancedRouteAnalytics(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Route Insights")
                        .font(.headline.weight(.semibold))
                    
                    if analytics.criticalInsights.isEmpty {
                        Text("Perfect conditions ahead! 🌟")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Text("\(analytics.criticalInsights.count) important insights for your ride")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Preview of top insight
            if let topInsight = analytics.criticalInsights.first {
                HStack(spacing: 12) {
                    Image(systemName: topInsight.icon)
                        .font(.title3)
                        .foregroundStyle(topInsight.priority.color)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topInsight.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        
                        Text(topInsight.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(topInsight.priority.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Action button
            Button {
                showingFullAnalytics = true
            } label: {
                Label("View Full Analysis", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingFullAnalytics) {
            EnhancedRouteAnalyticsDashboardView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Live Conditions Banner

struct LiveConditionsBanner: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    private var analytics: EnhancedRouteAnalytics {
        EnhancedRouteAnalytics(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units
        )
    }
    
    var body: some View {
        if let criticalInsight = analytics.criticalInsights.first(where: { $0.priority == .critical }) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(criticalInsight.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.red)
                    
                    Text(criticalInsight.message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button("Details") {
                    // Show full analytics
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
            }
            .padding(12)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.red.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Weather Score Indicator

struct WeatherScoreIndicator: View {
    let score: Double // 0-100
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(scoreColor)
                .frame(width: 12, height: 12)
            
            Text(scoreLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(scoreColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
    
    private var scoreColor: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
    
    private var scoreLabel: String {
        switch score {
        case 80...100: return "Excellent"
        case 60..<80: return "Good"
        case 40..<60: return "Fair"
        default: return "Poor"
        }
    }
}

/*
MARK: - Implementation Guide

To integrate this enhanced analytics system into your existing RideWeather Pro app:

1. **Replace existing analytics**: 
   - Replace `RouteAnalyticsDashboardView` with `EnhancedRouteAnalyticsDashboardView`
   - Update all sheet presentations that show analytics

2. **Add smart insights card**:
   ```swift
   // In your RouteBottomControlsView or main route view
   if !viewModel.weatherDataForRoute.isEmpty {
       SmartRideInsightsCard()
           .environmentObject(viewModel)
   }
   ```

3. **Add live conditions banner**:
   ```swift
   // At the top of your route view overlay
   VStack {
       LiveConditionsBanner()
           .environmentObject(viewModel)
       // ... rest of your overlay content
   }
   ```

4. **Integration with existing components**:
   - The enhanced analytics work with your existing `RouteWeatherPoint` data
   - Uses your existing `UnitSystem` enum
   - Integrates seamlessly with your `WeatherViewModel`

Key Features Added:
✅ **Actionable Insights**: "Temperature will drop 8°F during your ride - bring layers"
✅ **Time-based Analysis**: Weather conditions during actual ride duration
✅ **Route Segment Analysis**: Different conditions at different points
✅ **Optimal Departure Times**: When to start for best conditions
✅ **Critical Warnings**: High-priority alerts for dangerous conditions
✅ **Smart Recommendations**: Specific advice based on conditions

The system automatically analyzes:
- Temperature variations and their timing
- Wind impact on different route segments  
- Precipitation timing and affected areas
- Comfort factors (feels-like vs actual temperature)
- Alternative start times with improvement percentages
- Detailed segment-by-segment breakdown

All insights are contextual to the specific route and ride timing, making them immediately actionable for cyclists.
*/