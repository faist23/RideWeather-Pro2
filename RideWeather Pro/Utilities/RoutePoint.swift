//
//  RoutePoint.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 12/8/25.
//


import Foundation
import CoreLocation

/// A point along a route with location and elevation data
struct RoutePoint: Codable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let distance: Double // Cumulative distance in meters
    
    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        elevation: Double? = nil,
        distance: Double = 0
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.distance = distance
    }
    
    /// Create from CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D, elevation: Double? = nil, distance: Double = 0) {
        self.id = UUID()
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.elevation = elevation
        self.distance = distance
    }
    
    /// Convert to CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
