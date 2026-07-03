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
        let isImperial = (defaults?.string(forKey: "appSettings.units") ?? "imperial") == "imperial"

        if providerString == "apple" {
            return try await fetchAppleWeather(for: coordinate, isImperial: isImperial)
        } else {
            return try await fetchOpenWeather(for: coordinate, isImperial: isImperial)
        }
    }

    /// Heat index in the display unit plus its severity rank; the NWS
    /// formula runs in °F regardless of the display unit.
    private func heatIndexDisplay(temperatureF: Double, humidity: Int, isImperial: Bool) -> (value: Int, severity: Int)? {
        guard let reading = HeatIndexCalculator.reading(temperatureF: temperatureF, humidity: humidity) else { return nil }
        let value = isImperial ? reading.value : (reading.value - 32) * 5 / 9
        return (Int(value.rounded()), reading.category.severityRank)
    }

    private func fetchAppleWeather(for coordinate: CLLocationCoordinate2D, isImperial: Bool) async throws -> (data: WatchWeatherData, alerts: [WeatherAlert], hourly: [ForecastHour], nextHourSummary: String?) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let tempUnit: UnitTemperature = isImperial ? .fahrenheit : .celsius
        let speedUnit: UnitSpeed = isImperial ? .milesPerHour : .kilometersPerHour

        // Fetch Apple Weather and OpenWeather alerts in parallel
        async let apple = appleWeather.weather(for: location)
        async let owAlerts = fetchOpenWeatherAlerts(for: coordinate)

        let (weather, alerts) = try await (apple, owAlerts)

        let windDeg = weather.currentWeather.wind.direction.value
        let nextHourPop = Int((weather.hourlyForecast.first?.precipitationChance ?? 0) * 100)

        let currentHumidity = Int(weather.currentWeather.humidity * 100)
        let currentHeatIndex = heatIndexDisplay(
            temperatureF: weather.currentWeather.temperature.converted(to: .fahrenheit).value,
            humidity: currentHumidity,
            isImperial: isImperial
        )

        let weatherData = WatchWeatherData(
            temperature: weather.currentWeather.temperature.converted(to: tempUnit).value,
            feelsLike: weather.currentWeather.apparentTemperature.converted(to: tempUnit).value,
            condition: mapAppleConditionToIcon(weather.currentWeather.condition),
            description: weather.currentWeather.condition.description,
            location: "Current Location",
            humidity: currentHumidity,
            windSpeed: weather.currentWeather.wind.speed.converted(to: speedUnit).value,
            windDirection: compassDirection(for: windDeg),
            pop: nextHourPop,
            timestamp: Date(),
            highTemp: weather.dailyForecast.first?.highTemperature.converted(to: tempUnit).value,
            lowTemp: weather.dailyForecast.first?.lowTemperature.converted(to: tempUnit).value,
            heatIndex: currentHeatIndex?.value,
            heatIndexSeverity: currentHeatIndex?.severity
        )

        let now = Date()
        let hourly = weather.hourlyForecast
            .filter { $0.date > now.addingTimeInterval(-1800) }
            .prefix(8)
            .map { hour in
                let heatIndex = heatIndexDisplay(
                    temperatureF: hour.temperature.converted(to: .fahrenheit).value,
                    humidity: Int(hour.humidity * 100),
                    isImperial: isImperial
                )
                return ForecastHour(
                    time: hour.date,
                    temp: Int(hour.temperature.converted(to: tempUnit).value),
                    feelsLike: Int(hour.apparentTemperature.converted(to: tempUnit).value),
                    windSpeed: Int(hour.wind.speed.converted(to: speedUnit).value),
                    icon: mapAppleConditionToIcon(hour.condition),
                    heatIndex: heatIndex?.value,
                    heatIndexSeverity: heatIndex?.severity
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

    private func fetchOpenWeather(for coordinate: CLLocationCoordinate2D, isImperial: Bool) async throws -> (data: WatchWeatherData, alerts: [WeatherAlert], hourly: [ForecastHour], nextHourSummary: String?) {
        // Switch to One Call API (exclude minutely, daily to save data/battery)
        let unitsParam = isImperial ? "imperial" : "metric"
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&exclude=minutely,daily&appid=\(apiKey)&units=\(unitsParam)"

        guard let url = URL(string: urlString) else {
            throw WatchWeatherError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(WatchOneCallResponse.self, from: data)

        // OpenWeather returns wind in m/s for metric (mph for imperial);
        // the app displays kph for metric, matching the iOS side
        func displayWind(_ speed: Double) -> Double {
            isImperial ? speed : speed * 3.6
        }
        func temperatureF(_ temp: Double) -> Double {
            isImperial ? temp : temp * 9 / 5 + 32
        }

        let now = Date()
        let hourly = (response.hourly ?? [])
            .filter { $0.dt > now.timeIntervalSince1970 - 1800 }
            .prefix(8)
            .map { hour in
                let heatIndex = hour.humidity.flatMap {
                    heatIndexDisplay(temperatureF: temperatureF(hour.temp), humidity: $0, isImperial: isImperial)
                }
                return ForecastHour(
                    time: Date(timeIntervalSince1970: hour.dt),
                    temp: Int(hour.temp),
                    feelsLike: Int(hour.feels_like),
                    windSpeed: Int(displayWind(hour.wind_speed)),
                    icon: mapConditionToIcon(hour.weather.first?.main ?? "Clear"),
                    heatIndex: heatIndex?.value,
                    heatIndexSeverity: heatIndex?.severity
                )
            }

        guard let current = response.current else {
            throw WatchWeatherError.networkError
        }

        let firstHourPop = Int((response.hourly?.first?.pop ?? 0) * 100)

        let currentHeatIndex = heatIndexDisplay(
            temperatureF: temperatureF(current.temp),
            humidity: current.humidity,
            isImperial: isImperial
        )

        let weatherData = WatchWeatherData(
            temperature: current.temp,
            feelsLike: current.feels_like,
            condition: mapConditionToIcon(current.weather.first?.main ?? "Clear"),
            description: current.weather.first?.description.capitalized ?? "Clear",
            location: "Current Location",
            humidity: current.humidity,
            windSpeed: displayWind(current.wind_speed),
            windDirection: compassDirection(for: current.wind_deg ?? 0),
            pop: firstHourPop,
            timestamp: Date(),
            highTemp: 0,
            lowTemp: 0,
            heatIndex: currentHeatIndex?.value,
            heatIndexSeverity: currentHeatIndex?.severity
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
    
    private func compassDirection(for degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) & 7
        return directions[index]
    }

    // Heuristic to map text event to severity
    private func mapSeverity(_ event: String) -> WeatherAlert.Severity {
        let eventLower = event.lowercased()
        if eventLower.contains("warning") {
            return .severe
        } else if eventLower.contains("watch") {
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
    let current: WatchCurrentWeather? // Changed to optional to support alerts-only fetches
    let hourly: [WatchHourlyWeather]?
    let alerts: [WatchOpenWeatherAlert]?
}

struct WatchCurrentWeather: Codable {
    let temp: Double
    let feels_like: Double
    let humidity: Int
    let wind_speed: Double
    let wind_deg: Double?
    let weather: [WatchWeatherCondition]
}

struct WatchHourlyWeather: Codable {
    let dt: TimeInterval
    let temp: Double
    let feels_like: Double
    let humidity: Int?
    let wind_speed: Double
    let pop: Double?   // 0.0–1.0 probability of precipitation
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
    let windDirection: String  // cardinal direction e.g. "NW"
    let pop: Int               // precipitation probability 0–100
    let timestamp: Date
    let highTemp: Double?
    let lowTemp: Double?
    // NWS heat index in the same unit as `temperature`, with severity rank
    var heatIndex: Int? = nil
    var heatIndexSeverity: Int? = nil
}
