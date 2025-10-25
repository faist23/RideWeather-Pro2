//
//  LocationManager.swift
//  RideWeather Pro
//
//  Swift 6 compatible with proper concurrency and memory management
//

import Foundation
@preconcurrency import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus?

    // Performance optimizations
    private var locationUpdateTimer: Timer?
    private var lastLocationUpdate: Date?
    private let minimumUpdateInterval: TimeInterval = 30
    private let locationAccuracyThreshold: CLLocationDistance = 100

    // State management
    private var isRequestingLocation = false
    private var pendingLocationRequest = false

    override init() {
        super.init()
        setupLocationManager()
        print("[LocationManager] Initialized with optimized settings.")
    }

    // CORRECTED: Use DispatchQueue to safely clean up the non-Sendable Timer
    deinit {
        // Explicitly capture the resources that need main-thread cleanup
        let manager = self.manager
        let locationUpdateTimer = self.locationUpdateTimer

        // Use DispatchQueue.main.async to safely schedule cleanup for non-Sendable types
        DispatchQueue.main.async {
            manager.stopUpdatingLocation()
            locationUpdateTimer?.invalidate()
        }
        print("[LocationManager] Deinitialized")
    }

    private func setupLocationManager() {
        manager.delegate = self
        
        // Optimize for battery life while maintaining reasonable accuracy
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        
        // Set initial status
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocationAccess() {
        print("[LocationManager] Requesting location access...")
        let currentStatus = manager.authorizationStatus
        print("[LocationManager] Current status: \(statusString(currentStatus))")

        switch currentStatus {
        case .notDetermined:
            print("[LocationManager] Requesting 'When In Use' authorization.")
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestSingleLocation()
        case .denied, .restricted:
            print("[LocationManager] Location access denied or restricted.")
        @unknown default:
            print("[LocationManager] Unknown authorization status.")
        }
    }
    
    private func requestSingleLocation() {
        guard !isRequestingLocation else {
            pendingLocationRequest = true
            return
        }
        
        // Check if we have a recent location
        if let lastLocation = location,
           let lastUpdate = lastLocationUpdate,
           Date().timeIntervalSince(lastUpdate) < minimumUpdateInterval,
           lastLocation.horizontalAccuracy <= locationAccuracyThreshold {
            print("[LocationManager] Using recent cached location.")
            return
        }
        
        isRequestingLocation = true
        print("[LocationManager] Requesting current location...")
        
        manager.requestLocation()
        
        // Set a timeout for location request
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            // Use weak self to avoid capture issues
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleLocationTimeout()
            }
        }
    }
    
    private func handleLocationTimeout() async {
        print("[LocationManager] Location request timed out.")
        isRequestingLocation = false
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        
        // If there's a pending request, try again
        if pendingLocationRequest {
            pendingLocationRequest = false
            requestSingleLocation()
        }
    }
    
/*    // Force refresh location (for pull-to-refresh scenarios)
    func forceLocationUpdate() {
        lastLocationUpdate = nil
        requestSingleLocation()
    }*/
    
    // MARK: - CLLocationManagerDelegate (Swift 6 Compatible)
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Use weak self pattern in Task to avoid retention issues
        let newStatus = manager.authorizationStatus
        Task { [weak self] in
            await MainActor.run {
                guard let self = self else { return }
                self.authorizationStatus = newStatus
                print("[LocationManager] Authorization changed to: \(self.statusString(newStatus))")
                
                switch newStatus {
                case .authorizedWhenInUse, .authorizedAlways:
                    print("[LocationManager] Permission granted. Requesting location.")
                    self.requestSingleLocation()
                case .denied, .restricted:
                    print("[LocationManager] Permission denied or restricted.")
                case .notDetermined:
                    print("[LocationManager] Authorization still not determined.")
                @unknown default:
                    print("[LocationManager] Unknown authorization status.")
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // Use weak self pattern to avoid capture issues
        Task { [weak self] in
            await MainActor.run {
                guard let self = self else { return }
                
                print("[LocationManager] Received location update.")
                
                // Validate location accuracy
                guard newLocation.horizontalAccuracy <= self.locationAccuracyThreshold else {
                    print("[LocationManager] Location accuracy too low: \(newLocation.horizontalAccuracy)m")
                    return
                }
                
                // Check if this is a significant location change
                if let currentLocation = self.location {
                    let distance = newLocation.distance(from: currentLocation)
                    if distance < 10 {
                        print("[LocationManager] Location change too small: \(distance)m")
                        return
                    }
                }
                
                self.location = newLocation
                self.lastLocationUpdate = Date()
                self.isRequestingLocation = false
                self.locationUpdateTimer?.invalidate()
                self.locationUpdateTimer = nil
                
                print("[LocationManager] Location updated successfully.")
                
                // Handle pending requests
                if self.pendingLocationRequest {
                    self.pendingLocationRequest = false
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        await MainActor.run {
                            self.requestSingleLocation()
                        }
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Use weak self pattern to avoid capture issues
        Task { [weak self] in
            await MainActor.run {
                guard let self = self else { return }
                
                print("[LocationManager] Location update failed: \(error.localizedDescription)")
                
                self.isRequestingLocation = false
                self.locationUpdateTimer?.invalidate()
                self.locationUpdateTimer = nil
                
                // Handle specific errors
                if let clError = error as? CLError {
                    switch clError.code {
                    case .locationUnknown:
                        print("[LocationManager] Location unknown - will retry")
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                            await MainActor.run {
                                self.requestSingleLocation()
                            }
                        }
                    case .denied:
                        print("[LocationManager] Location access denied")
                        self.authorizationStatus = .denied
                    case .network:
                        print("[LocationManager] Network error - will retry")
                        Task {
                            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                            await MainActor.run {
                                self.requestSingleLocation()
                            }
                        }
                    default:
                        print("[LocationManager] Other location error: \(clError.localizedDescription)")
                    }
                }
                
                // Handle pending requests
                if self.pendingLocationRequest {
                    self.pendingLocationRequest = false
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                        await MainActor.run {
                            self.requestSingleLocation()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private func statusString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Authorized Always"
        case .authorizedWhenInUse: return "Authorized When In Use"
        @unknown default: return "Unknown"
        }
    }
    
    // Computed properties for UI
    var isLocationAvailable: Bool {
        return location != nil && (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways)
    }
    
    var locationAge: TimeInterval? {
        guard let lastUpdate = lastLocationUpdate else { return nil }
        return Date().timeIntervalSince(lastUpdate)
    }
    
    var isLocationRecent: Bool {
        guard let age = locationAge else { return false }
        return age < minimumUpdateInterval
    }
}
