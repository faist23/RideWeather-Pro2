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
    
    func saveWeatherData(_ data: WatchWeatherData, alert: WeatherAlert? = nil, hourly: [ForecastHour] = [], nextHourSummary: String? = nil) {
        let defaults = UserDefaults(suiteName: suiteName)
        let summary = SharedWeatherSummary.make(from: data, alert: alert, hourly: hourly, nextHourSummary: nextHourSummary)
        
        if let encoded = try? JSONEncoder().encode(summary) {
            defaults?.set(encoded, forKey: "widget_weather_summary")
            defaults?.synchronize()
            
            print("💾 Widget Data Saved. Alert: \(alert?.severity.rawValue ?? "None")")
            print("💾 Widget Data Saved with \(hourly.count) forecast hours.")
            
            // CRITICAL: Signal complications to reload immediately
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
            windDirection: summary.windDirection,
            pop: summary.pop,
            timestamp: summary.generatedAt,
            highTemp: nil,
            lowTemp: nil,
            heatIndex: summary.heatIndex,
            heatIndexSeverity: summary.heatIndexSeverity
        )
    }
    
    func saveSteps(_ steps: Int) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(steps, forKey: "widget_today_steps")
        
        print("💾 Steps saved: \(steps)")
        
        // Force all timelines to reload
        WidgetCenter.shared.reloadAllTimelines()
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
    var alertSeverity: String? // Changed to var for WatchSessionManager updates
    var hourlyForecast: [ForecastHour]? // Changed to var for WatchSessionManager updates
    var nextHourSummary: String? // Changed to var for WatchSessionManager updates
    // NWS heat index in the same unit as `temperature`, with its severity
    // rank (1–4, see HeatIndexCalculator.Category); nil when it doesn't apply
    var heatIndex: Int? = nil
    var heatIndexSeverity: Int? = nil
}

extension SharedWeatherSummary {
    static func make(
        from data: WatchWeatherData,
        alert: WeatherAlert? = nil,
        hourly: [ForecastHour] = [],
        nextHourSummary: String? = nil
    ) -> SharedWeatherSummary {
        SharedWeatherSummary(
            temperature: Int(data.temperature),
            feelsLike: Int(data.feelsLike),
            conditionIcon: data.condition,
            windSpeed: Int(data.windSpeed),
            windDirection: data.windDirection,
            pop: data.pop,
            generatedAt: Date(),
            alertSeverity: alert?.severity.rawValue,
            hourlyForecast: hourly,
            nextHourSummary: nextHourSummary,
            heatIndex: data.heatIndex,
            heatIndexSeverity: data.heatIndexSeverity
        )
    }
}

struct ForecastHour: Codable, Identifiable {
    var id: Date { time }
    let time: Date
    let temp: Int
    let feelsLike: Int
    let windSpeed: Int
    let icon: String
    var heatIndex: Int? = nil
    var heatIndexSeverity: Int? = nil
}

