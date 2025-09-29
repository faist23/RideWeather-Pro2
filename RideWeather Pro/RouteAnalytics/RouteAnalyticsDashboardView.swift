//
//  RouteAnalyticsDashboardView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/17/25.
//


//
//  RouteAnalyticsDashboardView.swift
//  RideWeather Pro
//
//  Route-specific weather analytics that appear after a route is loaded
//

import SwiftUI
import MapKit

struct RouteAnalyticsDashboardView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    private var routeAnalytics: RouteWeatherAnalytics {
        RouteWeatherAnalytics(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with route summary
                    routeHeaderSection
                    
                    // Weather timeline during ride
                    rideTimelineSection
                    
                    // Key insights and recommendations
                    insightsSection
                    
                    // Detailed segment analysis
                    segmentAnalysisSection
                    
                    // Alternative timing suggestions
                    timingRecommendationsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("Route Weather Analysis")
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
    
    // MARK: - Route Header Section
    
    private var routeHeaderSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Route Analysis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Text("\(routeAnalytics.totalDistance, specifier: "%.1f") \(viewModel.settings.units == .metric ? "km" : "miles") • \(routeAnalytics.estimatedDuration)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Spacer()
            }
            
            // Quick stats
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                QuickStatCard(
                    icon: "clock.fill",
                    title: "Start Time",
                    value: routeAnalytics.rideStartTime.formatted(date: .omitted, time: .shortened),
                    color: .blue
                )
                
                QuickStatCard(
                    icon: "flag.checkered.fill", 
                    title: "Finish Time",
                    value: routeAnalytics.estimatedEndTime.formatted(date: .omitted, time: .shortened),
                    color: .green
                )
                
                QuickStatCard(
                    icon: "thermometer",
                    title: "Temp Range",
                    value: "\(Int(routeAnalytics.temperatureRange.min))° - \(Int(routeAnalytics.temperatureRange.max))°",
                    color: .orange
                )
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Ride Timeline Section
    
    private var rideTimelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weather During Your Ride", systemImage: "clock.arrow.circlepath")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            LazyVStack(spacing: 12) {
                ForEach(Array(routeAnalytics.timelineSegments.enumerated()), id: \.offset) { index, segment in
                    TimelineSegmentRow(segment: segment, isLast: index == routeAnalytics.timelineSegments.count - 1)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Insights Section
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Key Insights", systemImage: "lightbulb.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            LazyVStack(spacing: 12) {
                ForEach(routeAnalytics.keyInsights, id: \.title) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Segment Analysis Section
    
    private var segmentAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Route Segments", systemImage: "road.lanes")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            LazyVStack(spacing: 8) {
                ForEach(Array(routeAnalytics.routeSegments.enumerated()), id: \.offset) { index, segment in
                    RouteSegmentRow(segment: segment, segmentNumber: index + 1)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Timing Recommendations Section
    
    private var timingRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Alternative Start Times", systemImage: "clock.arrow.2.circlepath")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            if routeAnalytics.alternativeStartTimes.isEmpty {
                Text("Current timing looks optimal!")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(routeAnalytics.alternativeStartTimes, id: \.startTime) { alternative in
                        AlternativeTimingCard(alternative: alternative)
                    }
                }
            }
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

// MARK: - Supporting Views

struct QuickStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TimelineSegmentRow: View {
    let segment: RouteTimelineSegment
    let isLast: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(segment.weatherCondition.color)
                    .frame(width: 12, height: 12)
                
                if !isLast {
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 2, height: 40)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.time.formatted(date: .omitted, time: .shortened))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: segment.weatherIcon)
                            .font(.title3)
                            .symbolRenderingMode(.multicolor)
                        
                        Text("\(Int(segment.temperature))°")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                
                Text(segment.description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                
                if segment.distance > 0 {
                    Text("Mile \(segment.distance, specifier: "%.1f")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}

struct InsightCard: View {
    let insight: RouteWeatherInsight
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.icon)
                .font(.title3)
                .foregroundStyle(insight.priority.color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(insight.description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(16)
        .background(insight.priority.backgroundColor, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RouteSegmentRow: View {
    let segment: RouteSegmentAnalysis
    let segmentNumber: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Segment number
            Text("\(segmentNumber)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.blue, in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Miles \(segment.startMile, specifier: "%.1f") - \(segment.endMile, specifier: "%.1f")")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Text("\(Int(segment.averageTemp))°")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                
                Text(segment.conditions)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                
                if !segment.recommendations.isEmpty {
                    Text(segment.recommendations)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AlternativeTimingCard: View {
    let alternative: AlternativeStartTime
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(alternative.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(alternative.improvementScore)% better")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.3), in: Capsule())
                    .foregroundStyle(.green)
            }
            
            Text(alternative.reason)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            
            HStack(spacing: 16) {
                Label("\(Int(alternative.tempRange.min))° - \(Int(alternative.tempRange.max))°", systemImage: "thermometer")
                
                Label("\(Int(alternative.maxWindSpeed)) mph", systemImage: "wind")
                
                Label("\(Int(alternative.rainChance * 100))%", systemImage: "cloud.rain")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Data Models

struct RouteWeatherAnalytics {
    let weatherPoints: [RouteWeatherPoint]
    let rideStartTime: Date
    let averageSpeed: Double // mph or kph
    let units: UnitSystem
    
    var totalDistance: Double {
        guard let lastPoint = weatherPoints.last else { return 0 }
        return units == .metric ? lastPoint.distance / 1000 : lastPoint.distance / 1609.34
    }
    
    var estimatedDuration: String {
        let durationHours = totalDistance / averageSpeed
        let hours = Int(durationHours)
        let minutes = Int((durationHours - Double(hours)) * 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var estimatedEndTime: Date {
        let durationHours = totalDistance / averageSpeed
        return rideStartTime.addingTimeInterval(durationHours * 3600)
    }
    
    var temperatureRange: (min: Double, max: Double) {
        let temps = weatherPoints.map { $0.weather.temp }
        return (temps.min() ?? 0, temps.max() ?? 0)
    }
    
    var timelineSegments: [RouteTimelineSegment] {
        let segments = stride(from: 0, through: weatherPoints.count - 1, by: max(1, weatherPoints.count / 6))
        return segments.compactMap { index in
            guard index < weatherPoints.count else { return nil }
            let point = weatherPoints[index]
            let timeOffset = (point.distance / 1609.34) / averageSpeed * 3600 // seconds
            let segmentTime = rideStartTime.addingTimeInterval(timeOffset)
            
            return RouteTimelineSegment(
                time: segmentTime,
                distance: units == .metric ? point.distance / 1000 : point.distance / 1609.34,
                temperature: point.weather.temp,
                weatherIcon: point.weather.iconName,
                description: point.weather.description.capitalized,
                weatherCondition: determineWeatherCondition(for: point.weather)
            )
        }
    }
    
    var keyInsights: [RouteWeatherInsight] {
        var insights: [RouteWeatherInsight] = []
        
        // Temperature insights
        let tempRange = temperatureRange
        if tempRange.max - tempRange.min > 15 {
            insights.append(RouteWeatherInsight(
                icon: "thermometer.variable",
                title: "Temperature Variation",
                description: "Temperature will change \(Int(tempRange.max - tempRange.min))°F during your ride. Consider layered clothing.",
                priority: .medium
            ))
        }
        
        // Wind insights
        let maxWind = weatherPoints.map { $0.weather.windSpeed }.max() ?? 0
        if maxWind > 15 {
            insights.append(RouteWeatherInsight(
                icon: "wind",
                title: "High Winds Expected",
                description: "Winds up to \(Int(maxWind)) mph. Plan for longer ride time and increased effort.",
                priority: .high
            ))
        }
        
        // Rain insights
        let rainPoints = weatherPoints.filter { $0.weather.humidity > 80 }
        if !rainPoints.isEmpty {
            insights.append(RouteWeatherInsight(
                icon: "cloud.rain",
                title: "Wet Conditions Possible",
                description: "High humidity expected around mile \(Int(rainPoints.first?.distance ?? 0 / 1609.34)). Bring rain gear.",
                priority: .medium
            ))
        }
        
        return insights
    }
    
    var routeSegments: [RouteSegmentAnalysis] {
        let segmentSize = weatherPoints.count / 4
        guard segmentSize > 0 else { return [] }
        
        return stride(from: 0, to: weatherPoints.count, by: segmentSize).enumerated().compactMap { index, start in
            let end = min(start + segmentSize, weatherPoints.count)
            let segmentPoints = Array(weatherPoints[start..<end])
            
            guard !segmentPoints.isEmpty,
                  let firstPoint = segmentPoints.first,
                  let lastPoint = segmentPoints.last else { return nil }
            
            let avgTemp = segmentPoints.map { $0.weather.temp }.reduce(0, +) / Double(segmentPoints.count)
            let avgWind = segmentPoints.map { $0.weather.windSpeed }.reduce(0, +) / Double(segmentPoints.count)
            
            return RouteSegmentAnalysis(
                startMile: units == .metric ? firstPoint.distance / 1000 : firstPoint.distance / 1609.34,
                endMile: units == .metric ? lastPoint.distance / 1000 : lastPoint.distance / 1609.34,
                averageTemp: avgTemp,
                conditions: "\(Int(avgWind)) mph winds, \(segmentPoints.first?.weather.description.capitalized ?? "Clear")",
                recommendations: avgWind > 20 ? "Consider alternate route or timing" : ""
            )
        }
    }
    
    var alternativeStartTimes: [AlternativeStartTime] {
        // For demo purposes - in real app, you'd analyze different start times
        var alternatives: [AlternativeStartTime] = []
        
        // 1 hour earlier
        let earlierStart = rideStartTime.addingTimeInterval(-3600)
        if earlierStart > Date() {
            alternatives.append(AlternativeStartTime(
                startTime: earlierStart,
                tempRange: (temperatureRange.min - 5, temperatureRange.max - 5),
                maxWindSpeed: weatherPoints.map { $0.weather.windSpeed }.max() ?? 0 - 3,
                rainChance: 0.1,
                improvementScore: 15,
                reason: "Cooler temperatures and lighter winds"
            ))
        }
        
        return alternatives
    }
    
    private func determineWeatherCondition(for weather: DisplayWeatherModel) -> WeatherConditionType {
        if weather.windSpeed > 20 {
            return .windy
        } else if weather.temp > 85 {
            return .hot
        } else if weather.temp < 50 {
            return .cold
        } else {
            return .pleasant
        }
    }
}

// MARK: - Supporting Data Types

struct RouteTimelineSegment {
    let time: Date
    let distance: Double
    let temperature: Double
    let weatherIcon: String
    let description: String
    let weatherCondition: WeatherConditionType
}

struct RouteWeatherInsight {
    let icon: String
    let title: String
    let description: String
    let priority: InsightPriority
}

struct RouteSegmentAnalysis {
    let startMile: Double
    let endMile: Double
    let averageTemp: Double
    let conditions: String
    let recommendations: String
}

struct AlternativeStartTime {
    let startTime: Date
    let tempRange: (min: Double, max: Double)
    let maxWindSpeed: Double
    let rainChance: Double
    let improvementScore: Int
    let reason: String
}

enum WeatherConditionType {
    case pleasant, hot, cold, windy, rainy
    
    var color: Color {
        switch self {
        case .pleasant: return .green
        case .hot: return .red
        case .cold: return .blue
        case .windy: return .cyan
        case .rainy: return .indigo
        }
    }
}

enum InsightPriority {
    case low, medium, high
    
    var color: Color {
        switch self {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .low: return .blue.opacity(0.1)
        case .medium: return .orange.opacity(0.1)  
        case .high: return .red.opacity(0.1)
        }
    }
}