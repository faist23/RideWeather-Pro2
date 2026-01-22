
//
//  WatchWeatherService.swift
//  RideWeatherWatch Watch App
//
//  Independent weather service for watch
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
    
    func fetchWeather(for coordinate: CLLocationCoordinate2D) async throws -> WatchWeatherData {
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&appid=\(apiKey)&units=imperial"
        
        guard let url = URL(string: urlString) else {
            throw WatchWeatherError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(WatchOpenWeatherResponse.self, from: data)
        
        return WatchWeatherData(
            temperature: response.main.temp,
            feelsLike: response.main.feels_like,
            condition: mapConditionToIcon(response.weather.first?.main ?? "Clear"),
            description: response.weather.first?.description.capitalized ?? "Clear",
            location: response.name,
            humidity: response.main.humidity,
            windSpeed: response.wind.speed,
            timestamp: Date(),
            highTemp: response.main.temp_max,
            lowTemp: response.main.temp_min
        )
    }
    
    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "OpenWeather", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 WatchWeatherService: OpenWeather.plist not found!")
            openWeather = nil
            return
        }
        
        openWeather = dict
        print("✅ WatchWeatherService: Config loaded")
        
        if configValue(forKey: "OpenWeatherApiKey") == nil {
            print("🚨 WatchWeatherService: OpenWeatherApiKey missing!")
        }
    }
    
    private func configValue(forKey key: String) -> String? {
        return openWeather?[key]
    }
    
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
}

enum WatchWeatherError: Error {
    case invalidURL
    case networkError
}

struct WatchOpenWeatherResponse: Codable {
    let main: WatchMainWeather
    let weather: [WatchWeatherCondition]
    let wind: WatchWind
    let name: String
}

struct WatchMainWeather: Codable {
    let temp: Double
    let feels_like: Double
    let temp_min: Double
    let temp_max: Double
    let humidity: Int
}

struct WatchWeatherCondition: Codable {
    let main: String
    let description: String
}

struct WatchWind: Codable {
    let speed: Double
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
