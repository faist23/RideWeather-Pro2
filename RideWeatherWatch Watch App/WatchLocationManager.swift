//
//  WatchLocationManager.swift
//  RideWeatherWatch Watch App
//

import Foundation
import CoreLocation
import SwiftUI
import Combine

@MainActor
class WatchLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WatchLocationManager()

    // Internal so tests can inject a MockCLLocationManager subclass.
    let locationManager: CLLocationManager

    @Published var currentLocation: CLLocation?
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined

    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var isFetchingWeather = false

    init(manager: CLLocationManager = CLLocationManager()) {
        locationManager = manager
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
    }

    /// Foreground entry point: call on app launch and scene-active transitions.
    func startUpdating() async {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.requestLocation()
    }

    /// Background entry point: suspends until a one-shot location fix arrives or
    /// the timeout elapses. Returns nil on timeout so the caller can fall back to
    /// cached App Group coordinates.
    func requestLocationAsync(timeout: TimeInterval = 8.0) async -> CLLocation? {
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard let pending = locationContinuation else { return }
                locationContinuation = nil
                pending.resume(returning: nil)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
        // Do NOT call requestLocation() here — startUpdating() handles the
        // initial fetch on every foreground entry. Calling it here produces
        // duplicate fetches because this delegate fires on every init.
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location

        if let sharedDefaults = UserDefaults(suiteName: "group.com.ridepro.rideweather") {
            sharedDefaults.set(location.coordinate.latitude, forKey: "user_latitude")
            sharedDefaults.set(location.coordinate.longitude, forKey: "user_longitude")
            sharedDefaults.set(Date(), forKey: "lastLocationUpdate")
        }

        // Background path: resolve the awaiting continuation and let the caller
        // handle weather fetch. Foreground path: trigger weather fetch directly.
        if let cont = locationContinuation {
            locationContinuation = nil
            cont.resume(returning: location)
            return
        }

        Task {
            await updateWeather(for: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location Manager Error: \(error.localizedDescription)")
        if let cont = locationContinuation {
            locationContinuation = nil
            cont.resume(returning: nil)
        }
    }

    // MARK: - Weather Update

    func updateWeather(for location: CLLocation? = nil) async {
        guard !isFetchingWeather else {
            print("⌚️ Weather fetch already in-flight, skipping duplicate")
            return
        }
        guard let loc = location ?? currentLocation ?? locationManager.location else {
            print("⚠️ No location available for weather update")
            return
        }
        isFetchingWeather = true
        defer { isFetchingWeather = false }

        do {
            print("🔄 Fetching weather for: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")

            let (weatherData, alerts, hourly, nextHourSummary) = try await WatchWeatherService.shared.fetchWeather(for: loc.coordinate)

            WatchSessionManager.shared.updateWeatherAlerts(alerts)

            let liveSummary = SharedWeatherSummary.make(from: weatherData, alert: alerts.first, hourly: hourly, nextHourSummary: nextHourSummary)
            let prunedSummary = WatchSessionManager.shared.prunePastHours(liveSummary)
            WatchSessionManager.shared.weatherSummary = prunedSummary

            WatchAppGroupManager.shared.saveWeatherData(weatherData, alert: alerts.first, hourly: prunedSummary.hourlyForecast ?? [], nextHourSummary: nextHourSummary)

            print("✅ Weather Updated. Alerts found: \(alerts.count)")
        } catch {
            print("❌ Error fetching weather: \(error)")
        }
    }
}
