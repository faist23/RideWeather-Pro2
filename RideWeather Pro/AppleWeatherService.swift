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
    
    /// Scans next 6 hours to find significant changes (e.g. "Rain at 2pm")
    func generateUpcomingConditionsSummary(from hourly: Forecast<HourWeather>) -> String? {
        let nextHours = hourly.prefix(7) // Current + 6 hours
        guard nextHours.count >= 2 else { return nil }
        
        let currentCondition = nextHours.first?.condition
        
        // Find the first hour where condition differs significantly from current
        for i in 1..<nextHours.count {
            let hour = nextHours[i]
            
            // Only highlight "significant" changes like precipitation or storms
            if hour.condition != currentCondition {
                let isPrecip = hour.condition.description.lowercased().contains("rain") || 
                               hour.condition.description.lowercased().contains("storm") ||
                               hour.condition.description.lowercased().contains("snow")
                
                if isPrecip {
                    let timeStr = hour.date.formatted(.dateTime.hour())
                    return "\(hour.condition.description) expected at \(timeStr)."
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Historical Weather
    
    /// Fetches weather conditions for a specific point in time (past)
    /// WeatherKit provides historical data through hourly/daily ranges.
    func fetchHistoricalWeather(for location: CLLocation, at date: Date) async throws -> (current: WeatherKit.HourWeather, metadata: WeatherKit.WeatherMetadata) {
        // Define a small range around the target date to get the specific hour
        let startDate = date.addingTimeInterval(-1800) // 30 mins before
        let endDate = date.addingTimeInterval(1800)  // 30 mins after
        
        // Fetch the hourly forecast for the range
        let hourlyForecast: Forecast<HourWeather> = try await weatherService.weather(
            for: location,
            including: .hourly(startDate: startDate, endDate: endDate)
        )
        
        // Find the closest hour in the returned forecast
        guard let closestHour = hourlyForecast.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else {
            throw NSError(domain: "AppleWeatherService", code: 404, userInfo: [NSLocalizedDescriptionKey: "No historical data found for this timestamp"])
        }
        
        // Use the metadata directly from the forecast object
        return (closestHour, hourlyForecast.metadata)
    }
}
