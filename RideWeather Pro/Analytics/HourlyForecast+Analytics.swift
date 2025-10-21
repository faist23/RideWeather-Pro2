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
        if temp >= 30 && temp <= 120 { return temp }
        return (temp * 9/5) + 32
    }
    
    /// Feels like temperature in Fahrenheit
    var feelsLikeF: Double {
        if feelsLike >= 30 && feelsLike <= 120 { return feelsLike }
        return (feelsLike * 9/5) + 32
    }
    
    /// Temperature in Celsius - check if conversion is needed
    var tempC: Double {
        if temp >= 30 && temp <= 120 { return (temp - 32) * 5/9 }
        return temp
    }
    
    /// Feels like temperature in Celsius
    var feelsLikeC: Double {
        if feelsLike >= 30 && feelsLike <= 120 { return (feelsLike - 32) * 5/9 }
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
/*//----------------------------------------------------------------------
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
        // If temp is already reasonable in F range (30-120), don't convert
        if temp >= 30 && temp <= 120 {
            return temp
        }
        // Otherwise assume it's Celsius and convert
        return (temp * 9/5) + 32
    }
    
    /// Feels like temperature in Fahrenheit
    var feelsLikeF: Double {
        // If feelsLike is already reasonable in F range, don't convert
        if feelsLike >= 30 && feelsLike <= 120 {
            return feelsLike
        }
        // Otherwise assume it's Celsius and convert
        return (feelsLike * 9/5) + 32
    }
    
    /// Temperature in Celsius - check if conversion is needed
    var tempC: Double {
        // If temp is in F range (30-120), convert to Celsius
        if temp >= 30 && temp <= 120 {
            return (temp - 32) * 5/9
        }
        // Otherwise assume it's already Celsius
        return temp
    }
    
    /// Feels like temperature in Celsius
    var feelsLikeC: Double {
        // If feelsLike is in F range, convert to Celsius
        if feelsLike >= 30 && feelsLike <= 120 {
            return (feelsLike - 32) * 5/9
        }
        // Otherwise assume it's already Celsius
        return feelsLike
    }
}

// MARK: - Unit-Aware Analytics Extensions
extension HourlyForecast {
    // Original cycling comfort score (for backward compatibility)
    func cyclingComfort(using units: UnitSystem) -> Double {
        // Temperature comfort score
        var tempScore: Double = 1.0
        let optimalTempRange = units == .metric ? 15.0...24.0 : 60.0...75.0 // Celsius : Fahrenheit
        
        let currentTemp = units == .metric ? temp : tempF
        
        if optimalTempRange.contains(currentTemp) {
            tempScore = 1.0
        } else if currentTemp < optimalTempRange.lowerBound {
            // Cold penalty
            let coldDiff = optimalTempRange.lowerBound - currentTemp
            let penalty = units == .metric ? coldDiff / 15 : coldDiff / 20
            tempScore = max(0.2, 1.0 - penalty)
        } else {
            // Hot penalty
            let hotDiff = currentTemp - optimalTempRange.upperBound
            let penalty = units == .metric ? hotDiff / 20 : hotDiff / 25
            tempScore = max(0.2, 1.0 - penalty)
        }
        
        // Wind comfort score (mph vs kph)
        var windScore: Double = 1.0
        let windLimits = units == .metric ?
            (comfortable: 16.0, moderate: 24.0, challenging: 32.0) : // kph
            (comfortable: 10.0, moderate: 15.0, challenging: 20.0)   // mph
        
        let currentWindSpeed = units == .metric ? windSpeed * 1.60934 : windSpeed // Convert if needed
        
        if currentWindSpeed <= windLimits.comfortable {
            windScore = 1.0
        } else if currentWindSpeed <= windLimits.moderate {
            windScore = 0.7
        } else if currentWindSpeed <= windLimits.challenging {
            windScore = 0.4
        } else {
            windScore = 0.2
        }
        print("cyclingComfort called")
        // Precipitation comfort score
        let rainScore = max(0.1, 1.0 - (pop * 1.2))
        
        // Weighted average
        let weightedScore = (tempScore * 0.5) + (windScore * 0.3) + (rainScore * 0.2)
        
        return max(0.0, min(1.0, weightedScore))
    }
    
    // Enhanced cycling comfort calculation including UV Index and Air Quality
//    func enhancedCyclingComfort(using units: UnitSystem, uvIndex: Double? = nil, aqi: Int? = nil) -> Double {
    func enhancedCyclingComfort(using units: UnitSystem, idealTemp: Double, uvIndex: Double?, aqi: Int?) -> Double {
    // Original temperature score (40% weight - reduced from 50%)
/*        var tempScore: Double = 1.0
        let optimalTempRange = units == .metric ? 15.0...24.0 : 60.0...75.0
        let currentTemp = units == .metric ? temp : tempF
        
        if optimalTempRange.contains(currentTemp) {
            tempScore = 1.0
        } else if currentTemp < optimalTempRange.lowerBound {
            let coldDiff = optimalTempRange.lowerBound - currentTemp
            let penalty = units == .metric ? coldDiff / 15 : coldDiff / 20
            tempScore = max(0.2, 1.0 - penalty)
        } else {
            let hotDiff = currentTemp - optimalTempRange.upperBound
            let penalty = units == .metric ? hotDiff / 20 : hotDiff / 25
            tempScore = max(0.2, 1.0 - penalty)
        }*/
        // Temperature score (40% weight) - NOW more granular
        let currentTemp = units == .metric ? temp : tempF
        let tempDiff = abs(currentTemp - idealTemp)

        // Apply a penalty of 3 points for every degree of difference from the ideal
        let tempPenalty = tempDiff * 3.0
        let tempScore = max(0.0, (100.0 - tempPenalty) / 100.0)
        
        // Wind score (25% weight - reduced from 30%)
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
        
        // Precipitation score (15% weight - reduced from 20%)
        let rainScore = max(0.1, 1.0 - (pop * 1.2))
        
        // UV Index score (10% weight - NEW)
        var uvScore: Double = 1.0
        if let uv = uvIndex {
            switch uv {
            case 0...2:      // Low
                uvScore = 1.0
            case 3...5:      // Moderate
                uvScore = 0.9
            case 6...7:      // High
                uvScore = 0.7
            case 8...10:     // Very High
                uvScore = 0.5
            case 11...:      // Extreme
                uvScore = 0.3
            default:
                uvScore = 0.8 // Default for negative values
            }
        }
        
        // Air Quality score (10% weight - NEW)
        var aqScore: Double = 1.0
        if let airQuality = aqi {
            switch airQuality {
            case 0...50:     // Good
                aqScore = 1.0
            case 51...100:   // Moderate
                aqScore = 0.8
            case 101...150:  // Unhealthy for Sensitive Groups
                aqScore = 0.6
            case 151...200:  // Unhealthy
                aqScore = 0.4
            case 201...300:  // Very Unhealthy
                aqScore = 0.2
            case 301...:     // Hazardous
                aqScore = 0.1
            default:
                aqScore = 0.7 // Default for negative values
            }
        }
        
        // New weighted calculation with all 5 factors
        let weightedScore = (tempScore * 0.40) +
                           (windScore * 0.25) +
                           (rainScore * 0.15) +
                           (uvScore * 0.10) +
                           (aqScore * 0.10)
        
        return max(0.0, min(1.0, weightedScore))
    }
    
/*    // Color representing cycling comfort level
    func comfortColor(using units: UnitSystem) -> Color {
        let comfort = cyclingComfort(using: units)
        if comfort > 0.8 {
            return .green
        } else if comfort > 0.6 {
            return .yellow
        } else if comfort > 0.4 {
            return .orange
        } else {
            return .red
        }
    }*/
    // Color representing the ENHANCED cycling comfort level
    func comfortColor(using units: UnitSystem) -> Color {
        // Use the enhanced comfort score for color coding
        let comfort = enhancedCyclingComfort(using: units, idealTemp: viewModel.settings.idealTemperature, uvIndex: self.uvIndex, aqi: self.aqi)
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

    
    // Formatted temperature string with unit
    func formattedTemp(using units: UnitSystem) -> String {
        let temperature = units == .metric ? temp : tempF
        return "\(Int(temperature))\(units.tempSymbol)"
    }
    
    /// Formatted wind speed with unit
    func formattedWindSpeed(using units: UnitSystem) -> String {
        let speed = units == .metric ? windSpeed * 1.60934 : windSpeed // Convert mph to kph if needed
        return "\(Int(speed)) \(units.speedUnitAbbreviation)"
    }
    
    /// Formatted feels like temperature string with unit
    func formattedFeelsLike(using units: UnitSystem) -> String {
        let temperature = units == .metric ? feelsLikeC : feelsLikeF
        return "\(Int(temperature))\(units.tempSymbol)"
    }
    
    /// Enhanced wind direction with degrees
    var windDirectionDetailed: String {
        return "\(windDirection) (\(windDeg)°)"
    }
}

// MARK: - Backward Compatibility Extensions
extension HourlyForecast {
    // Basic cycling comfort score (without units parameter for backward compatibility)
    var basicCyclingComfort: Double {
        // Temperature comfort score (using Fahrenheit)
        var tempScore: Double = 1.0
        let tempFahr = tempF
        
        if tempFahr < 50 || tempFahr > 80 {
            tempScore = 0.3
        } else if tempFahr < 60 || tempFahr > 75 {
            tempScore = 0.7
        }
        
        // Wind comfort score
        var windScore: Double = 1.0
        if windSpeed > 15 {
            windScore = 0.3
        } else if windSpeed > 10 {
            windScore = 0.7
        }
        
        // Rain score
        let rainScore = 1.0 - pop
        
        return (tempScore + windScore + rainScore) / 3.0
    }
    
    // Comfort color (without units parameter for backward compatibility)
    var basicComfortColor: Color {
        let comfort = basicCyclingComfort
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
    
    // Weather condition assessment
    var weatherCondition: CyclingWeatherCondition {
        if pop > 0.7 {
            return .stormy
        } else if pop > 0.3 {
            return .rainy
        } else if windSpeed > 20 {
            return .windy
        } else if tempF > 85 {
            return .hot
        } else if tempF < 45 {
            return .cold
        } else {
            return .pleasant
        }
    }
    
    // Is this hour suitable for cycling (daylight hours)
    var isDaylightHour: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        guard let hourTime = formatter.date(from: time) else { return false }
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: hourTime)
        
        // Consider 7 AM to 7 PM as daylight cycling hours
        return hour >= 7 && hour < 19
    }
    
    // Is this hour optimal for cycling? (includes daylight check)
    var isOptimal: Bool {
        return isDaylightHour && basicCyclingComfort > 0.7
    }
    
    // Is this hour challenging for cycling?
    var isChallenging: Bool {
        return basicCyclingComfort < 0.4 || !isDaylightHour
    }
}

// MARK: - Cycling Weather Condition Enum
enum CyclingWeatherCondition: String, CaseIterable {
    case pleasant = "Pleasant"
    case hot = "Hot"
    case cold = "Cold"
    case windy = "Windy"
    case rainy = "Rainy"
    case stormy = "Stormy"
    
    var icon: String {
        switch self {
        case .pleasant: return "sun.max.fill"
        case .hot: return "thermometer.sun.fill"
        case .cold: return "thermometer.snowflake"
        case .windy: return "wind"
        case .rainy: return "cloud.rain.fill"
        case .stormy: return "cloud.bolt.rain.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pleasant: return .green
        case .hot: return .red
        case .cold: return .blue
        case .windy: return .cyan
        case .rainy: return .indigo
        case .stormy: return .purple
        }
    }
}

// MARK: - Array Extensions with Unit Awareness
extension Array where Element == HourlyForecast {
 /*   // Average cycling comfort across all hours (unit-aware)
    func averageComfort(using units: UnitSystem) -> Double {
        guard !isEmpty else { return 0 }
        return self.map { $0.cyclingComfort(using: units) }.reduce(0, +) / Double(count)
    }*/
    // Average cycling comfort across all hours (unit-aware) using the ENHANCED score
     func averageComfort(using units: UnitSystem) -> Double {
         guard !isEmpty else { return 0 }
         // Map using the enhanced function, passing UV and AQI from each element
         return self.map { $0.enhancedCyclingComfort(using: units, idealTemp: viewModel.settings.idealTemperature, uvIndex: $0.uvIndex, aqi: $0.aqi) }.reduce(0, +) / Double(count)
     }

    
/*    // Hours with optimal cycling conditions (unit-aware, daylight only)
    func optimalHours(using units: UnitSystem) -> [HourlyForecast] {
        return self.filter { $0.cyclingComfort(using: units) > 0.7 && $0.isDaylightHour }
    }*/
    // Hours with optimal cycling conditions (unit-aware, daylight only) using the ENHANCED score
    func optimalHours(using units: UnitSystem) -> [HourlyForecast] {
        // Filter using the enhanced function
        return self.filter { $0.enhancedCyclingComfort(using: units, uvIndex: $0.uvIndex, aqi: $0.aqi) > 0.7 && $0.isDaylightHour }
    }

    
/*    // Hours with challenging cycling conditions (unit-aware)
    func challengingHours(using units: UnitSystem) -> [HourlyForecast] {
        return self.filter { $0.cyclingComfort(using: units) < 0.4 || !$0.isDaylightHour }
    }*/
    // Hours with challenging cycling conditions (unit-aware) using the ENHANCED score
     func challengingHours(using units: UnitSystem) -> [HourlyForecast] {
         // Filter using the enhanced function
         return self.filter { $0.enhancedCyclingComfort(using: units, uvIndex: $0.uvIndex, aqi: $0.aqi) < 0.4 || !$0.isDaylightHour }
     }

    
/*    // Best hour for cycling (unit-aware, daylight only)
    func bestCyclingHour(using units: UnitSystem) -> HourlyForecast? {
        let daylightHours = self.filter { $0.isDaylightHour }
        return daylightHours.max { $0.cyclingComfort(using: units) < $1.cyclingComfort(using: units) }
    }*/
    // Best hour for cycling (unit-aware, daylight only) using the ENHANCED score
    func bestCyclingHour(using units: UnitSystem) -> HourlyForecast? {
        let daylightHours = self.filter { $0.isDaylightHour }
        // Find the max value using the enhanced function
        return daylightHours.max {
            $0.enhancedCyclingComfort(using: units, uvIndex: $0.uvIndex, aqi: $0.aqi) < $1.enhancedCyclingComfort(using: units, uvIndex: $1.uvIndex, aqi: $1.aqi)
        }
    }

    
    // Get only daylight hours (7 AM - 7 PM)
    var daylightHours: [HourlyForecast] {
        return self.filter { $0.isDaylightHour }
    }
    
    // Get next 12 hours of daylight cycling opportunities
    func next12DaylightHours() -> [HourlyForecast] {
        return self.filter { $0.isDaylightHour }.prefix(12).map { $0 }
    }
    
    // Temperature range with proper formatting (unit-aware)
    func temperatureRange(using units: UnitSystem) -> (min: Double, max: Double, formatted: String) {
        guard !isEmpty else { return (0, 0, "N/A") }
        
        let temps = units == .metric ?
            self.map { $0.temp } :
            self.map { $0.tempF }
        
        let minTemp = temps.min()!
        let maxTemp = temps.max()!
        let formatted = "\(Int(minTemp))° - \(Int(maxTemp))\(units.tempSymbol)"
        return (minTemp, maxTemp, formatted)
    }
    
    // Wind speed range with proper formatting (unit-aware)
    func windSpeedRange(using units: UnitSystem) -> (min: Double, max: Double, formatted: String) {
        guard !isEmpty else { return (0, 0, "N/A") }
        
        let speeds = units == .metric ?
            self.map { $0.windSpeed * 1.60934 } : // Convert to kph
            self.map { $0.windSpeed }
        
        let minWind = speeds.min()!
        let maxWind = speeds.max()!
        let formatted = "\(Int(minWind))-\(Int(maxWind)) \(units.speedUnitAbbreviation)"
        return (minWind, maxWind, formatted)
    }
    
    // Precipitation summary
    var precipitationSummary: (maxChance: Double, hoursWithRain: Int, totalHours: Int) {
        let maxChance = self.map { $0.pop }.max() ?? 0
        let hoursWithRain = self.filter { $0.pop > 0.1 }.count
        return (maxChance, hoursWithRain, self.count)
    }
    
    // Wind direction analysis
    var windAnalysis: WindAnalysis {
        guard !isEmpty else {
            return WindAnalysis(averageSpeed: 0, primaryDirection: "N", directionConsistency: 0)
        }
        
        let averageSpeed = self.map { $0.windSpeed }.reduce(0, +) / Double(count)
        
        // Simple primary direction calculation
        let directions = self.map { $0.windDirection }
        let directionCounts = Dictionary(grouping: directions) { $0 }.mapValues { $0.count }
        let primaryDirection = directionCounts.max { $0.value < $1.value }?.key ?? "N"
        
        // Consistency: how often the wind comes from the primary direction
        let consistency = Double(directionCounts[primaryDirection] ?? 0) / Double(count)
        
        return WindAnalysis(
            averageSpeed: averageSpeed,
            primaryDirection: primaryDirection,
            directionConsistency: consistency
        )
    }
}

// MARK: - Backward Compatibility Array Extensions
extension Array where Element == HourlyForecast {
    /// Average comfort score (fallback for older code)
    var averageBasicComfort: Double {
        guard !isEmpty else { return 0 }
        return self.map { $0.basicCyclingComfort }.reduce(0, +) / Double(count)
    }
    
    /// Optimal hours (fallback for older code, daylight only)
    var basicOptimalHours: [HourlyForecast] {
        return self.filter { $0.basicCyclingComfort > 0.7 && $0.isDaylightHour }
    }
    
    /// Temperature range (fallback for older code)
    var basicTemperatureRange: (min: Double, max: Double) {
        guard !isEmpty else { return (0, 0) }
        let temps = self.map { $0.tempF }
        return (temps.min()!, temps.max()!)
    }
    
    /// Wind speed range (fallback for older code)
    var basicWindSpeedRange: (min: Double, max: Double) {
        guard !isEmpty else { return (0, 0) }
        let speeds = self.map { $0.windSpeed }
        return (speeds.min()!, speeds.max()!)
    }
}

// MARK: - Wind Analysis Helper
struct WindAnalysis {
    let averageSpeed: Double
    let primaryDirection: String
    let directionConsistency: Double // 0.0 to 1.0
    
    var consistencyDescription: String {
        if directionConsistency > 0.7 {
            return "Very consistent"
        } else if directionConsistency > 0.5 {
            return "Moderately consistent"
        } else {
            return "Variable"
        }
    }
    
    var speedDescription: String {
        if averageSpeed < 5 {
            return "Light"
        } else if averageSpeed < 15 {
            return "Moderate"
        } else if averageSpeed < 25 {
            return "Strong"
        } else {
            return "Very strong"
        }
    }
}

// MARK: - Analytics Recommendation
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

// MARK: - Unit-Aware Analytics Helper (Original)
struct CyclingAnalyticsHelper {
    let hourlyData: [HourlyForecast]
    let units: UnitSystem
    
    var averageComfort: Int {
        Int(hourlyData.averageComfort(using: units) * 100)
    }
    
    var bestHour: HourlyForecast? {
        hourlyData.bestCyclingHour(using: units)
    }
    
    var optimalHoursCount: Int {
        hourlyData.optimalHours(using: units).count
    }
    
    var challengingHoursCount: Int {
        hourlyData.challengingHours(using: units).count
    }
    
    var temperatureRangeFormatted: String {
        hourlyData.temperatureRange(using: units).formatted
    }
    
    var windRangeFormatted: String {
        hourlyData.windSpeedRange(using: units).formatted
    }
    
    var windAnalysis: WindAnalysis {
        hourlyData.windAnalysis
    }
    
    var precipitationSummary: (maxChance: Double, hoursWithRain: Int, totalHours: Int) {
        hourlyData.precipitationSummary
    }
    
    var recommendations: [AnalyticsRecommendation] {
        var recs: [AnalyticsRecommendation] = []
        
        // Optimal timing recommendation
        if let bestHour = bestHour {
            let comfort = Int(bestHour.enhancedCyclingComfort(using: units) * 100)
            recs.append(AnalyticsRecommendation(
                icon: "star.fill",
                title: "Optimal Window",
                description: "Best cycling from \(bestHour.time) with \(comfort)% comfort score. Temperature will be \(bestHour.formattedTemp(using: units)) with \(bestHour.formattedWindSpeed(using: units)) winds.",
                priority: .high,
                color: .green
            ))
        }
        
        // Wind recommendation
        let windRange = hourlyData.windSpeedRange(using: units)
        let highWindThreshold: Double = units == .metric ? 24.0 : 15.0
        if windRange.max > highWindThreshold {
            recs.append(AnalyticsRecommendation(
                icon: "wind",
                title: "Wind Alert",
                description: "High winds expected (up to \(Int(windRange.max)) \(units.speedUnitAbbreviation)). Choose sheltered routes or plan shorter rides.",
                priority: .medium,
                color: .orange
            ))
        }
        
        // Temperature recommendation
        let tempRange = hourlyData.temperatureRange(using: units)
        let coldThreshold: Double = units == .metric ? 10.0 : 50.0
        let hotThreshold: Double = units == .metric ? 30.0 : 85.0
        
        if tempRange.min < coldThreshold || tempRange.max > hotThreshold {
            recs.append(AnalyticsRecommendation(
                icon: "thermometer",
                title: "Temperature Alert",
                description: "Temperature extremes expected (\(tempRange.formatted)). Layer appropriately and bring extra fluids.",
                priority: .medium,
                color: .blue
            ))
        }
        
        // Precipitation recommendation
        let precipSummary = precipitationSummary
        if precipSummary.maxChance > 0.5 {
            recs.append(AnalyticsRecommendation(
                icon: "cloud.rain.fill",
                title: "Rain Alert",
                description: "High chance of precipitation (\(Int(precipSummary.maxChance * 100))%). Consider indoor alternatives or waterproof gear.",
                priority: .high,
                color: .blue
            ))
        }
        
        return recs
    }
}

// MARK: - Extensions for existing EnhancedCyclingAnalyticsHelper
// Add these methods to your existing EnhancedCyclingAnalyticsHelper if you want UV/AQI support

extension EnhancedCyclingAnalyticsHelper {
    /// Enhanced average comfort using UV and AQI data if available
    func enhancedAverageComfort(uvData: [Double?] = [], aqiData: [Int?] = []) -> Int {
        guard !hourlyData.isEmpty else { return 0 }
        
        var totalComfort: Double = 0
        for (index, hour) in hourlyData.enumerated() {
            let uv = index < uvData.count ? uvData[index] : nil
            let aqi = index < aqiData.count ? aqiData[index] : nil
            totalComfort += hour.enhancedCyclingComfort(using: units, uvIndex: uv, aqi: aqi)
        }
        
        return Int((totalComfort / Double(hourlyData.count)) * 100)
    }
    
    /// Get UV risk level from provided UV data
    func uvRisk(from uvData: [Double?]) -> UVRiskLevel {
        let maxUV = uvData.compactMap { $0 }.max() ?? 0
        return UVRiskLevel.from(uvIndex: maxUV)
    }
    
    /// Get air quality risk from provided AQI data
    func airQualityRisk(from aqiData: [Int?]) -> AirQualityLevel {
        let maxAQI = aqiData.compactMap { $0 }.max() ?? 0
        return AirQualityLevel.from(aqi: maxAQI)
    }
    
    /// Get health alerts for UV and air quality
    func healthAlerts(uvData: [Double?] = [], aqiData: [Int?] = []) -> [HealthAlert] {
        var alerts: [HealthAlert] = []
        
        // UV alerts
        let maxUV = uvData.compactMap { $0 }.max() ?? 0
        if maxUV >= 8 {
            alerts.append(HealthAlert(
                type: .uv,
                severity: maxUV >= 11 ? .high : .medium,
                message: "High UV exposure risk. Wear sunscreen, sunglasses, and protective clothing.",
                icon: "sun.max.fill",
                color: maxUV >= 11 ? .red : .orange
            ))
        }
        
        // Air quality alerts
        let maxAQI = aqiData.compactMap { $0 }.max() ?? 0
        if maxAQI > 100 {
            let message: String
            let severity: HealthAlert.Severity
            
            switch maxAQI {
            case 101...150:
                message = "Air quality may affect sensitive individuals. Consider shorter rides."
                severity = .medium
            case 151...200:
                message = "Unhealthy air quality. Limit outdoor exercise intensity."
                severity = .high
            case 201...:
                message = "Very poor air quality. Consider indoor alternatives."
                severity = .high
            default:
                message = "Monitor air quality during your ride."
                severity = .medium
            }
            
            alerts.append(HealthAlert(
                type: .airQuality,
                severity: severity,
                message: message,
                icon: "aqi.medium",
                color: severity == .high ? .red : .orange
            ))
        }
        
        return alerts
    }
}

// MARK: - Supporting Enums and Structs for Enhanced Features

enum UVRiskLevel: String, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case veryHigh = "Very High"
    case extreme = "Extreme"
    
    static func from(uvIndex: Double) -> UVRiskLevel {
        switch uvIndex {
        case 0...2: return .low
        case 3...5: return .moderate
        case 6...7: return .high
        case 8...10: return .veryHigh
        default: return .extreme
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .extreme: return .purple
        }
    }
}

enum AirQualityLevel: String, CaseIterable {
    case good = "Good"
    case moderate = "Moderate"
    case unhealthyForSensitive = "Unhealthy for Sensitive"
    case unhealthy = "Unhealthy"
    case veryUnhealthy = "Very Unhealthy"
    case hazardous = "Hazardous"
    
    static func from(aqi: Int) -> AirQualityLevel {
        switch aqi {
        case 0...50: return .good
        case 51...100: return .moderate
        case 101...150: return .unhealthyForSensitive
        case 151...200: return .unhealthy
        case 201...300: return .veryUnhealthy
        default: return .hazardous
        }
    }
    
    var color: Color {
        switch self {
        case .good: return .green
        case .moderate: return .yellow
        case .unhealthyForSensitive: return .orange
        case .unhealthy: return .red
        case .veryUnhealthy: return .purple
        case .hazardous: return .brown
        }
    }
}

struct HealthAlert {
    enum AlertType {
        case uv, airQuality
    }
    
    enum Severity {
        case low, medium, high
    }
    
    let type: AlertType
    let severity: Severity
    let message: String
    let icon: String
    let color: Color
}
*/
