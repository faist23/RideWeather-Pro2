//
//  CyclingAnalytics.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//


//
//  HourlyForecast+Analytics.swift
//  RideWeather Pro
//
//  Analytics extensions for existing HourlyForecast model
//

import SwiftUI

// MARK: - Analytics Extensions for HourlyForecast

extension HourlyForecast {
    /// Cycling comfort score based on temperature, wind, and precipitation
    var cyclingComfort: Double {
        // Convert temperature to Fahrenheit for calculation if needed
        let tempF = temp // Assuming temp is already in user's preferred unit
        
        // Temperature comfort score (optimal range: 60-75°F / 15-24°C)
        var tempScore: Double = 1.0
        let optimalTempRange: ClosedRange<Double> = settingsBasedOptimalTemp()
        
        if optimalTempRange.contains(tempF) {
            tempScore = 1.0
        } else if tempF < optimalTempRange.lowerBound {
            // Cold penalty
            let coldDiff = optimalTempRange.lowerBound - tempF
            tempScore = max(0.2, 1.0 - (coldDiff / 20))
        } else {
            // Hot penalty
            let hotDiff = tempF - optimalTempRange.upperBound
            tempScore = max(0.2, 1.0 - (hotDiff / 25))
        }
        
        // Wind comfort score (optimal: < 10 mph/16 kmh)
        var windScore: Double = 1.0
        let windLimit = windSpeedLimit()
        
        if windSpeed <= windLimit.comfortable {
            windScore = 1.0
        } else if windSpeed <= windLimit.moderate {
            windScore = 0.7
        } else if windSpeed <= windLimit.challenging {
            windScore = 0.4
        } else {
            windScore = 0.2
        }
        
        // Precipitation comfort score
        let rainScore = max(0.1, 1.0 - (pop * 1.2))
        
        // Weighted average (temperature is most important for cycling comfort)
        let weightedScore = (tempScore * 0.5) + (windScore * 0.3) + (rainScore * 0.2)
        
        return max(0.0, min(1.0, weightedScore))
    }
    
    /// Color representing cycling comfort level
    var comfortColor: Color {
        let comfort = cyclingComfort
        if comfort > 0.8 {
            return .green
        } else if comfort > 0.6 {
            return .yellow
        } else if comfort > 0.4 {
            return .orange
        } else {
            return .red
        }
    }
    
    /// Wind direction as compass string
    var windDirection: String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", 
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((Double(windDeg) + 11.25) / 22.5) % 16
        return directions[index]
    }
    
    /// Temperature in Fahrenheit (computed)
    var tempF: Double {
        // Assuming your existing temp is in Celsius, convert to F
        // If your temp is already in user's preferred unit, adjust this logic
        return temp * 9/5 + 32
    }
    
    /// Feels like temperature in Fahrenheit
    var feelsLikeF: Double {
        return feelsLike * 9/5 + 32
    }
    
    // MARK: - Private Helper Methods
    
    private func settingsBasedOptimalTemp() -> ClosedRange<Double> {
        // This would ideally check user settings, but for now assume Fahrenheit
        // If using Celsius, return 15.0...24.0
        return 60.0...75.0
    }
    
    private func windSpeedLimit() -> (comfortable: Double, moderate: Double, challenging: Double) {
        // Assuming wind speed is in mph. If using km/h, adjust accordingly
        return (comfortable: 10.0, moderate: 15.0, challenging: 20.0)
    }
}

// MARK: - Array Extensions for Analytics

extension Array where Element == HourlyForecast {
    /// Average cycling comfort across all hours
    var averageComfort: Double {
        guard !isEmpty else { return 0 }
        return self.map { $0.cyclingComfort }.reduce(0, +) / Double(count)
    }
    
    /// Hours with optimal cycling conditions (comfort > 70%)
    var optimalHours: [HourlyForecast] {
        return self.filter { $0.cyclingComfort > 0.7 }
    }
    
    /// Hours with challenging cycling conditions (comfort < 40%)
    var challengingHours: [HourlyForecast] {
        return self.filter { $0.cyclingComfort < 0.4 }
    }
    
    /// Temperature range across all hours
    var temperatureRange: (min: Double, max: Double) {
        guard !isEmpty else { return (0, 0) }
        let temps = self.map { $0.tempF }
        return (temps.min()!, temps.max()!)
    }
    
    /// Wind speed range across all hours
    var windSpeedRange: (min: Double, max: Double) {
        guard !isEmpty else { return (0, 0) }
        let speeds = self.map { $0.windSpeed }
        return (speeds.min()!, speeds.max()!)
    }
    
    /// Maximum precipitation probability
    var maxPrecipitationChance: Double {
        guard !isEmpty else { return 0 }
        return self.map { $0.pop }.max() ?? 0
    }
    
    /// Best hour for cycling (highest comfort score)
    var bestCyclingHour: HourlyForecast? {
        return self.max { $0.cyclingComfort < $1.cyclingComfort }
    }
    
    /// Hours grouped by comfort level
    var comfortLevelDistribution: (excellent: Int, good: Int, fair: Int, poor: Int) {
        let excellent = self.filter { $0.cyclingComfort > 0.8 }.count
        let good = self.filter { $0.cyclingComfort > 0.6 && $0.cyclingComfort <= 0.8 }.count
        let fair = self.filter { $0.cyclingComfort > 0.4 && $0.cyclingComfort <= 0.6 }.count
        let poor = self.filter { $0.cyclingComfort <= 0.4 }.count
        
        return (excellent: excellent, good: good, fair: fair, poor: poor)
    }
}

// MARK: - Analytics Data Structures

struct CyclingAnalytics {
    let hourlyData: [HourlyForecast]
    
    var summary: AnalyticsSummary {
        AnalyticsSummary(
            averageComfort: Int(hourlyData.averageComfort * 100),
            bestHour: hourlyData.bestCyclingHour,
            temperatureRange: hourlyData.temperatureRange,
            windRange: hourlyData.windSpeedRange,
            maxPrecipitation: hourlyData.maxPrecipitationChance,
            optimalHoursCount: hourlyData.optimalHours.count,
            challengingHoursCount: hourlyData.challengingHours.count
        )
    }
    
    var recommendations: [AnalyticsRecommendation] {
        var recs: [AnalyticsRecommendation] = []
        
        // Optimal timing recommendation
        if let bestHour = hourlyData.bestCyclingHour {
            let comfort = Int(bestHour.cyclingComfort * 100)
            recs.append(AnalyticsRecommendation(
                icon: "star.fill",
                title: "Optimal Window",
                description: "Best cycling from \(bestHour.time) with \(comfort)% comfort score. Temperature will be \(Int(bestHour.tempF))°F with \(Int(bestHour.windSpeed))mph winds.",
                priority: .high,
                color: .green
            ))
        }
        
        // Wind recommendation
        let windRange = hourlyData.windSpeedRange
        if windRange.max > 15 {
            recs.append(AnalyticsRecommendation(
                icon: "wind",
                title: "Wind Alert",
                description: "High winds expected (up to \(Int(windRange.max))mph). Choose sheltered routes or plan shorter rides.",
                priority: .medium,
                color: .orange
            ))
        }
        
        // Temperature recommendation
        let tempRange = hourlyData.temperatureRange
        if tempRange.min < 50 || tempRange.max > 85 {
            recs.append(AnalyticsRecommendation(
                icon: "thermometer",
                title: "Temperature Alert",
                description: "Temperature extremes expected (\(Int(tempRange.min))°-\(Int(tempRange.max))°F). Layer appropriately and bring extra fluids.",
                priority: .medium,
                color: .blue
            ))
        }
        
        // Precipitation recommendation
        if hourlyData.maxPrecipitationChance > 0.5 {
            recs.append(AnalyticsRecommendation(
                icon: "cloud.rain.fill",
                title: "Rain Alert",
                description: "High chance of precipitation (\(Int(hourlyData.maxPrecipitationChance * 100))%). Consider indoor alternatives or waterproof gear.",
                priority: .high,
                color: .blue
            ))
        }
        
        return recs
    }
}

struct AnalyticsSummary {
    let averageComfort: Int
    let bestHour: HourlyForecast?
    let temperatureRange: (min: Double, max: Double)
    let windRange: (min: Double, max: Double)
    let maxPrecipitation: Double
    let optimalHoursCount: Int
    let challengingHoursCount: Int
}

struct AnalyticsRecommendation {
    let icon: String
    let title: String
    let description: String
    let priority: Priority
    let color: Color
    
    enum Priority {
        case high, medium, low
    }
}