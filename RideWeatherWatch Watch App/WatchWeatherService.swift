//
//  WatchWeatherService.swift
//  RideWeatherWatch Watch App
//
//  Updated: Uses OneCall API to fetch Alerts independently
//

import Foundation
import CoreLocation

class WatchWeatherService {
    static let shared = WatchWeatherService()
    
    private var openWeather: [String: String]?
    
    private var apiKey: String {
        return configValue(forKey: "OpenWeatherApiKey") ?? "INVALID_API"
    }
    
    private init() {
        loadConfig()
    }
    
    // Updated return type to include optional Alert
    func fetchWeather(for coordinate: CLLocationCoordinate2D) async throws -> (data: WatchWeatherData, alert: WeatherAlert?) {
        // Switch to One Call API (exclude minutely, hourly, daily to save data/battery)
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&exclude=minutely,hourly,daily&appid=\(apiKey)&units=imperial"
        
        guard let url = URL(string: urlString) else {
            throw WatchWeatherError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(WatchOneCallResponse.self, from: data)
        
        // Map Basic Data
        let weatherData = WatchWeatherData(
            temperature: response.current.temp,
            feelsLike: response.current.feels_like,
            condition: mapConditionToIcon(response.current.weather.first?.main ?? "Clear"),
            description: response.current.weather.first?.description.capitalized ?? "Clear",
            location: "Current Location", // OneCall doesn't return city name, generic fallback
            humidity: response.current.humidity,
            windSpeed: response.current.wind_speed,
            timestamp: Date(),
            highTemp: 0, // OneCall 'current' doesn't have daily high/low, would need 'daily' include
            lowTemp: 0
        )
        
        // Map Alert (if exists)
        var weatherAlert: WeatherAlert? = nil
        if let firstAlert = response.alerts?.first {
            weatherAlert = WeatherAlert(
                message: firstAlert.event,
                description: firstAlert.description,
                severity: mapSeverity(firstAlert.event) // Heuristic mapping
            )
        }
        
        return (weatherData, weatherAlert)
    }
    
    // ... loadConfig and configValue remain the same ...
    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "OpenWeather", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            return
        }
        openWeather = dict
    }
    
    private func configValue(forKey key: String) -> String? {
        return openWeather?[key]
    }
    
    // ... mapConditionToIcon remains the same ...
    private func mapConditionToIcon(_ condition: String) -> String {
        switch condition.lowercased() {
        case "clear": return "sun.max.fill"
        case "clouds": return "cloud.fill"
        case "rain": return "cloud.rain.fill"
        case "drizzle": return "cloud.drizzle.fill"
        case "thunderstorm": return "cloud.bolt.fill"
        case "snow": return "cloud.snow.fill"
        case "mist", "fog", "haze": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
    
    // Heuristic to map text event to severity
    private func mapSeverity(_ event: String) -> WeatherAlert.Severity {
        let lower = event.lowercased()
        if lower.contains("warning") || lower.contains("tornado") || lower.contains("severe") {
            return .severe
        } else if lower.contains("watch") || lower.contains("advisory") {
            return .warning
        }
        return .advisory
    }
}

enum WatchWeatherError: Error {
    case invalidURL
    case networkError
}

// MARK: - One Call Structs

struct WatchOneCallResponse: Codable {
    let current: WatchCurrentWeather
    let alerts: [WatchOpenWeatherAlert]?
}

struct WatchCurrentWeather: Codable {
    let temp: Double
    let feels_like: Double
    let humidity: Int
    let wind_speed: Double
    let weather: [WatchWeatherCondition]
}

struct WatchOpenWeatherAlert: Codable {
    let sender_name: String
    let event: String
    let start: TimeInterval
    let end: TimeInterval
    let description: String
}

// Reuse existing support structs
struct WatchWeatherCondition: Codable {
    let main: String
    let description: String
}

struct WatchWeatherData: Codable {
    let temperature: Double
    let feelsLike: Double
    let condition: String
    let description: String
    let location: String
    let humidity: Int
    let windSpeed: Double
    let timestamp: Date
    let highTemp: Double?
    let lowTemp: Double?
}
