//
//  RouteProcessor.swift
//  RideWeather Pro
//
//  Fixed for Swift 6 concurrency
//

import Foundation
import MapKit

actor RouteProcessor {
    
    /// Calculates the total distance of a route from its coordinates.
/*    func getRouteSummary(from points: [CLLocationCoordinate2D]) -> (totalDistance: Double, duration: TimeInterval) {
        guard points.count > 1 else { return (0, 0) }
        
        var totalDistance: Double = 0
        for i in 1..<points.count {
            let start = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let end = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            totalDistance += end.distance(from: start)
        }
        return (totalDistance, 0)
    }*/
    
    /// Selects a number of key points along a route, always including the start and end.
/*    func selectKeyPoints(from points: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        let pointCount = points.count
        guard pointCount > maxPoints, pointCount > 2 else {
            return points
        }

        var selectedPoints = [CLLocationCoordinate2D]()
        let step = Double(pointCount - 1) / Double(maxPoints - 1)

        for i in 0..<maxPoints {
            let index = Int(round(step * Double(i)))
            if index < pointCount {
                selectedPoints.append(points[index])
            }
        }
        
        if let lastOriginal = points.last, let lastSelected = selectedPoints.last,
           (lastOriginal.latitude != lastSelected.latitude || lastOriginal.longitude != lastSelected.longitude) {
            selectedPoints.append(lastOriginal)
        }

        var uniquePoints = [CLLocationCoordinate2D]()
        var seenCoords = Set<String>()
        for point in selectedPoints {
            let coordString = "\(point.latitude),\(point.longitude)"
            if !seenCoords.contains(coordString) {
                uniquePoints.append(point)
                seenCoords.insert(coordString)
            }
        }
        
        return uniquePoints
    }*/
    

    // In your BackgroundProcessor file...

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
    
    // In your BackgroundProcessor file...

    /// Calculates the specific distances along the route where weather data should be fetched.
 /*   func calculateWeatherSampleDistances(for totalDistance: Double) -> [Double] {
        // 1. Determine the total number of segments based on route length.
        let totalSegments: Int
        let distanceInMiles = totalDistance / 1609.34
        
        if distanceInMiles < 25 {
            totalSegments = 4
        } else if distanceInMiles < 75 {
            totalSegments = 6
        } else {
            totalSegments = 8
        }
        
        // 2. Use a Set to automatically handle unique points.
        var distances = Set<Double>()
        
        // 3. Add the guaranteed sample points: start, middle, and end.
        distances.insert(0.0)
        distances.insert(totalDistance / 2.0)
        distances.insert(totalDistance)
        
        // 4. Add points for each segment boundary.
        for i in 1..<totalSegments {
            let segmentDistance = (Double(i) / Double(totalSegments)) * totalDistance
            distances.insert(segmentDistance)
        }
        
        // 5. Return a clean, sorted array of distances.
        return Array(distances).sorted()
    }*/

    /// Finds the precise coordinates on a route that correspond to a given set of distances.
/*    func findPoints(at distances: [Double], on route: [CLLocationCoordinate2D]) -> [(coordinate: CLLocationCoordinate2D, distance: Double)] {
        guard !route.isEmpty, !distances.isEmpty else { return [] }

        var resultPoints: [(coordinate: CLLocationCoordinate2D, distance: Double)] = []
        var traveledDistance: Double = 0.0
        var distanceIndex = 0
        
        // Add the starting point if requested
        if distances.first == 0.0 {
            resultPoints.append((coordinate: route.first!, distance: 0.0))
            distanceIndex += 1
        }

        for i in 1..<route.count {
            guard distanceIndex < distances.count else { break }

            let startCoord = route[i - 1]
            let endCoord = route[i]
            
            let startLoc = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
            let endLoc = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
            let segmentDistance = endLoc.distance(from: startLoc)

            while distanceIndex < distances.count && distances[distanceIndex] <= traveledDistance + segmentDistance {
                let targetDistance = distances[distanceIndex]
                let fraction = (targetDistance - traveledDistance) / segmentDistance
                
                let lat = startCoord.latitude + (endCoord.latitude - startCoord.latitude) * fraction
                let lon = startCoord.longitude + (endCoord.longitude - startCoord.longitude) * fraction
                
                resultPoints.append((coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), distance: targetDistance))
                distanceIndex += 1
            }
            traveledDistance += segmentDistance
        }
        return resultPoints
    }*/
}
