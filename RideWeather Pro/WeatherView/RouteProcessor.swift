//
//  RouteProcessor.swift
//  RideWeather Pro
//
//  Fixed for Swift 6 concurrency
//

import Foundation
import MapKit

// Weather-point sampling and ETA math moved to RouteSampler
// (RouteSampling.swift): the old geometric key-point matching here silently
// dropped loop finishes and could early-match waypoints. This actor now only
// hosts the static route utilities below.
actor RouteProcessor {}

// **********new for garmin route import
// MARK: - Static Utilities (Fix for Missing Member)

extension RouteProcessor {
    /// Recalculates cumulative distances for a set of route points.
    /// Useful when importing raw coordinates that don't have distance data.
    static func recalculateDistances(for points: [EnhancedRoutePoint]) -> [EnhancedRoutePoint] {
        guard !points.isEmpty else { return [] }
        
        var processedPoints: [EnhancedRoutePoint] = []
        var cumulativeDistance: Double = 0.0
        var previousLocation: CLLocation?
        
        for point in points {
            let currentLocation = CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
            
            if let prev = previousLocation {
                let distance = currentLocation.distance(from: prev)
                cumulativeDistance += distance
            }
            
            // Reconstruct point with new cumulative distance
            let newPoint = EnhancedRoutePoint(
                coordinate: point.coordinate,
                elevation: point.elevation,
                distance: cumulativeDistance, // Update distance
                timestamp: point.timestamp
            )
            
            processedPoints.append(newPoint)
            previousLocation = currentLocation
        }
        
        return processedPoints
    }
}
