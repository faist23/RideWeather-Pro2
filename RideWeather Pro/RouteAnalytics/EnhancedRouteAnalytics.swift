//
//  EnhancedRouteAnalytics.swift
//  RideWeather Pro
//
//  Enhanced route-specific weather analytics with actionable insights
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Enhanced Analytics Data Model

struct EnhancedRouteInsights {
    let weatherPoints: [RouteWeatherPoint]
    let rideStartTime: Date
    let averageSpeed: Double
    let units: UnitSystem
    
    var totalDistance: Double {
        guard let lastPoint = weatherPoints.last else { return 0 }
        return units == .metric ? lastPoint.distance / 1000 : lastPoint.distance / 1609.34
    }
    
    var estimatedDuration: String {
        guard averageSpeed > 0 else { return "0m" }
        let durationHours = totalDistance / averageSpeed
        let hours = Int(durationHours)
        let minutes = Int((durationHours - Double(hours)) * 60)
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    var estimatedEndTime: Date {
        guard averageSpeed > 0 else { return rideStartTime }
        let durationHours = totalDistance / averageSpeed
        return rideStartTime.addingTimeInterval(durationHours * 3600)
    }
    
    var criticalInsights: [CriticalRideInsight] {
        var insights: [CriticalRideInsight] = []
        
        if let tempVariation = analyzeTemperatureVariation() { insights.append(tempVariation) }
        insights.append(contentsOf: analyzeWindImpact())
        insights.append(contentsOf: analyzePrecipitationTiming())
        insights.append(contentsOf: analyzeComfortZones())
        
        return insights.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    var detailedSegments: [EnhancedRouteSegment] {
        // This logic is now simpler. It creates one segment for each pair
        // of the pre-sampled weather points we fetched.
        
        let sortedPoints = weatherPoints.sorted { $0.distance < $1.distance }
        guard sortedPoints.count >= 2 else { return [] }

        var segments: [EnhancedRouteSegment] = []

        // Loop from the first point up to the second-to-last point.
        // This creates N-1 segments from N points.
        for i in 0..<(sortedPoints.count - 1) {
            let startPoint = sortedPoints[i]
            let endPoint = sortedPoints[i+1]

            segments.append(
                EnhancedRouteSegment(
                    segmentNumber: i + 1,
                    startMile: units == .metric ? startPoint.distance / 1000 : startPoint.distance / 1609.34,
                    endMile: units == .metric ? endPoint.distance / 1000 : endPoint.distance / 1609.34,
                    startTime: estimatedTimeAt(distance: startPoint.distance),
                    endTime: estimatedTimeAt(distance: endPoint.distance),
                    weatherPoints: [startPoint, endPoint],
                    analysis: analyzeSegment([startPoint, endPoint]),
                    units: units
                )
            )
        }
        
        return segments
    }

    // MARK: - Analysis Functions
    
    private func analyzeTemperatureVariation() -> CriticalRideInsight? {
        let temps = weatherPoints.map { $0.weather.temp }
        guard let minTemp = temps.min(), let maxTemp = temps.max() else { return nil }
        
        let variation = maxTemp - minTemp
        let threshold = units == .metric ? 8.0 : 15.0
        
        if variation > threshold {
            let minIndex = temps.firstIndex(of: minTemp) ?? 0
            let maxIndex = temps.firstIndex(of: maxTemp) ?? 0
            
            let minMile = units == .metric ? weatherPoints[minIndex].distance / 1000 : weatherPoints[minIndex].distance / 1609.34
            let maxMile = units == .metric ? weatherPoints[maxIndex].distance / 1000 : weatherPoints[maxIndex].distance / 1609.34
            
            let tempUnit = units.tempSymbol
            
            return CriticalRideInsight(
                title: "Significant Temperature Change",
                message: "Temperature will vary by \(Int(variation))\(tempUnit) during your ride",
                details: String(format: "Lowest: %d%@ at mile %.1f, Highest: %d%@ at mile %.1f", Int(minTemp), tempUnit, minMile, Int(maxTemp), tempUnit, maxMile),
                recommendation: "Dress in layers. Start with gear for \(Int(minTemp))\(tempUnit) and plan to adjust.",
                icon: "thermometer.variable",
                priority: variation > threshold * 1.5 ? .critical : .important,
                affectedMileRange: (min(minMile, maxMile), max(minMile, maxMile))
            )
        }
        return nil
    }
    
    private func analyzeWindImpact() -> [CriticalRideInsight] {
        var insights: [CriticalRideInsight] = []
        
        let highWindPoints = weatherPoints.filter { $0.weather.windSpeed > 15 }
        
        if let firstHighWind = highWindPoints.first, let lastHighWind = highWindPoints.last {
            let startMile = units == .metric ? firstHighWind.distance / 1000 : firstHighWind.distance / 1609.34
            let endMile = units == .metric ? lastHighWind.distance / 1000 : lastHighWind.distance / 1609.34
            
            let maxWind = highWindPoints.map { $0.weather.windSpeed }.max() ?? 0
            let speedUnit = units.speedUnitAbbreviation
            
            insights.append(CriticalRideInsight(
                title: "High Winds Expected",
                message: String(format: "Winds up to %d %@ between miles %.1f and %.1f", Int(maxWind), speedUnit, startMile, endMile),
                details: "Strong winds will increase effort and may affect handling",
                recommendation: "Plan for 10-15% longer ride time. Consider route adjustments if winds exceed 25 \(speedUnit).",
                icon: "wind",
                priority: maxWind > 25 ? .critical : .important,
                affectedMileRange: (startMile, endMile)
            ))
        }
        return insights
    }
    
    private func analyzePrecipitationTiming() -> [CriticalRideInsight] {
        // Find the first point where the chance of rain is significant (e.g., >= 40%)
        if let firstRainPoint = weatherPoints.first(where: { $0.weather.pop >= 0.4 }) {
            // Find the maximum chance of rain for the whole ride to make the message more useful
            let maxPop = weatherPoints.map { $0.weather.pop }.max() ?? 0
            
            let startMile = units == .metric ? firstRainPoint.distance / 1000 : firstRainPoint.distance / 1609.34
            let startTime = estimatedTimeAt(distance: firstRainPoint.distance)
            
            return [CriticalRideInsight(
                title: "Chance of Rain",
                message: String(format: "Up to %.0f%% chance of rain, starting around mile %.1f.", maxPop * 100, startMile),
                details: "Wet conditions are possible from \(startTime.formatted(date: .omitted, time: .shortened)).",
                recommendation: "Pack rain gear and protect electronics. Reduce speed in wet conditions.",
                icon: "cloud.rain.fill",
                priority: maxPop >= 0.7 ? .critical : .important, // Higher priority for higher chance
                affectedMileRange: (startMile, totalDistance)
            )]
        }
        return []
    }
    private func analyzeComfortZones() -> [CriticalRideInsight] {
        let discomfortPoints = weatherPoints.filter { abs($0.weather.feelsLike - $0.weather.temp) > 10 }
        
        if let worstPoint = discomfortPoints.max(by: { abs($0.weather.feelsLike - $0.weather.temp) < abs($1.weather.feelsLike - $1.weather.temp) }) {
            let mile = units == .metric ? worstPoint.distance / 1000 : worstPoint.distance / 1609.34
            
            let feelsLike = worstPoint.weather.feelsLike
            let actual = worstPoint.weather.temp
            let tempUnit = units.tempSymbol
            let isHotter = feelsLike > actual
            
            return [CriticalRideInsight(
                title: isHotter ? "Heat Index Warning" : "Wind Chill Effect",
                message: "Feels like \(Int(feelsLike))\(tempUnit) despite \(Int(actual))\(tempUnit) temperature",
                details: String(format: "Most noticeable around mile %.1f", mile),
                recommendation: isHotter ? "Stay hydrated and take breaks in shade. Consider an earlier start time." : "Dress warmer than the temperature suggests. Protect exposed skin.",
                icon: isHotter ? "thermometer.sun.fill" : "thermometer.snowflake",
                priority: .moderate,
                affectedMileRange: (mile > 2 ? mile - 2 : 0, mile + 2)
            )]
        }
        return []
    }
    
    private func analyzeSegment(_ points: [RouteWeatherPoint]) -> EnhancedSegmentAnalysis {
        let temps = points.map { $0.weather.temp }
        let winds = points.map { $0.weather.windSpeed }
        let humidity = points.map { $0.weather.humidity }
        let pops = points.map { $0.weather.pop } // Get pop values

        return EnhancedSegmentAnalysis(
            averageTemp: temps.reduce(0, +) / Double(temps.count),
            tempRange: (temps.min() ?? 0, temps.max() ?? 0),
            averageWind: winds.reduce(0, +) / Double(winds.count),
            maxWind: winds.max() ?? 0,
            averageWindDirection: points.first?.weather.windDeg ?? 0,
            averageHumidity: humidity.reduce(0.0) { $0 + Double($1) } / Double(humidity.count),
            maxPop: pops.max() ?? 0, // Calculate and add max pop
            dominantCondition: points.first?.weather.description ?? "Clear",
            riskLevel: calculateRiskLevel(points)
        )
    }
    
    private func calculateRiskLevel(_ points: [RouteWeatherPoint]) -> WeatherRiskLevel {
        let maxWind = points.map { $0.weather.windSpeed }.max() ?? 0
        let maxHumidity = points.map { $0.weather.humidity }.max() ?? 0
        let temps = points.map { $0.weather.temp }
        
        if maxWind > 25 || maxHumidity > 90 { return .high }
        if maxWind > 15 || maxHumidity > 80 || temps.contains(where: { $0 > 85 || $0 < 45 }) { return .moderate }
        return .low
    }
    
    private func estimatedTimeAt(distance: Double) -> Date {
        guard averageSpeed > 0 else { return rideStartTime }
        let distanceInStandardUnit = units == .metric ? distance / 1000 : distance / 1609.34
        let timeOffsetHours = distanceInStandardUnit / averageSpeed
        return rideStartTime.addingTimeInterval(timeOffsetHours * 3600)
    }
}

// MARK: - Enhanced Data Models

struct CriticalRideInsight {
    let title: String
    let message: String
    let details: String
    let recommendation: String
    let icon: String
    let priority: InsightPriorityLevel
    let affectedMileRange: (start: Double, end: Double)
    
    enum InsightPriorityLevel: Int, CaseIterable {
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

struct EnhancedRouteSegment {
    let segmentNumber: Int
    let startMile: Double
    let endMile: Double
    let startTime: Date
    let endTime: Date
    let weatherPoints: [RouteWeatherPoint]
    let analysis: EnhancedSegmentAnalysis
    let units: UnitSystem
    
    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
    
    var distance: Double {
        endMile - startMile
    }
}

struct EnhancedSegmentAnalysis {
    let averageTemp: Double
    let tempRange: (min: Double, max: Double)
    let averageWind: Double
    let maxWind: Double
    let averageWindDirection: Int
    let averageHumidity: Double
    let maxPop: Double 
    let dominantCondition: String
    let riskLevel: WeatherRiskLevel
}

enum WeatherRiskLevel: CaseIterable {
    case low, moderate, high
    
/*    var color: Color {
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
    }*/
}

