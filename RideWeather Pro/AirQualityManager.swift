//
//  AirQualityManager.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation

/// Single home for the app's air-quality sourcing policy: official AirNow
/// (US EPA station) data first, with the OpenWeather model pipeline as
/// fallback — model products can understate smoke events by an order of
/// magnitude (a real AQI-434 episode read as 64 from model data).
///
/// Two consumers, one policy:
/// - Route forecast: worst AQI over the planned ride window.
/// - Live Weather: current conditions at the user's location.
///
/// Every failure path returns nil — air quality never blocks or fails the
/// caller's flow.
final class AirQualityManager {
    static let shared = AirQualityManager()

    private let weatherRepo = WeatherRepository()

    // MARK: - Route forecast

    /// Air quality for a planned ride window at the route start, or nil when
    /// neither source has usable data.
    func routeAirQuality(startCoordinate: CLLocationCoordinate2D, windowStart: Date, windowEnd: Date) async -> RouteAirQualitySummary? {
        if let airNowSummary = await airNowRouteAirQuality(coordinate: startCoordinate, windowStart: windowStart, windowEnd: windowEnd) {
            return airNowSummary
        }
        return await openWeatherRouteAirQuality(coordinate: startCoordinate, windowStart: windowStart, windowEnd: windowEnd)
    }

    /// Worst official AirNow AQI over the ride window, or nil when AirNow
    /// has no coverage (non-US, outage, or ride beyond its daily forecast).
    private func airNowRouteAirQuality(coordinate: CLLocationCoordinate2D, windowStart: Date, windowEnd: Date) async -> RouteAirQualitySummary? {
        do {
            async let observationsFetch = weatherRepo.fetchAirNowObservations(
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
            async let forecastFetch = weatherRepo.fetchAirNowForecast(
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
            let (observations, forecasts) = try await (observationsFetch, forecastFetch)

            guard let selected = AirNowRouteAQISelector.select(
                observations: observations,
                forecasts: forecasts,
                windowStart: windowStart,
                windowEnd: windowEnd
            ) else { return nil }

            return RouteAirQualitySummary(
                aqi: selected.aqi,
                category: EPAAirQualityCalculator.Category(aqi: selected.aqi),
                dominantPollutant: selected.dominantPollutant,
                windowStart: windowStart,
                windowEnd: windowEnd,
                source: .airNow
            )
        } catch {
            print("⚠️ AirNow unavailable, using OpenWeather fallback: \(error)")
            return nil
        }
    }

    /// Fallback: worst-hour EPA AQI computed from OpenWeather's modeled
    /// pollution forecast at the route start (understates smoke events).
    private func openWeatherRouteAirQuality(coordinate: CLLocationCoordinate2D, windowStart: Date, windowEnd: Date) async -> RouteAirQualitySummary? {
        do {
            let forecast = try await weatherRepo.fetchAirPollutionForecast(
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )

            // Pad by half an hour each side so the hourly entries bracketing
            // departure and finish are included.
            let paddedStart = windowStart.addingTimeInterval(-1800).timeIntervalSince1970
            let paddedEnd = windowEnd.addingTimeInterval(1800).timeIntervalSince1970
            var entries = forecast.list.filter { $0.dt >= paddedStart && $0.dt <= paddedEnd }

            if entries.isEmpty {
                // Short ride inside a single forecast hour: use the nearest
                // entry if the ride is within the forecast horizon at all.
                let departure = windowStart.timeIntervalSince1970
                if let nearest = forecast.list.min(by: { abs($0.dt - departure) < abs($1.dt - departure) }),
                   abs(nearest.dt - departure) <= 3600 {
                    entries = [nearest]
                } else {
                    // Ride is beyond the ~4-day pollution forecast horizon —
                    // show nothing rather than stale current conditions.
                    return nil
                }
            }

            let readings = entries.map { reading(from: $0.components) }

            guard let worst = readings.max(by: { $0.aqi < $1.aqi }) else { return nil }

            return RouteAirQualitySummary(
                aqi: worst.aqi,
                category: worst.category,
                dominantPollutant: worst.dominantPollutant,
                windowStart: windowStart,
                windowEnd: windowEnd,
                source: .openWeatherModel
            )
        } catch {
            print("⚠️ Route air quality unavailable: \(error)")
            return nil
        }
    }

    // MARK: - Current conditions

    /// Current-conditions AQI at the user's location: official AirNow
    /// observations first, falling back to OpenWeather components the caller
    /// already fetched with the current weather. Returns nil when neither
    /// source has data, and returns nil without falling back when the
    /// surrounding task was cancelled — callers decide whether nil is
    /// publishable (see the cancellation guard in WeatherViewModel).
    func currentAirQuality(location: CLLocation, fallbackComponents: PollutionComponents?) async -> CurrentAirQuality? {
        do {
            let observations = try await weatherRepo.fetchAirNowObservations(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude
            )
            guard !Task.isCancelled else { return nil }
            // Reusing the route selector with no forecasts and a zero-length
            // window at `now` reduces it to "max of current observations".
            let now = Date()
            if let selected = AirNowRouteAQISelector.select(
                observations: observations,
                forecasts: [],
                windowStart: now,
                windowEnd: now,
                now: now
            ) {
                return CurrentAirQuality(
                    aqi: selected.aqi,
                    category: EPAAirQualityCalculator.Category(aqi: selected.aqi),
                    dominantPollutant: selected.dominantPollutant,
                    source: .airNow
                )
            }
        } catch {
            if Task.isCancelled { return nil }
            print("⚠️ AirNow current observations unavailable: \(error)")
        }

        guard !Task.isCancelled, let components = fallbackComponents else { return nil }
        let fallback = reading(from: components)
        return CurrentAirQuality(
            aqi: fallback.aqi,
            category: fallback.category,
            dominantPollutant: fallback.dominantPollutant,
            source: .openWeatherModel
        )
    }

    // MARK: - Shared

    private func reading(from components: PollutionComponents) -> EPAAirQualityCalculator.Reading {
        return EPAAirQualityCalculator.reading(
            pm25: components.pm2_5,
            pm10: components.pm10,
            o3: components.o3,
            no2: components.no2,
            so2: components.so2,
            co: components.co
        )
    }
}
