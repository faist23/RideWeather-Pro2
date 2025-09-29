//
//  WeatherRepository.swift
//

import Foundation
import CoreLocation

struct WeatherRepository {
    private let service = WeatherService()

    func fetchWeather(for location: CLLocation, units: String) async throws -> (CurrentWeatherResponse, OneCallResponse) {
        async let current = service.fetchCurrentWeather(lat: location.coordinate.latitude, lon: location.coordinate.longitude, units: units)
        async let forecast = service.fetchForecast(lat: location.coordinate.latitude, lon: location.coordinate.longitude, units: units)
        return try await (current, forecast)
    }

    func fetchExtendedForecast(for location: CLLocation, units: String) async throws -> OneCallResponse {
        return try await service.fetchExtendedForecast(lat: location.coordinate.latitude, lon: location.coordinate.longitude, units: units)
    }

    func fetchWeatherForRoutePoint(coordinate: CLLocationCoordinate2D, time: Date, distance: Double, units: String) async -> RouteWeatherPoint? {
        do {
            let forecast = try await service.fetchForecast(lat: coordinate.latitude, lon: coordinate.longitude, units: units)
            guard let weatherForHour = forecast.hourly.min(by: { abs($0.dt - time.timeIntervalSince1970) < abs($1.dt - time.timeIntervalSince1970) }) else {
                return nil
            }
            let displayWeather = WeatherMapper.mapForecastItemToDisplayModel(weatherForHour)
            return RouteWeatherPoint(coordinate: coordinate, distance: distance, eta: time, weather: displayWeather)
        } catch {
            print("Failed route point weather: \(error)")
            return nil
        }
    }
}
