
//
//  Enhanced RouteParser.swift with Elevation Support
//

import Foundation
import CoreLocation
import CoreGPX
import FitFileParser

enum RouteParseError: Error {
    case unknownFileType
    case parsingFailed
    case noCoordinatesFound
}

// MARK: - Enhanced Route Point with Elevation
struct EnhancedRoutePoint {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double?     // in meters
    let distance: Double       // cumulative distance in meters
    let timestamp: Date?       // optional timestamp
}

// MARK: - Elevation Analysis Data
struct ElevationAnalysis {
    let totalGain: Double          // Total climbing in meters
    let totalLoss: Double          // Total descending in meters
    let maxElevation: Double       // Highest point in meters
    let minElevation: Double       // Lowest point in meters
    let elevationProfile: [ElevationPoint] // For charting
    let hasActualData: Bool        // True if from file, false if estimated
}

struct ElevationPoint {
    let distance: Double      // Distance along route in meters
    let elevation: Double     // Elevation in meters
    let grade: Double?        // Grade percentage at this point
}

// MARK: - Enhanced RouteParser
struct RouteParser: Sendable {
    
    // MARK: - Public Methods
    
    func parse(gpxData: Data) throws -> [CLLocationCoordinate2D] {
        let enhancedResult = try parseWithElevation(gpxData: gpxData)
        return enhancedResult.coordinates
    }
    
    func parse(fitData: Data) throws -> [CLLocationCoordinate2D] {
        let enhancedResult = try parseWithElevation(fitData: fitData)
        return enhancedResult.coordinates
    }
    
    func parseWithElevation(gpxData: Data) throws -> (coordinates: [CLLocationCoordinate2D], elevationAnalysis: ElevationAnalysis?) {
        guard let gpx = GPXParser(withData: gpxData).parsedData() else {
            throw RouteParseError.parsingFailed
        }
        
        var enhancedPoints: [EnhancedRoutePoint] = []
        var cumulativeDistance = 0.0
        var previousCoordinate: CLLocationCoordinate2D?

        // Parse tracks first (preferred for recorded activities)
        for track in gpx.tracks {
            for segment in track.segments {
                for point in segment.points {
                    guard let lat = point.latitude, let lon = point.longitude else { continue }
                    
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    
                    if let prevCoord = previousCoordinate {
                        let distance = calculateDistance(from: prevCoord, to: coordinate)
                        cumulativeDistance += distance
                    }
                    
                    let enhancedPoint = EnhancedRoutePoint(
                        coordinate: coordinate,
                        elevation: point.elevation,
                        distance: cumulativeDistance,
                        timestamp: point.time
                    )
                    
                    enhancedPoints.append(enhancedPoint)
                    previousCoordinate = coordinate
                }
            }
        }

        // If no tracks, try routes
        if enhancedPoints.isEmpty {
            cumulativeDistance = 0.0
            previousCoordinate = nil
            
            for route in gpx.routes {
                for point in route.points {
                    guard let lat = point.latitude, let lon = point.longitude else { continue }
                    
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    
                    if let prevCoord = previousCoordinate {
                        let distance = calculateDistance(from: prevCoord, to: coordinate)
                        cumulativeDistance += distance
                    }
                    
                    let enhancedPoint = EnhancedRoutePoint(
                        coordinate: coordinate,
                        elevation: point.elevation,
                        distance: cumulativeDistance,
                        timestamp: nil
                    )
                    
                    enhancedPoints.append(enhancedPoint)
                    previousCoordinate = coordinate
                }
            }
        }
        
        if enhancedPoints.isEmpty {
            throw RouteParseError.noCoordinatesFound
        }
        
        let coordinates = enhancedPoints.map { $0.coordinate }
        let elevationAnalysis = generateElevationAnalysis(from: enhancedPoints)
        
        return (coordinates: coordinates, elevationAnalysis: elevationAnalysis)
    }
    
    func parseWithElevation(fitData: Data) throws -> (coordinates: [CLLocationCoordinate2D], elevationAnalysis: ElevationAnalysis?) {
        let fitFile = FitFile(data: fitData)
        let records = fitFile.messages(forMessageType: .record)
        
        var enhancedPoints: [EnhancedRoutePoint] = []
        var cumulativeDistance = 0.0
        var previousCoordinate: CLLocationCoordinate2D?
        
        for msg in records {
            var coordinate: CLLocationCoordinate2D?
            var elevation: Double?
            var timestamp: Date?
            
            // Access the values dictionary directly using reflection
            let mirror = Mirror(reflecting: msg)
            var valuesDict: [String: Double]?
            var datesDict: [String: Date]?
            
            for (label, value) in mirror.children {
                if label == "values", let vDict = value as? [String: Double] {
                    valuesDict = vDict
                }
                if label == "dates", let dDict = value as? [String: Date] {
                    datesDict = dDict
                }
            }
            
            // Get coordinates from position_lat/position_long
            if let values = valuesDict,
               let lat = values["position_lat"],
               let lon = values["position_long"] {
                // Convert semicircles to degrees (FIT format)
                let latDegrees = lat * (180.0 / pow(2, 31))
                let lonDegrees = lon * (180.0 / pow(2, 31))
                coordinate = CLLocationCoordinate2D(latitude: latDegrees, longitude: lonDegrees)
            }
            
            // Try to get elevation from multiple possible keys
            if let values = valuesDict {
                let altitudeKeys = ["enhanced_altitude", "altitude", "enhanced_alt", "alt"]
                for altKey in altitudeKeys {
                    if let altValue = values[altKey] {
                        elevation = altValue
                        break
                    }
                }
            }
            
            // Get timestamp
            if let dates = datesDict {
                timestamp = dates["timestamp"]
            }
            
            // Skip if no coordinate
            guard let coord = coordinate else { continue }
            
            if let prevCoord = previousCoordinate {
                let distance = calculateDistance(from: prevCoord, to: coord)
                cumulativeDistance += distance
            }
            
            let enhancedPoint = EnhancedRoutePoint(
                coordinate: coord,
                elevation: elevation,
                distance: cumulativeDistance,
                timestamp: timestamp
            )
            
            enhancedPoints.append(enhancedPoint)
            previousCoordinate = coord
        }
        
        if enhancedPoints.isEmpty {
            throw RouteParseError.noCoordinatesFound
        }
        
        let coordinates = enhancedPoints.map { $0.coordinate }
        let elevationAnalysis = generateElevationAnalysis(from: enhancedPoints)
        
        return (coordinates: coordinates, elevationAnalysis: elevationAnalysis)
    }
    
    // MARK: - Private Helper Methods
    
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let location2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return location1.distance(from: location2)
    }
    
    private func generateElevationAnalysis(from points: [EnhancedRoutePoint]) -> ElevationAnalysis? {
        let pointsWithElevation = points.filter { $0.elevation != nil }
        
        // If less than half the points have elevation, assume unreliable
        guard pointsWithElevation.count > points.count / 2 else {
            return createEstimatedElevationAnalysis(from: points)
        }
        
        var totalGain = 0.0
        var totalLoss = 0.0
        var previousElevation: Double?
        var elevationProfile: [ElevationPoint] = []
        
        for point in pointsWithElevation {
            guard let elevation = point.elevation else { continue }
            
            if let prevElevation = previousElevation {
                let elevationChange = elevation - prevElevation
                if elevationChange > 0.2 {  //was 0.5
                    totalGain += elevationChange
                } else if elevationChange < -0.1 {
                    totalLoss += abs(elevationChange)
                }
            }
            
            var grade: Double?
            if let prevPoint = elevationProfile.last, let prevElevation = previousElevation {
                let horizontalDistance = point.distance - prevPoint.distance
                if horizontalDistance > 0 {
                    grade = ((elevation - prevElevation) / horizontalDistance) * 100
                    grade = max(-25, min(25, grade!)) // Clamp extreme values
                }
            }
            
            elevationProfile.append(ElevationPoint(
                distance: point.distance,
                elevation: elevation,
                grade: grade
            ))
            
            previousElevation = elevation
        }
        
        let elevations = pointsWithElevation.compactMap { $0.elevation }
        guard !elevations.isEmpty else { return nil }
        
        return ElevationAnalysis(
            totalGain: totalGain,
            totalLoss: totalLoss,
            maxElevation: elevations.max() ?? 0,
            minElevation: elevations.min() ?? 0,
            elevationProfile: elevationProfile,
            hasActualData: true
        )
    }
    
    private func createEstimatedElevationAnalysis(from points: [EnhancedRoutePoint]) -> ElevationAnalysis {
        guard let lastPoint = points.last else {
            return ElevationAnalysis(
                totalGain: 0,
                totalLoss: 0,
                maxElevation: 100,
                minElevation: 100,
                elevationProfile: [],
                hasActualData: false
            )
        }
        
        let totalDistanceKm = lastPoint.distance / 1000.0
        let estimatedGainPerKm = 15.0
        let estimatedTotalGain = totalDistanceKm * estimatedGainPerKm
        
        var elevationProfile: [ElevationPoint] = []
        let baseElevation = 100.0
        
        if points.count > 1 {
            for (index, point) in points.enumerated() {
                let progress = Double(index) / Double(points.count - 1)
                
                let primaryClimb = progress * estimatedTotalGain
                let variation1 = sin(progress * .pi * 3) * 20
                let variation2 = sin(progress * .pi * 12) * 5
                
                let elevation = baseElevation + primaryClimb + variation1 + variation2
                
                elevationProfile.append(ElevationPoint(
                    distance: point.distance,
                    elevation: elevation,
                    grade: nil
                ))
            }
        }
        
        return ElevationAnalysis(
            totalGain: estimatedTotalGain,
            totalLoss: estimatedTotalGain * 0.7,
            maxElevation: baseElevation + estimatedTotalGain + 25,
            minElevation: baseElevation - 15,
            elevationProfile: elevationProfile,
            hasActualData: false
        )
    }
}
extension ElevationAnalysis {
    /// Returns interpolated elevation at a given distance (in meters).
    func elevation(at distance: Double) -> Double? {
        guard !elevationProfile.isEmpty else { return nil }
        
        // Exact match
        if let exact = elevationProfile.first(where: { abs($0.distance - distance) < 1.0 }) {
            return exact.elevation
        }
        
        // Find the segment [prev, next] surrounding this distance
        if let nextIndex = elevationProfile.firstIndex(where: { $0.distance > distance }), nextIndex > 0 {
            let prev = elevationProfile[nextIndex - 1]
            let next = elevationProfile[nextIndex]
            
            let ratio = (distance - prev.distance) / (next.distance - prev.distance)
            return prev.elevation + ratio * (next.elevation - prev.elevation)
        }
        
        // If before first or after last point, clamp
        if distance <= elevationProfile.first!.distance {
            return elevationProfile.first!.elevation
        }
        if distance >= elevationProfile.last!.distance {
            return elevationProfile.last!.elevation
        }
        
        return nil
    }
}
