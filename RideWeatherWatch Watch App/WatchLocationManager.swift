
//
//  WatchLocationManager.swift
//  RideWeatherWatch Watch App
//
//  Independent location manager for watch
//

import CoreLocation
import Combine
import ClockKit

class WatchLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WatchLocationManager()
    
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        
        print("📍 WatchLocationManager initialized")
    }
    
    func startUpdating() async {
        print("📍 Starting location updates, status: \(authorizationStatus.rawValue)")
        
        switch authorizationStatus {
        case .notDetermined:
            print("📍 Requesting location permission")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 Already authorized, starting updates")
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            print("❌ Location access denied or restricted")
        @unknown default:
            print("⚠️ Unknown authorization status")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("📍 Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        self.location = location
        
        Task {
            await fetchWeatherForCurrentLocation()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        print("📍 Authorization changed: \(authorizationStatus.rawValue) → \(newStatus.rawValue)")
        authorizationStatus = newStatus
        
        if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
            print("📍 Permission granted, starting updates")
            locationManager.startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
    
    private func fetchWeatherForCurrentLocation() async {
            guard let location = location else { return }
            
            do {
                // 1. Fetch Data & Alert
                let (weatherData, alert) = try await WatchWeatherService.shared.fetchWeather(for: location.coordinate)
                
                // 2. Save BOTH to App Group (This was the missing link!)
                WatchAppGroupManager.shared.saveWeatherData(weatherData, alert: alert)
                
                // 3. Update Session (for App UI)
                await MainActor.run {
                    WatchSessionManager.shared.updateWeatherAlertIndependent(alert)
                }
                
                print("✅ Watch Fetched Weather. Alert: \(alert?.severity.rawValue ?? "None")")
                
            } catch {
                print("❌ Watch Weather Fetch Failed: \(error.localizedDescription)")
            }
        }
}
