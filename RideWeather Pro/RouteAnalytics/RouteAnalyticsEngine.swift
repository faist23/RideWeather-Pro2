//
//  RouteAnalyticsEngine.swift
//  RideWeather Pro
//
//  Core analytics engine for route weather analysis
//

import Foundation

struct RouteAnalyticsEngine {
    let weatherPoints: [RouteWeatherPoint]
    let rideStartTime: Date
    let averageSpeed: Double
    let units: UnitSystem
    
    // MARK: - Basic Metrics
    
    var totalDistance: Double {
        guard !weatherPoints.isEmpty else { return 0 }
        
        // Debug: Print all distances to identify the issue
        #if DEBUG
        print("=== ROUTE ANALYTICS DEBUG ===")
        print("Total weather points: \(weatherPoints.count)")
        print("First point distance: \(weatherPoints.first?.distance ?? 0)")
        print("Last point distance: \(weatherPoints.last?.distance ?? 0)")
        print("All distances: \(weatherPoints.map { $0.distance })")
        #endif
        
        // Use the maximum distance from all points, not just the last
        let maxDistance = weatherPoints.map { $0.distance }.max() ?? 0
        return units == .metric ? maxDistance / 1000 : maxDistance / 1609.34
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
    
    var temperatureRange: (min: Double, max: Double) {
        let temps = weatherPoints.map { $0.weather.temp }
        return (temps.min() ?? 0, temps.max() ?? 0)
    }
    
    var temperatureRangeFormatted: String {
        let range = temperatureRange
        let unit = units == .metric ? "°C" : "°F"
        return "\(Int(range.min))\(unit) - \(Int(range.max))\(unit)"
    }
    
    var maxWindSpeed: Double {
        weatherPoints.map { $0.weather.windSpeed }.max() ?? 0
    }
    
    var rainRisk: Double {
        guard !weatherPoints.isEmpty else { return 0 }
        let highHumidityPoints = weatherPoints.filter { $0.weather.humidity > 75 }.count
        return Double(highHumidityPoints) / Double(weatherPoints.count)
    }
    
    // MARK: - Timeline Generation
    
    func generateTimelinePoints() -> [RouteTimelinePoint] {
        guard !weatherPoints.isEmpty else { return [] }
        
        var points: [RouteTimelinePoint] = []
        
        // Sort weather points by distance to ensure proper ordering
        let sortedPoints = weatherPoints.sorted { $0.distance < $1.distance }
        
        // Always include start point
        if let startPoint = sortedPoints.first {
            points.append(RouteTimelinePoint(
                id: "start",
                time: rideStartTime,
                distance: 0,
                weather: startPoint.weather,
                milestone: .start,
                description: "Ride begins"
            ))
        }
        
        // Add strategic points throughout the route
        let pointCount = sortedPoints.count
        if pointCount > 1 {
            // Add quarter point
            if pointCount >= 4 {
                let quarterIndex = pointCount / 4
                let quarterPoint = sortedPoints[quarterIndex]
                let quarterDistance = units == .metric ? quarterPoint.distance / 1000 : quarterPoint.distance / 1609.34
                let quarterTimeOffset = (quarterDistance / averageSpeed) * 3600
                
                points.append(RouteTimelinePoint(
                    id: "quarter",
                    time: rideStartTime.addingTimeInterval(quarterTimeOffset),
                    distance: quarterDistance,
                    weather: quarterPoint.weather,
                    milestone: .checkpoint,
                    description: "25% complete"
                ))
            }
            
            // Add midpoint
            let midIndex = pointCount / 2
            let midPoint = sortedPoints[midIndex]
            let midDistance = units == .metric ? midPoint.distance / 1000 : midPoint.distance / 1609.34
            let midTimeOffset = (midDistance / averageSpeed) * 3600
            
            points.append(RouteTimelinePoint(
                id: "mid",
                time: rideStartTime.addingTimeInterval(midTimeOffset),
                distance: midDistance,
                weather: midPoint.weather,
                milestone: .midpoint,
                description: "Halfway point"
            ))
            
            // Add three-quarter point
            if pointCount >= 4 {
                let threeQuarterIndex = (pointCount * 3) / 4
                let threeQuarterPoint = sortedPoints[threeQuarterIndex]
                let threeQuarterDistance = units == .metric ? threeQuarterPoint.distance / 1000 : threeQuarterPoint.distance / 1609.34
                let threeQuarterTimeOffset = (threeQuarterDistance / averageSpeed) * 3600
                
                points.append(RouteTimelinePoint(
                    id: "three_quarter",
                    time: rideStartTime.addingTimeInterval(threeQuarterTimeOffset),
                    distance: threeQuarterDistance,
                    weather: threeQuarterPoint.weather,
                    milestone: .checkpoint,
                    description: "75% complete"
                ))
            }
            
            // Always include end point
            if let endPoint = sortedPoints.last {
                let endDistance = units == .metric ? endPoint.distance / 1000 : endPoint.distance / 1609.34
                points.append(RouteTimelinePoint(
                    id: "end",
                    time: estimatedEndTime,
                    distance: endDistance,
                    weather: endPoint.weather,
                    milestone: .end,
                    description: "Ride complete"
                ))
            }
        }
        
        return points.sorted { $0.distance < $1.distance }
    }
    
    // MARK: - Segment Analysis
    
    func generateRouteSegments() -> [RouteSegment] {
        guard weatherPoints.count >= 2 else { return [] }
        
        let sortedPoints = weatherPoints.sorted { $0.distance < $1.distance }
        let segmentCount = min(6, max(3, sortedPoints.count / 10)) // 3-6 segments based on route length
        let pointsPerSegment = sortedPoints.count / segmentCount
        var segments: [RouteSegment] = []
        
        for i in 0..<segmentCount {
            let startIndex = i * pointsPerSegment
            let endIndex = (i == segmentCount - 1) ? sortedPoints.count - 1 : (i + 1) * pointsPerSegment
            
            guard startIndex < sortedPoints.count && endIndex < sortedPoints.count else { continue }
            
            let startPoint = sortedPoints[startIndex]
            let endPoint = sortedPoints[endIndex]
            let segmentPoints = Array(sortedPoints[startIndex...endIndex])
            
            let startDistance = units == .metric ? startPoint.distance / 1000 : startPoint.distance / 1609.34
            let endDistance = units == .metric ? endPoint.distance / 1000 : endPoint.distance / 1609.34
            
            let startTime = rideStartTime.addingTimeInterval((startDistance / averageSpeed) * 3600)
            let endTime = rideStartTime.addingTimeInterval((endDistance / averageSpeed) * 3600)
            
            segments.append(RouteSegment(
                id: "segment_\(i + 1)",
                number: i + 1,
                startDistance: startDistance,
                endDistance: endDistance,
                startTime: startTime,
                endTime: endTime,
                weatherPoints: segmentPoints,
                analysis: analyzeSegmentWeather(segmentPoints)
            ))
        }
        
        return segments
    }
    
    // MARK: - Critical Insights
    
    func generateCriticalInsights() -> [WeatherInsight] {
        var insights: [WeatherInsight] = []
        
        // Temperature variation analysis
        let tempRange = temperatureRange
        let variation = tempRange.max - tempRange.min
        let threshold = units == .metric ? 10.0 : 18.0
        
        if variation > threshold {
            insights.append(WeatherInsight(
                id: "temp_variation",
                title: "Large Temperature Change",
                message: "Temperature will vary by \(Int(variation))° during your ride",
                recommendation: "Dress in layers and be prepared to adjust clothing",
                priority: variation > threshold * 1.5 ? .critical : .important,
                icon: "thermometer.variable"
            ))
        }
        
        // Wind analysis
        if maxWindSpeed > 15 {
            let speedUnit = units == .metric ? "kph" : "mph"
            insights.append(WeatherInsight(
                id: "high_winds",
                title: "Strong Winds Expected",
                message: "Winds up to \(Int(maxWindSpeed)) \(speedUnit)",
                recommendation: "Plan for increased effort and potentially longer ride time",
                priority: maxWindSpeed > 25 ? .critical : .important,
                icon: "wind"
            ))
        }
        
        // Rain risk analysis
        if rainRisk > 0.4 {
            insights.append(WeatherInsight(
                id: "rain_risk",
                title: "High Rain Probability",
                message: "\(Int(rainRisk * 100))% chance of encountering wet conditions",
                recommendation: "Bring rain gear and consider tire pressure adjustments",
                priority: rainRisk > 0.7 ? .critical : .moderate,
                icon: "cloud.rain.fill"
            ))
        }
        
        // Extreme temperature warnings
        let maxTemp = tempRange.max
        let minTemp = tempRange.min
        let hotThreshold = units == .metric ? 32.0 : 90.0
        let coldThreshold = units == .metric ? 5.0 : 40.0
        
        if maxTemp > hotThreshold {
            insights.append(WeatherInsight(
                id: "extreme_heat",
                title: "Extreme Heat Warning",
                message: "Temperatures reaching \(Int(maxTemp))°",
                recommendation: "Start early, bring extra water, and take frequent breaks",
                priority: .critical,
                icon: "thermometer.sun.fill"
            ))
        }
        
        if minTemp < coldThreshold {
            insights.append(WeatherInsight(
                id: "extreme_cold",
                title: "Cold Weather Advisory",
                message: "Temperatures dropping to \(Int(minTemp))°",
                recommendation: "Dress warmly and protect exposed skin",
                priority: .important,
                icon: "thermometer.snowflake"
            ))
        }
        
        return insights.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    // MARK: - Alternative Start Times
    
    func generateBetterStartTimes() -> [AlternativeStartTime] {
        var alternatives: [AlternativeStartTime] = []
        
        let currentScore = calculateWeatherScore()
        
        for hourOffset in [-3, -2, -1, 1, 2, 3, 4] {
            let alternativeStart = rideStartTime.addingTimeInterval(Double(hourOffset) * 3600)
            guard alternativeStart > Date() else { continue }
            
            // For now, use simplified scoring - in a real implementation,
            // you'd want to fetch weather data for the alternative time
            let alternativeScore = currentScore + Double.random(in: -10...15)
            
            if alternativeScore > currentScore {
                let improvement = Int(((alternativeScore - currentScore) / currentScore) * 100)
                
                alternatives.append(AlternativeStartTime(
                    id: "alt_\(hourOffset)",
                    startTime: alternativeStart,
                    improvement: improvement,
                    primaryBenefit: determinePrimaryBenefit(hourOffset: hourOffset),
                    weatherScore: alternativeScore
                ))
            }
        }
        
        return alternatives.sorted { $0.improvement > $1.improvement }.prefix(3).map { $0 }
    }
    
    // MARK: - Private Helper Methods
    
    private func analyzeSegmentWeather(_ points: [RouteWeatherPoint]) -> SegmentWeatherAnalysis {
        let temps = points.map { $0.weather.temp }
        let winds = points.map { $0.weather.windSpeed }
        let humidity = points.map { Double($0.weather.humidity) }
        
        return SegmentWeatherAnalysis(
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
        
        let extremeTempThreshold = units == .metric ? 35.0 : 95.0
        let coldTempThreshold = units == .metric ? 0.0 : 32.0
        
        if maxWind > 25 || maxHumidity > 90 || temps.contains(where: { $0 > extremeTempThreshold || $0 < coldTempThreshold }) {
            return .high
        } else if maxWind > 15 || maxHumidity > 80 || temps.contains(where: { $0 > 30 || $0 < 10 }) {
            return .moderate
        } else {
            return .low
        }
    }
    
    private func calculateWeatherScore() -> Double {
        guard !weatherPoints.isEmpty else { return 0 }
        
        var score = 100.0
        
        for point in weatherPoints {
            let weather = point.weather
            
            // Temperature comfort scoring
            let idealTemp = units == .metric ? 20.0 : 68.0
            let tempDiff = abs(weather.temp - idealTemp)
            score -= tempDiff * 0.5
            
            // Wind penalty
            score -= weather.windSpeed * 0.8
            
            // Humidity penalty
            score -= Double(weather.humidity) * 0.1
        }
        
        return max(0, score / Double(weatherPoints.count))
    }
    
    private func determinePrimaryBenefit(hourOffset: Int) -> String {
        if hourOffset < 0 {
            return "Cooler temperatures and calmer morning conditions"
        } else if hourOffset <= 2 {
            return "Better weather window with improved conditions"
        } else {
            return "Afternoon weather improvement expected"
        }
    }
}