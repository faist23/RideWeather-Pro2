//
//  RouteProcessor.swift
//  RideWeather Pro
//
//  Fixed for Swift 6 concurrency
//

import Foundation
import MapKit

actor RouteProcessor {
    
    func calculateETAs(
        for keyPoints: [CLLocationCoordinate2D],
        from fullRoute: [CLLocationCoordinate2D],
        rideDate: Date,
        avgSpeed: Double
    ) -> [(coordinate: CLLocationCoordinate2D, distance: Double, eta: Date)] {
        
        guard !fullRoute.isEmpty, avgSpeed > 0 else { return [] }

        var results: [(coordinate: CLLocationCoordinate2D, distance: Double, eta: Date)] = []
        var traveledDistance: Double = 0.0
        var keyPointIndex = 0

        // Immediately add the starting point
        if !keyPoints.isEmpty {
            results.append((coordinate: fullRoute.first!, distance: 0.0, eta: rideDate))
            keyPointIndex += 1
        }

        // Iterate through the main route to calculate distances
        for i in 1..<fullRoute.count {
            guard keyPointIndex < keyPoints.count else { break }

            let prevCoord = fullRoute[i - 1]
            let currCoord = fullRoute[i]
            
            let prevLoc = CLLocation(latitude: prevCoord.latitude, longitude: prevCoord.longitude)
            let currLoc = CLLocation(latitude: currCoord.latitude, longitude: currCoord.longitude)
            let segmentDistance = currLoc.distance(from: prevLoc)

            // Check if the next key point is on this segment of the full route
            let nextKeyPoint = keyPoints[keyPointIndex]
            if isCoordinate(nextKeyPoint, onSegment: (prevCoord, currCoord)) {
                // Find the distance to this key point
                let keyPointLocation = CLLocation(latitude: nextKeyPoint.latitude, longitude: nextKeyPoint.longitude)
                let distanceToKeyPoint = traveledDistance + prevLoc.distance(from: keyPointLocation)
                
                // Calculate ETA
                let timeOffset = distanceToKeyPoint / avgSpeed
                let eta = rideDate.addingTimeInterval(timeOffset)
                
                results.append((coordinate: nextKeyPoint, distance: distanceToKeyPoint, eta: eta))
                keyPointIndex += 1
            }
            
            traveledDistance += segmentDistance
        }
        
        // A helper function to check if a point lies on a line segment
        // This is a simplified check; more complex geometry checks can be used if needed.
        func isCoordinate(_ coord: CLLocationCoordinate2D, onSegment segment: (CLLocationCoordinate2D, CLLocationCoordinate2D)) -> Bool {
            let tolerance = 0.0001 // Tolerance for floating point comparisons
            let minLat = min(segment.0.latitude, segment.1.latitude) - tolerance
            let maxLat = max(segment.0.latitude, segment.1.latitude) + tolerance
            let minLon = min(segment.0.longitude, segment.1.longitude) - tolerance
            let maxLon = max(segment.0.longitude, segment.1.longitude) + tolerance
            
            return coord.latitude >= minLat && coord.latitude <= maxLat &&
                   coord.longitude >= minLon && coord.longitude <= maxLon
        }

        return results
    }
}
