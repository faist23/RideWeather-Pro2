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
    private let locationManager = CLLocationManager()
    
    // Publish location so views can observe it if needed
    @Published var currentLocation: CLLocation?
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
    }
    
    /// Entry point: Call this from onAppear in your App root
    func startUpdating() async {
        // Check status and request if needed
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        
        // Request initial location update
        locationManager.requestLocation()
    }
    
    // MARK: - Core Location Delegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
        if locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.currentLocation = location
        
        // Save to Shared Defaults for Widgets/Complications
        if let sharedDefaults = UserDefaults(suiteName: "group.com.ridepro.rideweather") {
            sharedDefaults.set(location.coordinate.latitude, forKey: "user_latitude")
            sharedDefaults.set(location.coordinate.longitude, forKey: "user_longitude")
            sharedDefaults.set(Date(), forKey: "lastLocationUpdate")
        }
        
        // Trigger the async weather fetch for immediate UI update
        Task {
            await updateWeather(for: location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location Manager Error: \(error.localizedDescription)")
    }
    
    // MARK: - Weather Update Logic
    
    func updateWeather(for location: CLLocation? = nil) async {
        // Use passed location or fall back to cached
        guard let loc = location ?? currentLocation ?? locationManager.location else {
            print("⚠️ No location available for weather update")
            return
        }
        
        do {
            print("🔄 Fetching weather for: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
            
            // 1. Fetch Data (Tuple: Data + Array of Alerts + Hourly + Summary)
            let (weatherData, alerts, hourly, nextHourSummary) = try await WatchWeatherService.shared.fetchWeather(for: loc.coordinate)
            
            // 2. Update Session (Main Actor is guaranteed by class annotation)
            WatchSessionManager.shared.updateWeatherAlerts(alerts)
            
            // 3. Save weather data for widget
            WatchAppGroupManager.shared.saveWeatherData(weatherData, alert: alerts.first, hourly: hourly, nextHourSummary: nextHourSummary)
            
            print("✅ Weather Updated. Alerts found: \(alerts.count)")
            
        } catch {
            print("❌ Error fetching weather: \(error)")
        }
    }
    
    deinit {
        // Properties and tasks already cleaned up or removed
    }
    
}
