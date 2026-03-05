//
//  AppleWeatherService.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 3/4/26.
//

import Foundation
import WeatherKit
import CoreLocation

@available(iOS 16.0, *)
class AppleWeatherService {
    static let shared = AppleWeatherService()
    private let weatherService = WeatherKit.WeatherService.shared
    
    private init() {}
    
    func fetchWeather(for location: CLLocation) async throws -> (current: WeatherKit.CurrentWeather, hourly: Forecast<HourWeather>, daily: Forecast<DayWeather>, alerts: [WeatherKit.WeatherAlert]?, minute: Forecast<MinuteWeather>?) {
        let weather = try await weatherService.weather(for: location)
        return (weather.currentWeather, weather.hourlyForecast, weather.dailyForecast, weather.weatherAlerts, weather.minuteForecast)
    }
    
    func fetchNextHourSummary(for location: CLLocation) async -> String? {
        do {
            let weather = try await weatherService.weather(for: location, including: .minute)
            return weather?.summary
        } catch {
            print("AppleWeatherService: Failed to fetch minute forecast: \(error)")
            return nil
        }
    }
}
