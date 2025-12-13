//
//  RouteParser.swift with Elevation Support
//  RideWeather Pro
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
            
            // Try to get 'record' messages first (for activities)
            var messages = fitFile.messages(forMessageType: .record)
            var isCourseFile = false
            
            // If no 'record' messages, it's a Course file. Get 'course_point' messages.
            if messages.isEmpty {
                print("RouteParser: No 'record' messages found. Checking for 'course_point' messages.")

                messages = fitFile.messages(forMessageType: .course_point)
                isCourseFile = true
                if !messages.isEmpty {
                    print("RouteParser: Found \(messages.count) course_point messages.")
                }
            }

            var enhancedPoints: [EnhancedRoutePoint] = []
            var cumulativeDistance: Double = 0.0 // This will be read from the message for course files
            var previousCoordinate: CLLocationCoordinate2D?
            
            // Use the 'messages' variable (which is either records or course_points)
            for msg in messages {
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
                
                if let values = valuesDict {
                    // Try 'record' message keys first
                    var lat = values["position_lat"]
                    var lon = values["position_long"]

                    // If nil, try 'course_point' message keys
                    if lat == nil || lon == nil {
                        // Check standard course_point keys
                        lat = values["position_lat"]
                        lon = values["position_long"]
                    }
                    
                    if let lat, let lon {
                        // Convert semicircles to degrees (FIT format)
                        let latDegrees = lat * (180.0 / pow(2, 31))
                        let lonDegrees = lon * (180.0 / pow(2, 31))
                        
                        // Wahoo/Garmin sometimes use invalid 0,0 coordinates
                        if latDegrees != 0 && lonDegrees != 0 {
                            coordinate = CLLocationCoordinate2D(latitude: latDegrees, longitude: lonDegrees)
                        }
                    }
                }

                if let values = valuesDict {
                    let altitudeKeys = ["enhanced_altitude", "altitude", "enhanced_alt", "alt"]
                    var altValue: Double?
                    for altKey in altitudeKeys {
                        if let value = values[altKey] {
                            altValue = value
                            break
                        }
                    }
                    elevation = altValue
                }

                // 'record' messages usually have cumulative distance. 'course_point' messages
                // have a 'distance' field which is also cumulative.
                if let values = valuesDict, let dist = values["distance"] {
                     cumulativeDistance = dist // Read cumulative distance directly
                }

                if let dates = datesDict, let ts = dates["timestamp"] {
                    timestamp = ts
                } else if let values = valuesDict, let tsSeconds = values["timestamp"] { // course_point uses 'timestamp'
                    // FIT file timestamp is seconds since UTC 1989-12-31 00:00:00
                    let fitEpoch = Date(timeIntervalSinceReferenceDate: -347222400)
                    timestamp = Date(timeInterval: tsSeconds, since: fitEpoch)
                }
                
                // Skip if no coordinate
                guard let coord = coordinate else { continue }
                
                // If it's *not* a course file, we must calculate distance manually
                if !isCourseFile {
                    if let prevCoord = previousCoordinate {
                        let distance = calculateDistance(from: prevCoord, to: coord)
                        cumulativeDistance += distance
                    }
                }
                
                let enhancedPoint = EnhancedRoutePoint(
                    coordinate: coord,
                    elevation: elevation,
                    distance: cumulativeDistance, // This will be from the FIT msg if isCourseFile, or calculated if not
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
        
        // STEP 1: Build elevation profile first
        var elevationProfile: [ElevationPoint] = []
        var previousElevation: Double?
        
        for point in pointsWithElevation {
            guard let elevation = point.elevation else { continue }
            
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
        
        // STEP 2: Calculate gain/loss DIRECTLY from raw data with minimal filtering
        var totalGain = 0.0
        var totalLoss = 0.0
        var filteredOutGain = 0.0
        var filteredOutLoss = 0.0
        var impossibleGrades = 0
        
        for i in 1..<elevationProfile.count {
            let elevationChange = elevationProfile[i].elevation - elevationProfile[i-1].elevation
            let distanceBetweenPoints = elevationProfile[i].distance - elevationProfile[i-1].distance
            
            // Only filter out impossible grades (GPS errors)
            // Real steep grades can be 15-20%, so only filter if >35%
            if distanceBetweenPoints > 0 {
                let grade = abs(elevationChange / distanceBetweenPoints)
                
                // If grade is reasonable (<35%), count it
                if grade < 0.35 {
                    if elevationChange > 0 {
                        totalGain += elevationChange
                    } else if elevationChange < 0 {
                        totalLoss += abs(elevationChange)
                    }
                } else {
                    // Track what we're filtering out
                    impossibleGrades += 1
                    if elevationChange > 0 {
                        filteredOutGain += elevationChange
                    } else {
                        filteredOutLoss += abs(elevationChange)
                    }
                }
            }
        }
        
        // Use the RAW profile for visualization (smoothing was destroying data)
        let smoothedProfile = elevationProfile
        
        let elevations = pointsWithElevation.compactMap { $0.elevation }
        guard !elevations.isEmpty else { return nil }
        
        let elevationRange = (elevations.max() ?? 0) - (elevations.min() ?? 0)
        
        print("📊 Elevation Analysis:")
        print("   Raw points: \(pointsWithElevation.count)")
        print("   Total gain: \(Int(totalGain))m (\(Int(totalGain * 3.28084))ft)")
        print("   Total loss: \(Int(totalLoss))m (\(Int(totalLoss * 3.28084))ft)")
        print("   Max elevation: \(Int(elevations.max() ?? 0))m (\(Int((elevations.max() ?? 0) * 3.28084))ft)")
        print("   Min elevation: \(Int(elevations.min() ?? 0))m (\(Int((elevations.min() ?? 0) * 3.28084))ft)")
        print("   Elevation range: \(Int(elevationRange))m (\(Int(elevationRange * 3.28084))ft)")
        print("   Filtered impossible grades: \(impossibleGrades) points")
        print("   Filtered gain: \(Int(filteredOutGain))m, loss: \(Int(filteredOutLoss))m")
        
        return ElevationAnalysis(
            totalGain: totalGain,
            totalLoss: totalLoss,
            maxElevation: elevations.max() ?? 0,
            minElevation: elevations.min() ?? 0,
            elevationProfile: smoothedProfile,
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
