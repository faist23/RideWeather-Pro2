//
//  WatchWeatherService.swift
//  RideWeatherWatch Watch App
//
//  Updated: Uses OneCall API to fetch Alerts independently
//

import Foundation
import CoreLocation
import WeatherKit

class WatchWeatherService {
    static let shared = WatchWeatherService()
    
    private var openWeather: [String: String]?
    private let appleWeather = WeatherKit.WeatherService.shared
    
    private var apiKey: String {
        return configValue(forKey: "OpenWeatherApiKey") ?? "INVALID_API"
    }
    
    private init() {
        loadConfig()
    }
    
    func fetchWeather(for coordinate: CLLocationCoordinate2D) async throws -> (data: WatchWeatherData, alerts: [WeatherAlert], hourly: [ForecastHour], nextHourSummary: String?) {
        let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
        let providerString = defaults?.string(forKey: "appSettings.weatherProvider") ?? "apple"
        
        if providerString == "apple" {
            return try await fetchAppleWeather(for: coordinate)
        } else {
            return try await fetchOpenWeather(for: coordinate)
        }
    }

    private func fetchAppleWeather(for coordinate: CLLocationCoordinate2D) async throws -> (data: WatchWeatherData, alerts: [WeatherAlert], hourly: [ForecastHour], nextHourSummary: String?) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Fetch Apple Weather and OpenWeather alerts in parallel
        async let apple = appleWeather.weather(for: location)
        async let owAlerts = fetchOpenWeatherAlerts(for: coordinate)
        
        let (weather, alerts) = try await (apple, owAlerts)
        
        let weatherData = WatchWeatherData(
            temperature: weather.currentWeather.temperature.converted(to: .fahrenheit).value,
            feelsLike: weather.currentWeather.apparentTemperature.converted(to: .fahrenheit).value,
            condition: mapAppleConditionToIcon(weather.currentWeather.condition),
            description: weather.currentWeather.condition.description,
            location: "Current Location",
            humidity: Int(weather.currentWeather.humidity * 100),
            windSpeed: weather.currentWeather.wind.speed.converted(to: .milesPerHour).value,
            timestamp: Date(),
            highTemp: weather.dailyForecast.first?.highTemperature.converted(to: .fahrenheit).value,
            lowTemp: weather.dailyForecast.first?.lowTemperature.converted(to: .fahrenheit).value
        )
        
        let hourly = weather.hourlyForecast.prefix(8).map { hour in
            ForecastHour(
                time: hour.date,
                temp: Int(hour.temperature.converted(to: .fahrenheit).value),
                feelsLike: Int(hour.apparentTemperature.converted(to: .fahrenheit).value),
                windSpeed: Int(hour.wind.speed.converted(to: .milesPerHour).value),
                icon: mapAppleConditionToIcon(hour.condition)
            )
        }
        
        return (weatherData, alerts, Array(hourly), weather.minuteForecast?.summary)
    }

    private func fetchOpenWeatherAlerts(for coordinate: CLLocationCoordinate2D) async throws -> [WeatherAlert] {
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&exclude=minutely,hourly,current,daily&appid=\(apiKey)&units=imperial"
        
        guard let url = URL(string: urlString) else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(WatchOneCallResponse.self, from: data)
        
        return response.alerts?.map { alertRaw in
            WeatherAlert(
                message: alertRaw.event,
                description: alertRaw.description,
                severity: mapSeverity(alertRaw.event)
            )
        } ?? []
    }

    private func fetchOpenWeather(for coordinate: CLLocationCoordinate2D) async throws -> (data: WatchWeatherData, alerts: [WeatherAlert], hourly: [ForecastHour], nextHourSummary: String?) {
        // Switch to One Call API (exclude minutely, daily to save data/battery)
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&exclude=minutely,daily&appid=\(apiKey)&units=imperial"
        
        guard let url = URL(string: urlString) else {
            throw WatchWeatherError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(WatchOneCallResponse.self, from: data)
        
        let hourly = response.hourly?.prefix(8).map { hour in
            ForecastHour(
                time: Date(timeIntervalSince1970: hour.dt),
                temp: Int(hour.temp),
                feelsLike: Int(hour.feels_like),
                windSpeed: Int(hour.wind_speed),
                icon: mapConditionToIcon(hour.weather.first?.main ?? "Clear")
            )
        } ?? []
        
            
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
        
        // Map ALL alerts
        let alerts = response.alerts?.map { alertRaw in
            WeatherAlert(
                message: alertRaw.event,
                description: alertRaw.description,
                severity: mapSeverity(alertRaw.event)
            )
        } ?? [] // Default to empty array if nil
        
        return (weatherData, alerts, hourly, nil)
    }

    private func mapAppleConditionToIcon(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .mostlyCloudy, .cloudy: return "cloud.fill"
        case .haze, .foggy, .blowingDust: return "cloud.fog.fill"
        case .windy: return "wind"
        case .drizzle, .heavyRain, .rain, .sunShowers: return "cloud.rain.fill"
        case .flurries, .snow, .heavySnow, .sunFlurries: return "cloud.snow.fill"
        case .thunderstorms: return "cloud.bolt.fill"
        default: return "cloud.fill"
        }
    }
    
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
    let hourly: [WatchHourlyWeather]?
    let alerts: [WatchOpenWeatherAlert]?
}

struct WatchCurrentWeather: Codable {
    let temp: Double
    let feels_like: Double
    let humidity: Int
    let wind_speed: Double
    let weather: [WatchWeatherCondition]
}

struct WatchHourlyWeather: Codable {
    let dt: TimeInterval
    let temp: Double
    let feels_like: Double
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
