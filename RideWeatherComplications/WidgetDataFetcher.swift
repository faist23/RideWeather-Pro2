//
//  WidgetDataFetcher.swift
//  RideWeatherComplications
//
//  Fetches fresh weather data for complications
//  Steps come from Watch app background updates - widget NEVER touches HealthKit
//

import Foundation

@MainActor
class WidgetDataFetcher {
    static let shared = WidgetDataFetcher()
    private let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
    
    // Load API key from config file
    private var apiKey: String {
        guard let path = Bundle.main.path(forResource: "OpenWeather", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String],
              let key = dict["OpenWeatherApiKey"] else {
            print("❌ Widget: Failed to load OpenWeather API key")
            return ""
        }
        return key
    }
    
    private init() {
        // Debug: Print all keys in the shared container
        if let defaults = defaults {
            print("🔍 Widget UserDefaults Debug:")
            print("   Suite: group.com.ridepro.rideweather")
            let dict = defaults.dictionaryRepresentation()
            print("   Total keys: \(dict.keys.count)")
            for key in dict.keys.sorted() {
                if key.contains("widget") || key.contains("user_") {
                    let value = dict[key]
                    print("   - \(key): \(value ?? "nil")")
                }
            }
        } else {
            print("❌ Widget: Failed to initialize UserDefaults with app group!")
        }
    }
    
    // MARK: - Fetch All Data
    
    func fetchAllData() async {
        print("🔄 Widget: Reading shared data from App Group")
        
        // Data is now primarily provided by the Watch app's background refresh or Phone sync.
        // We no longer perform independent network fetches here to avoid data mismatches.
        
        if let data = defaults?.data(forKey: "widget_weather_summary"),
           let summary = try? JSONDecoder().decode(SharedWeatherSummary.self, from: data) {
            print("✅ Widget: Successfully read shared weather - \(summary.temperature)°F")
        } else {
            print("⚠️ Widget: No shared weather data found in App Group")
        }
        
        print("🔄 Widget: Refresh complete")
    }
    
    // MARK: - Helper Functions
    
    private func mapWeatherIcon(_ icon: String) -> String {
        switch icon {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "smoke.fill"
        case "09d", "09n": return "cloud.drizzle.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.fill"
        case "13d", "13n": return "snow"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
    
    private func degreesToCardinal(_ degrees: Int) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(degrees) + 22.5) / 45.0) % 8
        return directions[index]
    }
}
