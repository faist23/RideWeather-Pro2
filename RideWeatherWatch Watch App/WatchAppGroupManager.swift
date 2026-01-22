//
//  WatchAppGroupManager.swift
//  RideWeatherWatch Watch App
//
//  Manages shared data storage for watch
//

import Foundation

class WatchAppGroupManager {
    static let shared = WatchAppGroupManager()
    
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
    
    func saveWeatherData(_ data: WatchWeatherData) {
        guard let defaults = Self.sharedDefaults else { return }
        
        // Convert to SharedWeatherSummary format used by complications
        let weatherSummary = SharedWeatherSummary(
            temperature: Int(data.temperature),
            feelsLike: Int(data.feelsLike),
            conditionIcon: data.condition,
            windSpeed: Int(data.windSpeed),
            windDirection: "N", // TODO: Calculate from wind direction if available
            pop: 0,
            generatedAt: data.timestamp
        )
        
        if let encoded = try? JSONEncoder().encode(weatherSummary) {
            defaults.set(encoded, forKey: weatherKey)
            defaults.synchronize()
            print("💾 Weather saved to complications key")
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
        guard let defaults = Self.sharedDefaults else { return }
        defaults.set(steps, forKey: stepsKey)
        defaults.synchronize()
        print("💾 Steps saved: \(steps)")
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

// Shared weather summary structure - MUST match complications
struct SharedWeatherSummary: Codable {
    let temperature: Int
    let feelsLike: Int
    let conditionIcon: String
    let windSpeed: Int
    let windDirection: String
    let pop: Int
    let generatedAt: Date
}
