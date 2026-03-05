//
//  WeatherRepository.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//

import Foundation
import CoreLocation
import WeatherKit

struct WeatherRepository {
    private let service = WeatherService()
    private let appleService = AppleWeatherService.shared

    func fetchWeather(for location: CLLocation, units: String) async throws -> (CurrentWeatherResponse, OneCallResponse) {
        let settings = UserDefaultsManager.shared.loadSettings()
        
        if settings.weatherProvider == .apple {
            return try await fetchAppleWeather(for: location, units: units)
        } else {
            async let current = service.fetchCurrentWeather(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: units
            )
            async let forecast = service.fetchForecast(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: units
            )
            return try await (current, forecast)
        }
    }

    private func fetchAppleWeather(for location: CLLocation, units: String) async throws -> (CurrentWeatherResponse, OneCallResponse) {
        // Fetch Apple Weather and OpenWeather alerts in parallel
        async let appleData = appleService.fetchWeather(for: location)
        async let owAlerts = service.fetchForecast(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            units: units
        )
        
        let (apple, alerts) = try await (appleData, owAlerts)
        
        // Map Apple Weather to OpenWeather-style models for compatibility
        let current = WeatherMapper.mapAppleCurrentToOpenWeather(apple.current, location: location, units: units, nextHourSummary: apple.minute?.summary, minuteForecast: apple.minute)
        let hourly = apple.hourly.map { WeatherMapper.mapAppleHourlyToOpenWeather($0) }
        
        let forecast = OneCallResponse(hourly: hourly, alerts: alerts.alerts)
        return (current, forecast)
    }

    // Fetch extended hourly forecast and return it mapped to `[HourlyForecast]`
    func fetchExtendedForecast(for location: CLLocation, units: String) async throws -> [HourlyForecast] {
        let settings = UserDefaultsManager.shared.loadSettings()
        
        if settings.weatherProvider == .apple {
            let apple = try await appleService.fetchWeather(for: location)
            return apple.hourly.map { WeatherMapper.mapAppleHourlyToUIModel($0) }
        } else {
            let extended = try await service.fetchExtendedForecast(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: units
            )

            // Convert ExtendedOneCallResponse.hourly → [HourlyForecast]
            return extended.hourly.map { item in
                HourlyForecast(from: item)
            }
        }
    }
    
    
    // Air pollution fetching - delegates to service layer
    func fetchAirPollution(lat: Double, lon: Double) async throws -> AirPollutionResponse {
        return try await service.fetchAirPollution(lat: lat, lon: lon)
    }
    
    // Fetch complete weather data including air pollution
    func fetchCompleteWeatherData(for location: CLLocation, units: String) async throws -> CompleteWeatherData {
        let settings = UserDefaultsManager.shared.loadSettings()
        
        if settings.weatherProvider == .apple {
            async let appleData = appleService.fetchWeather(for: location)
            async let owAlerts = service.fetchForecast(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: units
            )
            async let airPollution = service.fetchAirPollution(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude
            )
            
            let (apple, alerts, pollution) = try await (appleData, owAlerts, airPollution)
            
            let current = WeatherMapper.mapAppleCurrentToOpenWeather(apple.current, location: location, units: units, nextHourSummary: apple.minute?.summary, minuteForecast: apple.minute)
            let hourly = apple.hourly.map { WeatherMapper.mapAppleHourlyToOpenWeather($0) }
            let forecast = OneCallResponse(hourly: hourly, alerts: alerts.alerts)
            
            return CompleteWeatherData(
                current: current,
                forecast: forecast,
                airPollution: pollution
            )
        } else {
            async let currentWeather = service.fetchCurrentWeather(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: units
            )
            async let forecast = service.fetchForecast(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: units
            )
            async let airPollution = service.fetchAirPollution(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude
            )
            
            let (current, fcst, pollution) = try await (currentWeather, forecast, airPollution)
            
            return CompleteWeatherData(
                current: current,
                forecast: fcst,
                airPollution: pollution
            )
        }
    }

    // MARK: - NEW: Daily Forecast Wrapper
    func fetchDailyForecast(for location: CLLocation, units: String) async throws -> [DailyItem] {
        let settings = UserDefaultsManager.shared.loadSettings()
        
        if settings.weatherProvider == .apple {
            let apple = try await appleService.fetchWeather(for: location)
            return apple.daily.map { WeatherMapper.mapAppleDailyToOpenWeather($0) }
        } else {
            return try await service.fetchDailyForecast(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: units
            )
        }
    }

    func fetchWeatherForRoutePoint(
        coordinate: CLLocationCoordinate2D,
        time: Date,
        distance: Double,
        units: String
    ) async -> RouteWeatherPoint? {
        do {
            let (current, forecast) = try await fetchWeather(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), units: units)
            
            guard let weatherForHour = forecast.hourly.min(
                by: { abs($0.dt - time.timeIntervalSince1970) < abs($1.dt - time.timeIntervalSince1970) }
            ) else {
                return nil
            }
            let displayWeather = WeatherMapper.mapForecastItemToDisplayModel(weatherForHour)
            return RouteWeatherPoint(
                coordinate: coordinate,
                distance: distance,
                eta: time,
                weather: displayWeather
            )
        } catch {
            print("Failed route point weather: \(error)")
            return nil
        }
    }
}
