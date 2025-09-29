//
//  LocationManager.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/12/25.
//


import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus? // **ADDED**: Publish authorization status
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }
    
    // **ADDED**: This delegate method is called whenever the authorization status changes.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission granted, request location
            manager.requestLocation()
        case .denied:
            // Permission denied
            print("Location access denied.")
        case .notDetermined:
            // Permission not yet asked
            manager.requestWhenInUseAuthorization()
        case .restricted:
            // Permission restricted (e.g., by parental controls)
            print("Location access restricted.")
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // **FIXED**: Better handling for specific errors like denied access.
        if let clError = error as? CLError, clError.code == .denied {
            print("Location access was denied by the user.")
        } else {
            print("Error getting location: \(error.localizedDescription)")
        }
    }
}
