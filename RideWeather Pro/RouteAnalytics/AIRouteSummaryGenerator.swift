//
//  AIRouteSummaryGenerator.swift
//  RideWeather Pro
//
//  Complete AI-generated natural language route descriptions with caching
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Route Summary Cache Manager

class RouteSummaryCacheManager {
    static let shared = RouteSummaryCacheManager()
    
    private let cacheKey = "routeSummaryCache"
    private let geocodeKey = "geocodeCache"
    private let maxCacheAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let maxGeocodeEntries = 100 // Limit geocode cache size
    
    private init() {}
    
    // MARK: - Summary Cache
    
    /// Cache key is generated from route fingerprint (start/end coords + total distance)
    private func generateCacheKey(
        start: CLLocationCoordinate2D?,
        end: CLLocationCoordinate2D?,
        distance: Double
    ) -> String {
        let startStr = start.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "none"
        let endStr = end.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "none"
        let distStr = String(format: "%.0f", distance)
        return "\(startStr)|\(endStr)|\(distStr)"
    }
    
    func getCachedSummary(
        start: CLLocationCoordinate2D?,
        end: CLLocationCoordinate2D?,
        distance: Double
    ) -> CachedRouteSummary? {
        let key = generateCacheKey(start: start, end: end, distance: distance)
        
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: CachedRouteSummary].self, from: data),
              let cached = cache[key] else {
            return nil
        }
        
        // Check if cache is still valid
        if Date().timeIntervalSince(cached.timestamp) > maxCacheAge {
            return nil
        }
        
        return cached
    }
    
    func cacheSummary(
        _ summary: String,
        start: CLLocationCoordinate2D?,
        end: CLLocationCoordinate2D?,
        distance: Double,
        routeType: RouteType
    ) {
        let key = generateCacheKey(start: start, end: end, distance: distance)
        
        var cache: [String: CachedRouteSummary] = [:]
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let existing = try? JSONDecoder().decode([String: CachedRouteSummary].self, from: data) {
            cache = existing
        }
        
        cache[key] = CachedRouteSummary(
            summary: summary,
            routeType: routeType,
            timestamp: Date()
        )
        
        // Clean old entries
        cache = cache.filter { Date().timeIntervalSince($0.value.timestamp) <= maxCacheAge }
        
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    // MARK: - Geocode Cache
    
    private func geocodeCacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        // Round to 3 decimal places (~110m precision) for cache key
        String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
    }
    
    func getCachedLocationName(for coordinate: CLLocationCoordinate2D) -> String? {
        let key = geocodeCacheKey(for: coordinate)
        
        guard let data = UserDefaults.standard.data(forKey: geocodeKey),
              let cache = try? JSONDecoder().decode([String: CachedGeocode].self, from: data),
              let cached = cache[key] else {
            return nil
        }
        
        // Geocode cache is valid for 90 days
        if Date().timeIntervalSince(cached.timestamp) > (90 * 24 * 60 * 60) {
            return nil
        }
        
        return cached.locationName
    }
    
    func cacheLocationName(_ name: String, for coordinate: CLLocationCoordinate2D) {
        let key = geocodeCacheKey(for: coordinate)
        
        var cache: [String: CachedGeocode] = [:]
        if let data = UserDefaults.standard.data(forKey: geocodeKey),
           let existing = try? JSONDecoder().decode([String: CachedGeocode].self, from: data) {
            cache = existing
        }
        
        cache[key] = CachedGeocode(locationName: name, timestamp: Date())
        
        // Limit cache size
        if cache.count > maxGeocodeEntries {
            // Remove oldest entries
            let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
            cache = Dictionary(uniqueKeysWithValues: sorted.suffix(maxGeocodeEntries))
        }
        
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: geocodeKey)
        }
    }
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: geocodeKey)
    }
}

struct CachedRouteSummary: Codable {
    let summary: String
    let routeType: RouteType
    let timestamp: Date
}

struct CachedGeocode: Codable {
    let locationName: String
    let timestamp: Date
}

// MARK: - Route Type Detection

enum RouteType: String, Codable {
    case outAndBack = "Out-and-Back"
    case loop = "Loop"
    case pointToPoint = "Point-to-Point"
    case figure8 = "Figure-8"
    case lollipop = "Lollipop" // Out-and-back with a loop
    
    var emoji: String {
        switch self {
        case .outAndBack: return "↔️"
        case .loop: return "🔄"
        case .pointToPoint: return "➡️"
        case .figure8: return "8️⃣"
        case .lollipop: return "🍭"
        }
    }
}

// MARK: - Main Route Summary Generator

extension AIWeatherPacingInsights {
    
    /// Generates a comprehensive natural language summary of the route
    /// Uses caching to avoid repeated geocoding and analysis
    func generateRouteSummary(metadata: RideMetadata? = nil) async -> RouteSummaryResult? {
        guard let powerAnalysis = powerAnalysis,
              let elevationAnalysis = elevationAnalysis,
              !weatherPoints.isEmpty else {
            return nil
        }
        
        let totalDistance = powerAnalysis.segments.last?.endPoint.distance ?? 0
        
        // Get coordinates - prefer metadata, fallback to power analysis segments
        let startCoord = metadata?.startCoordinate ?? powerAnalysis.segments.first?.startPoint.coordinate
        let endCoord = metadata?.endCoordinate ?? powerAnalysis.segments.last?.endPoint.coordinate
        
        // Check cache first
        if let cached = RouteSummaryCacheManager.shared.getCachedSummary(
            start: startCoord,
            end: endCoord,
            distance: totalDistance
        ) {
            print("📋 Using cached route summary")
            return RouteSummaryResult(
                summary: cached.summary,
                routeType: cached.routeType,
                fromCache: true
            )
        }
        
        print("🔍 Generating new route summary...")
        
        var summary: [String] = []
        
        // 1. DETERMINE ROUTE TYPE
        let routeType = await detectRouteType(
            powerSegments: powerAnalysis.segments,
            startCoord: startCoord,
            endCoord: endCoord,
            breadcrumbs: metadata?.routeBreadcrumbs
        )
        
        // 2. START/END LOCATIONS with geocoding
        if let locationsDesc = await describeStartEndLocations(
            startCoord: startCoord,
            endCoord: endCoord,
            routeType: routeType
        ) {
            summary.append(locationsDesc)
        }
        
        // 3. ROUTE TYPE SPECIFIC DETAILS
        if let routeTypeDesc = await describeRouteTypeDetails(
            routeType: routeType,
            powerSegments: powerAnalysis.segments,
            startCoord: startCoord
        ) {
            summary.append(routeTypeDesc)
        }
        
        // 4. MAJOR CLIMBS
        let climbSummaries = describeMajorClimbs(
            powerSegments: powerAnalysis.segments,
            elevationAnalysis: elevationAnalysis
        )
        summary.append(contentsOf: climbSummaries)
        
        // 5. TERRAIN CHARACTER
        if let terrainDesc = describeOverallTerrain(
            powerSegments: powerAnalysis.segments,
            elevationAnalysis: elevationAnalysis
        ) {
            summary.append(terrainDesc)
        }
        
        let fullSummary = summary.joined(separator: ". ") + "."
        
        // Cache for future use
        RouteSummaryCacheManager.shared.cacheSummary(
            fullSummary,
            start: startCoord,
            end: endCoord,
            distance: totalDistance,
            routeType: routeType
        )
        
        return RouteSummaryResult(
            summary: fullSummary,
            routeType: routeType,
            fromCache: false
        )
    }
    
    // MARK: - Distance Formatting Helper
    
    private func formatDistance(_ meters: Double) -> String {
        if settings.units == .metric {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.1f mi", meters / 1609.34)
        }
    }
    
    // MARK: - Route Type Detection
    
    private func detectRouteType(
        powerSegments: [PowerRouteSegment],
        startCoord: CLLocationCoordinate2D?,
        endCoord: CLLocationCoordinate2D?,
        breadcrumbs: [CLLocationCoordinate2D]?
    ) async -> RouteType {
        guard let start = startCoord, let end = endCoord else {
            return .pointToPoint
        }
        
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let endDistance = endLoc.distance(from: startLoc)
        
        // 1. CHECK FOR LOOP (start and end very close)
        if endDistance < 200 { // Within 200 meters
            
            // Check if it's a figure-8 by looking at path crossings
            if let breadcrumbs = breadcrumbs, breadcrumbs.count > 20 {
                if detectFigure8(breadcrumbs: breadcrumbs) {
                    return .figure8
                }
            }
            
            return .loop
        }
        
        // 2. CHECK FOR OUT-AND-BACK
        if endDistance < 1000 { // Within 1km
            if let turnaroundInfo = detectTurnaround(
                powerSegments: powerSegments,
                breadcrumbs: breadcrumbs
            ) {
                // If we have a loop at the turnaround, it's a lollipop
                if turnaroundInfo.hasLoop {
                    return .lollipop
                }
                return .outAndBack
            }
        }
        
        // 3. DEFAULT TO POINT-TO-POINT
        return .pointToPoint
    }
    
    private func detectFigure8(breadcrumbs: [CLLocationCoordinate2D]) -> Bool {
        // Look for a point where the route crosses itself
        // This is a simplified check - in production you'd want more sophisticated geometry
        
        let midpoint = breadcrumbs.count / 2
        guard midpoint > 5 else { return false }
        
        // Check if the middle section comes close to the start/end area
        let startArea = breadcrumbs.prefix(10)
        let middlePoints = breadcrumbs[(midpoint-5)...(midpoint+5)]
        
        for middlePoint in middlePoints {
            let midLoc = CLLocation(latitude: middlePoint.latitude, longitude: middlePoint.longitude)
            
            for startPoint in startArea {
                let startLoc = CLLocation(latitude: startPoint.latitude, longitude: startPoint.longitude)
                
                // If middle section comes within 100m of start, might be figure-8
                if midLoc.distance(from: startLoc) < 100 {
                    return true
                }
            }
        }
        
        return false
    }
    
    private struct TurnaroundInfo {
        let distanceToTurnaround: Double
        let hasLoop: Bool
    }
    
    private func detectTurnaround(
        powerSegments: [PowerRouteSegment],
        breadcrumbs: [CLLocationCoordinate2D]?
    ) -> TurnaroundInfo? {
        guard powerSegments.count > 20 else { return nil }
        
        // Find the farthest point from start
        guard let start = powerSegments.first?.startPoint.coordinate else { return nil }
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        
        var maxDistance: Double = 0
        var maxDistanceIndex = 0
        var maxDistanceSegment: PowerRouteSegment?
        
        for (index, seg) in powerSegments.enumerated() {
            let segLocation = CLLocation(
                latitude: seg.startPoint.coordinate.latitude,
                longitude: seg.startPoint.coordinate.longitude
            )
            let distance = segLocation.distance(from: startLocation)
            
            if distance > maxDistance {
                maxDistance = distance
                maxDistanceIndex = index
                maxDistanceSegment = seg
            }
        }
        
        guard let turnaroundSeg = maxDistanceSegment else { return nil }
        let routeLength = powerSegments.count
        let percentThrough = Double(maxDistanceIndex) / Double(routeLength)
        
        // Out-and-back routes typically turn around between 35-65% through
        guard percentThrough > 0.35 && percentThrough < 0.65 else { return nil }
        
        // Check if there's a loop at the turnaround
        let hasLoop = checkForLoopAtTurnaround(
            segments: powerSegments,
            turnaroundIndex: maxDistanceIndex
        )
        
        return TurnaroundInfo(
            distanceToTurnaround: turnaroundSeg.startPoint.distance,
            hasLoop: hasLoop
        )
    }
    
    private func checkForLoopAtTurnaround(
        segments: [PowerRouteSegment],
        turnaroundIndex: Int
    ) -> Bool {
        // Look at segments around the turnaround point
        let windowSize = 20
        let startIdx = max(0, turnaroundIndex - windowSize)
        let endIdx = min(segments.count - 1, turnaroundIndex + windowSize)
        
        guard endIdx > startIdx + 10 else { return false }
        
        let windowSegments = segments[startIdx...endIdx]
        let coords = windowSegments.map { $0.startPoint.coordinate }
        
        // Check if path forms a loop (start and end of window are close)
        guard let first = coords.first, let last = coords.last else { return false }
        
        let firstLoc = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let lastLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
        
        // If start and end of window are within 500m, there's likely a loop
        return firstLoc.distance(from: lastLoc) < 500
    }
    
    // MARK: - Location Name with Geocoding
    
    private func locationName(for coordinate: CLLocationCoordinate2D?) async -> String? {
        guard let coord = coordinate else { return nil }
        
        // Check cache first
        if let cached = RouteSummaryCacheManager.shared.getCachedLocationName(for: coord) {
            return cached
        }
        
        // Use MKLocalSearch for reverse geocoding
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = "location"
        searchRequest.region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            
            if let mapItem = response.mapItems.first {
                let placemark = mapItem.placemark
                let name = placemark.locality ??
                          placemark.subLocality ??
                          placemark.administrativeArea ??
                          placemark.name ??
                          "this area"
                
                // Cache the result
                RouteSummaryCacheManager.shared.cacheLocationName(name, for: coord)
                
                return name
            }
        } catch {
            print("Geocoding failed: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: - Start/End Location Description
    
    private func describeStartEndLocations(
        startCoord: CLLocationCoordinate2D?,
        endCoord: CLLocationCoordinate2D?,
        routeType: RouteType
    ) async -> String? {
        
        let startName = await locationName(for: startCoord)
        let endName = await locationName(for: endCoord)
        
        guard let start = startName else { return nil }
        
        switch routeType {
        case .loop, .figure8:
            return "\(routeType.emoji) \(routeType.rawValue) route starting and finishing in \(start)"
            
        case .outAndBack, .lollipop:
            return "\(routeType.emoji) \(routeType.rawValue) route starting in \(start)"
            
        case .pointToPoint:
            if let end = endName, end != start {
                return "\(routeType.emoji) \(routeType.rawValue) route from \(start) to \(end)"
            } else {
                return "\(routeType.emoji) Route starting in \(start)"
            }
        }
    }
    
    // MARK: - Route Type Specific Details
    
    private func describeRouteTypeDetails(
        routeType: RouteType,
        powerSegments: [PowerRouteSegment],
        startCoord: CLLocationCoordinate2D?
    ) async -> String? {
        
        switch routeType {
        case .outAndBack:
            if let turnaroundInfo = detectTurnaround(
                powerSegments: powerSegments,
                breadcrumbs: nil
            ) {
                let turnaroundDist = formatDistance(turnaroundInfo.distanceToTurnaround)
                return "with a turnaround point at \(turnaroundDist)"
            }
            
        case .lollipop:
            if let turnaroundInfo = detectTurnaround(
                powerSegments: powerSegments,
                breadcrumbs: nil
            ) {
                let turnaroundDist = formatDistance(turnaroundInfo.distanceToTurnaround)
                return "featuring a loop at the \(turnaroundDist) mark before returning"
            }
            
        case .figure8:
            return "with two distinct loops meeting in the middle"
            
        case .loop, .pointToPoint:
            return nil // No special details needed
        }
        
        return nil
    }
    
    // MARK: - Climb Descriptions
    
    private func describeMajorClimbs(
        powerSegments: [PowerRouteSegment],
        elevationAnalysis: ElevationAnalysis
    ) -> [String] {
        var descriptions: [String] = []
        
        // Find all significant climbs
        struct Climb {
            let startDistance: Double
            let length: Double
            let gain: Double
            let avgGrade: Double
            let maxGrade: Double
        }
        
        var climbs: [Climb] = []
        var currentClimb: (start: Double, startIdx: Int, gain: Double, grades: [Double])? = nil
        
        for (index, seg) in powerSegments.enumerated() {
            let grade = seg.elevationGrade * 100
            let gainThisSegment = max(0, seg.elevationGrade * seg.distanceMeters)
            
            if grade > 2.5 { // Climbing
                if var climb = currentClimb {
                    climb.gain += gainThisSegment
                    climb.grades.append(grade)
                    currentClimb = climb
                } else {
                    currentClimb = (seg.startPoint.distance, index, gainThisSegment, [grade])
                }
            } else if let climb = currentClimb {
                // Climb ended
                let minGain = settings.units == .metric ? 100.0 : 91.44 // 100m or 300ft
                
                if climb.gain > minGain {
                    let endSeg = powerSegments[index]
                    let length = endSeg.startPoint.distance - climb.start
                    let avgGrade = climb.grades.reduce(0, +) / Double(climb.grades.count)
                    let maxGrade = climb.grades.max() ?? 0
                    
                    climbs.append(Climb(
                        startDistance: climb.start,
                        length: length,
                        gain: climb.gain,
                        avgGrade: avgGrade,
                        maxGrade: maxGrade
                    ))
                }
                currentClimb = nil
            }
        }
        
        // Handle climb at end of route
        if let climb = currentClimb, climb.gain > (settings.units == .metric ? 100.0 : 91.44) {
            let endSeg = powerSegments.last!
            let length = endSeg.endPoint.distance - climb.start
            let avgGrade = climb.grades.reduce(0, +) / Double(climb.grades.count)
            let maxGrade = climb.grades.max() ?? 0
            
            climbs.append(Climb(
                startDistance: climb.start,
                length: length,
                gain: climb.gain,
                avgGrade: avgGrade,
                maxGrade: maxGrade
            ))
        }
        
        // Describe the most significant climbs (top 3)
        let sortedClimbs = climbs.sorted { $0.gain > $1.gain }.prefix(3)
        
        for (index, climb) in sortedClimbs.enumerated() {
            let startDist = formatDistance(climb.startDistance)
            let climbLength = formatDistance(climb.length)
            let gainStr = settings.units == .metric ?
                "\(Int(climb.gain))m" :
                "\(Int(climb.gain * 3.28084))ft"
            
            var desc = ""
            
            // First climb gets article, others get "another"
            if index == 0 {
                desc = "There is a"
            } else {
                desc = "Another"
            }
            
            // Describe difficulty
            if climb.maxGrade > 12 {
                desc += " very steep"
            } else if climb.maxGrade > 10 {
                desc += " steep"
            } else if climb.maxGrade > 7 {
                desc += " challenging"
            } else {
                desc += " moderate"
            }
            
            desc += " climb starting at \(startDist), lasting \(climbLength)"
            desc += " with \(gainStr) of elevation gain"
            
            if climb.maxGrade > 8 {
                desc += " (max grade \(String(format: "%.0f", climb.maxGrade))%)"
            }
            
            descriptions.append(desc)
        }
        
        return descriptions
    }
    
    // MARK: - Overall Terrain Character
    
    private func describeOverallTerrain(
        powerSegments: [PowerRouteSegment],
        elevationAnalysis: ElevationAnalysis
    ) -> String? {
        let totalDistance = powerSegments.last?.endPoint.distance ?? 0
        guard totalDistance > 0 else { return nil }
        
        let totalGain = elevationAnalysis.totalGain
        let climbingDensity = (totalGain / totalDistance) * 1000 // meters per km
        
        let totalDistanceStr = formatDistance(totalDistance)
        let gainStr = settings.units == .metric ?
            "\(Int(totalGain))m" :
            "\(Int(totalGain * 3.28084))ft"
        
        if climbingDensity > 25 {
            return "The route covers \(totalDistanceStr) with \(gainStr) of climbing, making it a very hilly mountain route"
        } else if climbingDensity > 15 {
            return "The route covers \(totalDistanceStr) with \(gainStr) of climbing, featuring continuous rolling terrain"
        } else if totalGain > (settings.units == .metric ? 1000 : 3000) {
            return "The route covers \(totalDistanceStr) with \(gainStr) of climbing concentrated in specific sections"
        } else {
            return "The route covers \(totalDistanceStr) with \(gainStr) of climbing, relatively flat overall"
        }
    }
}

// MARK: - Route Summary Result

struct RouteSummaryResult {
    let summary: String
    let routeType: RouteType
    let fromCache: Bool
}
