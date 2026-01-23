//
//  WatchAppGroupManager.swift
//  RideWeatherWatch Watch App
//
//  Manages shared data storage for watch
//

import Foundation
import WidgetKit

class WatchAppGroupManager {
    static let shared = WatchAppGroupManager()
    private let suiteName = "group.com.ridepro.rideweather"
    
    private static let sharedDefaults: UserDefaults? = {
        guard let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather") else {
            print("❌ Failed to create UserDefaults with suite name")
            return nil
        }
        return defaults
    }()
    
    // Use the same keys as complications
    private let weatherKey = "widget_weather_summary"
    private let stepsKey = "widget_today_steps"
    
    private init() {}
    
    // Updated: Accepts optional Alert
    func saveWeatherData(_ data: WatchWeatherData, alert: WeatherAlert? = nil) {
        let defaults = UserDefaults(suiteName: suiteName)
        
        // Map to Shared Summary (matches Widget definition)
        let summary = SharedWeatherSummary(
            temperature: Int(data.temperature),
            feelsLike: Int(data.feelsLike),
            conditionIcon: data.condition,
            windSpeed: Int(data.windSpeed),
            windDirection: compassDirection(for: 0), // Simplification if wind deg missing
            pop: 0, // Pop not always available in current current-weather call
            generatedAt: Date(),
            alertSeverity: alert?.severity.rawValue // NEW FIELD
        )
        
        if let encoded = try? JSONEncoder().encode(summary) {
            defaults?.set(encoded, forKey: "widget_weather_summary")
            print("💾 Widget Data Saved. Alert: \(alert?.severity.rawValue ?? "None")")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    func getWeatherData() -> WatchWeatherData? {
        guard let defaults = Self.sharedDefaults,
              let data = defaults.data(forKey: weatherKey),
              let summary = try? JSONDecoder().decode(SharedWeatherSummary.self, from: data) else {
            return nil
        }
        
        // Convert from SharedWeatherSummary to WatchWeatherData
        return WatchWeatherData(
            temperature: Double(summary.temperature),
            feelsLike: Double(summary.feelsLike),
            condition: summary.conditionIcon,
            description: mapIconToDescription(summary.conditionIcon),
            location: "Current Location",
            humidity: 0,
            windSpeed: Double(summary.windSpeed),
            timestamp: summary.generatedAt,
            highTemp: nil,
            lowTemp: nil
        )
    }
    
    func saveSteps(_ steps: Int) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(steps, forKey: "widget_today_steps")
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func compassDirection(for degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) & 7
        return directions[index]
    }
    
    func getSteps() -> Int {
        guard let defaults = Self.sharedDefaults else { return 0 }
        return defaults.integer(forKey: stepsKey)
    }
    
    private func mapIconToDescription(_ icon: String) -> String {
        switch icon {
        case "sun.max.fill": return "Clear"
        case "cloud.fill": return "Cloudy"
        case "cloud.rain.fill": return "Rain"
        case "cloud.bolt.fill": return "Thunderstorm"
        case "cloud.snow.fill": return "Snow"
        case "cloud.fog.fill": return "Foggy"
        default: return "Unknown"
        }
    }
}

// SHARED DATA MODEL (Must match Widget)
struct SharedWeatherSummary: Codable {
    let temperature: Int
    let feelsLike: Int
    let conditionIcon: String
    let windSpeed: Int
    let windDirection: String
    let pop: Int
    let generatedAt: Date
    let alertSeverity: String? // NEW
}
