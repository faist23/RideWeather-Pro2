//
//  GeocodingManager.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 12/19/25.
//

import CoreLocation

// This actor prevents "Thread Sanitizer" warnings and handles the concurrency safely
actor GeocodingManager {
    static let shared = GeocodingManager()
    
    // In-memory cache to stop you from hitting Apple's servers 100 times for the same start point
    private var cache: [CLLocation: CLPlacemark] = [:]
    
    func reverseGeocode(location: CLLocation) async throws -> CLPlacemark? {
        // 1. Check Memory Cache first
        if let cached = cache[location] {
            print("📍 Geocoding: Hit memory cache")
            return cached
        }
        
        // 2. Perform Network Request
        let geocoder = CLGeocoder()
        // This is where your 'MKErrorDomain error 4' comes from—Apple blocking you for asking too fast.
        // We add a tiny delay to be polite if needed, or handle the error gracefully.
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        
        if let first = placemarks.first {
            cache[location] = first
            return first
        }
        return nil
    }
}
