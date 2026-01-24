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
    
    // NEW: Background task for periodic updates
    private var updateTask: Task<Void, Never>?
    
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
        
        // NEW: Start periodic background updates
        startPeriodicUpdates()
    }
    
    // NEW: Periodic refresh every 30 minutes
    private func startPeriodicUpdates() {
        // Cancel any existing task
        updateTask?.cancel()
        
        updateTask = Task {
            while !Task.isCancelled {
                // Wait 30 minutes
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                
                guard !Task.isCancelled else { break }
                
                // Trigger location refresh
                locationManager.requestLocation()
                
                print("🔄 Periodic weather update triggered")
            }
        }
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
        
        // Trigger the async weather fetch
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
            
            // 1. Fetch Data (Tuple: Data + Array of Alerts)
            let (weatherData, alerts) = try await WatchWeatherService.shared.fetchWeather(for: loc.coordinate)
            
            // 2. Update Session (Main Actor is guaranteed by class annotation)
            WatchSessionManager.shared.updateWeatherAlerts(alerts)
            
            // 3. Save weather data for widget
            WatchAppGroupManager.shared.saveWeatherData(weatherData, alert: alerts.first)
            
            print("✅ Weather Updated. Alerts found: \(alerts.count)")
            
        } catch {
            print("❌ Error fetching weather: \(error)")
        }
    }
    
    deinit {
        updateTask?.cancel()
    }
}
