//
//  WeatherRepository.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//

import Foundation
import CoreLocation

struct WeatherRepository {
    private let service = WeatherService()

    func fetchWeather(for location: CLLocation, units: String) async throws -> (CurrentWeatherResponse, OneCallResponse) {
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

    // Fetch extended hourly forecast and return it mapped to `[HourlyForecast]`
    func fetchExtendedForecast(for location: CLLocation, units: String) async throws -> [HourlyForecast] {
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
    
    
    // Air pollution fetching - delegates to service layer
    func fetchAirPollution(lat: Double, lon: Double) async throws -> AirPollutionResponse {
        return try await service.fetchAirPollution(lat: lat, lon: lon)
    }
    
    // Fetch complete weather data including air pollution
    func fetchCompleteWeatherData(for location: CLLocation, units: String) async throws -> CompleteWeatherData {
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

    // MARK: - NEW: Daily Forecast Wrapper
    func fetchDailyForecast(for location: CLLocation, units: String) async throws -> [DailyItem] {
        return try await service.fetchDailyForecast(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            units: units
        )
    }

    func fetchWeatherForRoutePoint(
        coordinate: CLLocationCoordinate2D,
        time: Date,
        distance: Double,
        units: String
    ) async -> RouteWeatherPoint? {
        do {
            let forecast = try await service.fetchForecast(
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                units: units
            )
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
