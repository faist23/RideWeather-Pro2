//
//  HourlyForecast+Analytics.swift
//  RideWeather Pro
//
//  Complete extensions for HourlyForecast with analytics, unit support, and enhanced comfort scoring
//

import SwiftUI

// MARK: - Temperature Conversion Extensions
extension HourlyForecast {
    /// Temperature in Fahrenheit - check if conversion is needed
    var tempF: Double {
        return temp
    }
    
    /// Feels like temperature in Fahrenheit
    var feelsLikeF: Double {
        return feelsLike
    }
    
    /// Temperature in Celsius - check if conversion is needed
    var tempC: Double {
        return temp
    }
    
    /// Feels like temperature in Celsius
    var feelsLikeC: Double {
        return feelsLike
    }
}

// MARK: - Unit-Aware Analytics Extensions
extension HourlyForecast {
    
    /// Enhanced cycling comfort calculation including ideal temp, UV Index and Air Quality
    func enhancedCyclingComfort(using units: UnitSystem, idealTemp: Double, uvIndex: Double?, aqi: Int?) -> Double {
        // Temperature score (40% weight) - NOW more granular
        let currentTemp = units == .metric ? tempC : tempF
        let tempDiff = abs(currentTemp - idealTemp)
        
        // Apply a penalty of 3 points for every degree of difference from the ideal
        let tempPenalty = tempDiff * 3.0
        let tempScore = max(0.0, (100.0 - tempPenalty) / 100.0)

        // Wind score (25% weight)
        var windScore: Double = 1.0
        let windLimits = units == .metric ?
            (comfortable: 16.0, moderate: 24.0, challenging: 32.0) :
            (comfortable: 10.0, moderate: 15.0, challenging: 20.0)
        
        let currentWindSpeed = units == .metric ? windSpeed * 1.60934 : windSpeed
        
        if currentWindSpeed <= windLimits.comfortable {
            windScore = 1.0
        } else if currentWindSpeed <= windLimits.moderate {
            windScore = 0.7
        } else if currentWindSpeed <= windLimits.challenging {
            windScore = 0.4
        } else {
            windScore = 0.2
        }
        
        // Precipitation score (15% weight)
        let rainScore = max(0.1, 1.0 - (pop * 1.2))
        
        // UV Index score (10% weight)
        var uvScore: Double = 1.0
        if let uv = uvIndex {
            switch uv {
            case 0...2: uvScore = 1.0
            case 3...5: uvScore = 0.9
            case 6...7: uvScore = 0.7
            case 8...10: uvScore = 0.5
            case 11...: uvScore = 0.3
            default: uvScore = 0.8
            }
        }
        
        // Air Quality score (10% weight)
        var aqScore: Double = 1.0
        if let airQuality = aqi {
            switch airQuality {
            case 1: aqScore = 1.0 // Good
            case 2: aqScore = 0.8 // Fair
            case 3: aqScore = 0.6 // Moderate
            case 4: aqScore = 0.4 // Poor
            case 5: aqScore = 0.2 // Very Poor
            default: aqScore = 0.7
            }
        }
        
        let weightedScore = (tempScore * 0.40) +
                           (windScore * 0.25) +
                           (rainScore * 0.15) +
                           (uvScore * 0.10) +
                           (aqScore * 0.10)
        
        return max(0.0, min(1.0, weightedScore))
    }
    
    /// Color representing cycling comfort level
    func comfortColor(using units: UnitSystem, idealTemp: Double) -> Color {
        let comfort = enhancedCyclingComfort(using: units, idealTemp: idealTemp, uvIndex: self.uvIndex, aqi: self.aqi)
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
    
    /// Formatted temperature string with unit
    func formattedTemp(using units: UnitSystem) -> String {
        let temperature = units == .metric ? tempC : tempF
        return "\(Int(temperature))\(units.tempSymbol)"
    }
    
    /// Formatted wind speed with unit
    func formattedWindSpeed(using units: UnitSystem) -> String {
        let speed = units == .metric ? windSpeed * 1.60934 : windSpeed
        return "\(Int(speed)) \(units.speedUnitAbbreviation)"
    }
    
    /// Formatted feels like temperature string with unit
    func formattedFeelsLike(using units: UnitSystem) -> String {
        let temperature = units == .metric ? feelsLikeC : feelsLikeF
        return "\(Int(temperature))\(units.tempSymbol)"
    }
}

// MARK: - Array Extensions with Unit Awareness
extension Array where Element == HourlyForecast {
    /// Average cycling comfort across all hours (unit-aware)
    func averageComfort(using units: UnitSystem, idealTemp: Double) -> Double {
        guard !isEmpty else { return 0 }
        return self.map { $0.enhancedCyclingComfort(using: units, idealTemp: idealTemp, uvIndex: $0.uvIndex, aqi: $0.aqi) }.reduce(0, +) / Double(count)
    }
    
    /// Hours with optimal cycling conditions (unit-aware, daylight only)
    func optimalHours(using units: UnitSystem, idealTemp: Double) -> [HourlyForecast] {
        return self.filter { $0.enhancedCyclingComfort(using: units, idealTemp: idealTemp, uvIndex: $0.uvIndex, aqi: $0.aqi) > 0.7 && $0.isDaylightHour }
    }
    
    /// Hours with challenging cycling conditions (unit-aware)
    func challengingHours(using units: UnitSystem, idealTemp: Double) -> [HourlyForecast] {
        return self.filter { $0.enhancedCyclingComfort(using: units, idealTemp: idealTemp, uvIndex: $0.uvIndex, aqi: $0.aqi) < 0.4 || !$0.isDaylightHour }
    }
    
    /// Best hour for cycling (unit-aware, daylight only)
    func bestCyclingHour(using units: UnitSystem, idealTemp: Double) -> HourlyForecast? {
        let daylightHours = self.filter { $0.isDaylightHour }
        return daylightHours.max {
            $0.enhancedCyclingComfort(using: units, idealTemp: idealTemp, uvIndex: $0.uvIndex, aqi: $0.aqi) < $1.enhancedCyclingComfort(using: units, idealTemp: idealTemp, uvIndex: $1.uvIndex, aqi: $1.aqi)
        }
    }
    
    var daylightHours: [HourlyForecast] {
        return self.filter { $0.isDaylightHour }
    }

    func temperatureRange(using units: UnitSystem) -> (min: Double, max: Double, formatted: String) {
        guard !isEmpty else { return (0, 0, "N/A") }
        
        let numericTemps = self.map { units == .metric ? $0.tempC : $0.tempF }
        
        let minTemp = numericTemps.min() ?? 0
        let maxTemp = numericTemps.max() ?? 0
        let formatted = "\(Int(minTemp))° - \(Int(maxTemp))\(units.tempSymbol)"
        return (minTemp, maxTemp, formatted)
    }
}

// MARK: - Cycling Analytics Helper
struct CyclingAnalyticsHelper {
    let hourlyData: [HourlyForecast]
    let units: UnitSystem
    let idealTemp: Double

    init(hourlyData: [HourlyForecast], units: UnitSystem, idealTemp: Double) {
        self.hourlyData = hourlyData
        self.units = units
        self.idealTemp = idealTemp
    }

    var averageComfort: Int {
        Int(hourlyData.averageComfort(using: units, idealTemp: idealTemp) * 100)
    }
    
    var bestHour: HourlyForecast? {
        hourlyData.bestCyclingHour(using: units, idealTemp: idealTemp)
    }
    
    var optimalHoursCount: Int {
        hourlyData.optimalHours(using: units, idealTemp: idealTemp).count
    }
    
    var challengingHoursCount: Int {
        hourlyData.challengingHours(using: units, idealTemp: idealTemp).count
    }
    
    var temperatureRangeFormatted: String {
        hourlyData.temperatureRange(using: units).formatted
    }
    
    var windRangeFormatted: String {
        guard !hourlyData.isEmpty else { return "N/A" }
        let speeds = hourlyData.map { units == .metric ? $0.windSpeed * 1.60934 : $0.windSpeed }
        let maxSpeed = speeds.max() ?? 0
        return "\(Int(maxSpeed)) \(units.speedUnitAbbreviation)"
    }

    var recommendations: [AnalyticsRecommendation] {
        var recs: [AnalyticsRecommendation] = []
        
        if let bestHour = bestHour {
            let comfort = Int(bestHour.enhancedCyclingComfort(using: units, idealTemp: idealTemp, uvIndex: bestHour.uvIndex, aqi: bestHour.aqi) * 100)
            recs.append(AnalyticsRecommendation(
                icon: "star.fill",
                title: "Optimal Window",
                description: "Best cycling from \(bestHour.time) with \(comfort)% comfort score. Temperature will be \(bestHour.formattedTemp(using: units)) with \(bestHour.formattedWindSpeed(using: units)) winds.",
                priority: .high,
                color: .green
            ))
        }
        
        return recs
    }
}

// MARK: - Supporting Types

struct AnalyticsRecommendation {
    let icon: String
    let title: String
    let description: String
    let priority: Priority
    let color: Color
    
    enum Priority {
        case low, medium, high
    }
}

extension HourlyForecast {
    var isDaylightHour: Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: self.date)
        return hour >= 7 && hour < 19
    }
}
