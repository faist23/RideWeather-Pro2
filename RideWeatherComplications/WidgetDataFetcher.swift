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
            if let dict = defaults.dictionaryRepresentation() as? [String: Any] {
                print("   Total keys: \(dict.keys.count)")
                for key in dict.keys.sorted() {
                    if key.contains("widget") || key.contains("user_") {
                        let value = dict[key]
                        print("   - \(key): \(value ?? "nil")")
                    }
                }
            }
        } else {
            print("❌ Widget: Failed to initialize UserDefaults with app group!")
        }
    }
    
    // MARK: - Fetch All Data
    
    func fetchAllData() async {
        print("🔄 Widget: Refreshing weather only (steps come from Watch app)")
        
        // Steps are updated by Watch app background process - just read current value
        let currentSteps = defaults?.integer(forKey: "widget_today_steps") ?? 0
        print("📊 Widget: Current steps from Watch: \(currentSteps)")
        
        // Only fetch weather
        await fetchWeather()
        
        print("🔄 Widget: Weather refresh complete")
    }
    
    // MARK: - Fetch Weather from OpenWeather API 3.0
    
    @discardableResult
    private func fetchWeather() async -> Data? {
        // Get stored location from iOS app
        guard let latitude = defaults?.double(forKey: "user_latitude"),
              let longitude = defaults?.double(forKey: "user_longitude"),
              latitude != 0, longitude != 0 else {
            print("⚠️ Widget: No location available")
            return nil
        }
        
        print("📍 Widget: Using location \(latitude), \(longitude)")
        
        guard !apiKey.isEmpty else {
            print("❌ Widget: No API key")
            return nil
        }
        
        // UPDATED: Removed 'alerts' from exclude list
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(latitude)&lon=\(longitude)&exclude=minutely,daily&appid=\(apiKey)&units=imperial"
        
        guard let url = URL(string: urlString) else {
            print("❌ Widget: Invalid URL")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ Widget: API error")
                return nil
            }
            
            if let weatherData = parseWeatherResponse(data) {
                let encoded = try? JSONEncoder().encode(weatherData)
                defaults?.set(encoded, forKey: "widget_weather_summary")
                defaults?.synchronize()
                print("✅ Widget: Weather updated - \(weatherData.temperature)°F, Alert: \(weatherData.alertSeverity ?? "None")")
                return encoded
            }
            
            return nil
        } catch {
            print("❌ Widget: Fetch failed - \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Parse Weather Response
    
    private func parseWeatherResponse(_ data: Data) -> SharedWeatherSummary? {
        struct OneCallResponse: Codable {
            let current: Current
            let hourly: [Hourly]
            let alerts: [Alert]? // NEW: Capture alerts
            
            struct Current: Codable {
                let temp: Double
                let feels_like: Double
                let weather: [Weather]
                let wind_speed: Double
                let wind_deg: Int
            }
            
            struct Hourly: Codable {
                let pop: Double
            }
            
            struct Weather: Codable {
                let icon: String
            }
            
            struct Alert: Codable {
                let event: String
            }
        }
        
        do {
            let response = try JSONDecoder().decode(OneCallResponse.self, from: data)
            
            let conditionIcon = mapWeatherIcon(response.current.weather.first?.icon ?? "01d")
            let windDirection = degreesToCardinal(response.current.wind_deg)
            let pop = Int((response.hourly.first?.pop ?? 0) * 100)
            
            // Map Alert Severity
            var alertSeverity: String? = nil
            if let firstAlert = response.alerts?.first {
                alertSeverity = mapSeverity(firstAlert.event)
            }
            
            return SharedWeatherSummary(
                temperature: Int(response.current.temp.rounded()),
                feelsLike: Int(response.current.feels_like.rounded()),
                conditionIcon: conditionIcon,
                windSpeed: Int(response.current.wind_speed.rounded()),
                windDirection: windDirection,
                pop: pop,
                generatedAt: Date(),
                alertSeverity: alertSeverity // NEW: Pass the mapped severity
            )
        } catch {
            print("❌ Widget: Parse failed - \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Helper Functions
    
    private func mapSeverity(_ event: String) -> String {
        let lower = event.lowercased()
        if lower.contains("warning") || lower.contains("tornado") || lower.contains("severe") {
            return "severe"
        } else if lower.contains("watch") || lower.contains("advisory") {
            return "warning"
        }
        return "advisory"
    }
    
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
