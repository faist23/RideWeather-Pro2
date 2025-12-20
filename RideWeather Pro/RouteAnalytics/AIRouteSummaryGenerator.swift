//
//  AIRouteSummaryGenerator.swift
//  RideWeather Pro
//
//  Advanced Route Analysis Engine
//  Fixed: File-System Caching, Directory Size Calculation, and Stricter Loop Logic
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Route Summary Cache Manager (File System Based)
class RouteSummaryCacheManager {
    static let shared = RouteSummaryCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Create a specific folder in Caches for our data
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("RouteAnalysisCache", isDirectory: true)
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Size Calculation (Requested Feature)
    func getCacheSize() -> String {
        guard let urls = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 KB"
        }
        
        var totalSize: Int64 = 0
        for url in urls {
            if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    func clearCache() {
        do {
            let urls = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for url in urls {
                try fileManager.removeItem(at: url)
            }
            print("🗑️ Cache Cleared Successfully")
        } catch {
            print("⚠️ Failed to clear cache: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Summary IO
    private func getSummaryFileURL(start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?, distance: Double) -> URL {
        // Create a unique filename hash
        let startStr = start.map { String(format: "%.4f_%.4f", $0.latitude, $0.longitude) } ?? "nil"
        let endStr = end.map { String(format: "%.4f_%.4f", $0.latitude, $0.longitude) } ?? "nil"
        let rawString = "\(startStr)-\(endStr)-\(Int(distance))"
        let filename = "summary_\(rawString.hashValue).json"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    func getCachedSummary(start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?, distance: Double) -> CachedRouteSummary? {
        let url = getSummaryFileURL(start: start, end: end, distance: distance)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedRouteSummary.self, from: data) else { return nil }
        
        // Expiry check (30 days)
        if Date().timeIntervalSince(cached.timestamp) > (30 * 24 * 60 * 60) {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return cached
    }
    
    func cacheSummary(_ summary: String, start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?, distance: Double, routeType: RouteType) {
        let url = getSummaryFileURL(start: start, end: end, distance: distance)
        let object = CachedRouteSummary(summary: summary, routeType: routeType, timestamp: Date())
        
        if let data = try? JSONEncoder().encode(object) {
            try? data.write(to: url)
        }
    }
    
    // MARK: - Geocode IO
    private func getGeocodeFileURL(for coord: CLLocationCoordinate2D) -> URL {
        let rawString = String(format: "geo_%.3f_%.3f", coord.latitude, coord.longitude)
        return cacheDirectory.appendingPathComponent("\(rawString).json")
    }
    
    func getCachedLocationName(for coord: CLLocationCoordinate2D) -> String? {
        let url = getGeocodeFileURL(for: coord)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedGeocode.self, from: data) else { return nil }
        return cached.locationName
    }
    
    func cacheLocationName(_ name: String, for coord: CLLocationCoordinate2D) {
        let url = getGeocodeFileURL(for: coord)
        let object = CachedGeocode(locationName: name, timestamp: Date())
        if let data = try? JSONEncoder().encode(object) {
            try? data.write(to: url)
        }
    }
}

struct CachedRouteSummary: Codable { let summary: String; let routeType: RouteType; let timestamp: Date }
struct CachedGeocode: Codable { let locationName: String; let timestamp: Date }
struct RouteSummaryResult { let summary: String; let routeType: RouteType; let fromCache: Bool }

enum RouteType: String, Codable {
    case outAndBack = "Out-and-Back"
    case loop = "Loop"
    case pointToPoint = "Point-to-Point"
    case figure8 = "Figure-8"
    case lollipop = "Lollipop"
    
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

// MARK: - Enhanced AI Generator

extension AIWeatherPacingInsights {
    
    func generateRouteSummary(metadata: RideMetadata? = nil) async -> RouteSummaryResult? {
        guard let powerAnalysis = powerAnalysis, let elevationAnalysis = elevationAnalysis, !weatherPoints.isEmpty else { return nil }
        
        let totalDistance = powerAnalysis.segments.last?.endPoint.distance ?? 0
        let startCoord = metadata?.startCoordinate ?? powerAnalysis.segments.first?.startPoint.coordinate
        let endCoord = metadata?.endCoordinate ?? powerAnalysis.segments.last?.endPoint.coordinate
        
        // 1. CHECK CACHE
        if let cached = RouteSummaryCacheManager.shared.getCachedSummary(start: startCoord, end: endCoord, distance: totalDistance) {
            return RouteSummaryResult(summary: cached.summary, routeType: cached.routeType, fromCache: true)
        }
        
        print("🧠 AI Engine: Analyzing Route Geometry (Polygon Method)...")
        
        // 2. DETECT ROUTE TYPE (GEOMETRIC)
        let routeType = await detectGeometricRouteType(
            powerSegments: powerAnalysis.segments,
            startCoord: startCoord,
            endCoord: endCoord,
            totalDistance: totalDistance
        )
        
        // 3. GENERATE TEXT
        var summaryComponents: [String] = []
        var locationSuccess = false
        
        // A. Start/End Description
        if let locationDesc = await describeLocationsDetailed(
            startCoord: startCoord,
            endCoord: endCoord,
            routeType: routeType,
            segments: powerAnalysis.segments
        ) {
            summaryComponents.append(locationDesc)
            locationSuccess = true
        }
        
        // B. Climbs
        let climbs = describeMajorClimbs(powerSegments: powerAnalysis.segments, elevationAnalysis: elevationAnalysis)
        summaryComponents.append(contentsOf: climbs)
        
        // C. Terrain
        if let terrain = describeOverallTerrain(powerSegments: powerAnalysis.segments, elevationAnalysis: elevationAnalysis) {
            summaryComponents.append(terrain)
        }
        
        let fullSummary = summaryComponents.joined(separator: ". ") + "."
        
        // 4. CACHE
        if locationSuccess {
            RouteSummaryCacheManager.shared.cacheSummary(fullSummary, start: startCoord, end: endCoord, distance: totalDistance, routeType: routeType)
        }
        
        return RouteSummaryResult(summary: fullSummary, routeType: routeType, fromCache: false)
    }
    
    // MARK: - High-Precision Geocoding
    
    private func getDetailedLocationName(for coordinate: CLLocationCoordinate2D?) async -> String? {
        guard let coord = coordinate else { return nil }
        
        if let cached = RouteSummaryCacheManager.shared.getCachedLocationName(for: coord) { return cached }
        
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        
        do {
            if let placemark = try await GeocodingManager.shared.reverseGeocode(location: location) {
                var details: [String] = []
                
                if let street = placemark.thoroughfare { details.append(street) }
                if let neighborhood = placemark.subLocality {
                    details.append(neighborhood)
                } else if let city = placemark.locality {
                    details.append(city)
                }
                
                if details.count == 1, let city = placemark.locality, !details.contains(city) {
                    details.append(city)
                }
                if let state = placemark.administrativeArea { details.append(state) }
                
                let name = details.joined(separator: ", ")
                
                if !name.isEmpty {
                    RouteSummaryCacheManager.shared.cacheLocationName(name, for: coord)
                    return name
                }
            }
        } catch {
            print("Geocoding Error: \(error.localizedDescription)")
        }
        return nil
    }
    
    // MARK: - Geometric Route Detection (Stricter)
    
    private func detectGeometricRouteType(
        powerSegments: [PowerRouteSegment],
        startCoord: CLLocationCoordinate2D?,
        endCoord: CLLocationCoordinate2D?,
        totalDistance: Double
    ) async -> RouteType {
        guard let start = startCoord, let end = endCoord else { return .pointToPoint }
        
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let gapDistance = endLoc.distance(from: startLoc)
        
        // 1. Point to Point Check
        if gapDistance > 1500 { return .pointToPoint }
        
        // 2. POLYGON AREA CHECK ("Shoelace Algorithm")
        let polygonPoints = powerSegments.enumerated()
            .filter { $0.offset % 10 == 0 }
            .map { $0.element.startPoint.coordinate }
        
        let area = calculatePolygonArea(coordinates: polygonPoints)
        let ratio = area / (totalDistance * totalDistance)
        
        print("📐 Geometry: Area=\(Int(area)), Ratio=\(String(format: "%.4f", ratio))")
        
        // 3. CLASSIFICATION (Adjusted Threshold)
        // Previous: 0.015. New: 0.025.
        // This forces "skinny" loops (like tight out-and-backs with drift) into the Out-and-Back bucket.
        if ratio > 0.025 {
            if detectFigure8(segments: powerSegments) {
                return .figure8
            }
            return .loop
        } else {
            // Minimal area -> Out-and-Back or Lollipop
            if detectLollipop(segments: powerSegments) {
                return .lollipop
            }
            return .outAndBack
        }
    }
    
    private func calculatePolygonArea(coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 2 else { return 0 }
        var area: Double = 0
        let kEarthRadius = 6378137.0
        
        for i in 0..<coordinates.count {
            let p1 = coordinates[i]
            let p2 = coordinates[(i + 1) % coordinates.count]
            
            let x1 = p1.longitude * .pi / 180 * kEarthRadius * cos(p1.latitude * .pi / 180)
            let y1 = p1.latitude * .pi / 180 * kEarthRadius
            
            let x2 = p2.longitude * .pi / 180 * kEarthRadius * cos(p2.latitude * .pi / 180)
            let y2 = p2.latitude * .pi / 180 * kEarthRadius
            
            area += (x1 * y2) - (x2 * y1)
        }
        return abs(area / 2.0)
    }
    
    private func detectFigure8(segments: [PowerRouteSegment]) -> Bool {
        let midIdx = segments.count / 2
        guard midIdx < segments.count else { return false }
        
        let startLoc = CLLocation(latitude: segments[0].startPoint.coordinate.latitude, longitude: segments[0].startPoint.coordinate.longitude)
        let midLoc = CLLocation(latitude: segments[midIdx].startPoint.coordinate.latitude, longitude: segments[midIdx].startPoint.coordinate.longitude)
        
        return startLoc.distance(from: midLoc) < 300
    }
    
    // MARK: - The Tuned Lollipop Logic
    
    private func detectLollipop(segments: [PowerRouteSegment]) -> Bool {
        let count = segments.count
        guard count > 50 else { return false }
        
        // 1. CHECK STICK: Start (20%) and Return (80%) must be close
        let idxStick = Int(Double(count) * 0.20)
        let idxReturn = Int(Double(count) * 0.80)
        
        let locStick = CLLocation(latitude: segments[idxStick].startPoint.coordinate.latitude, longitude: segments[idxStick].startPoint.coordinate.longitude)
        let locReturn = CLLocation(latitude: segments[idxReturn].startPoint.coordinate.latitude, longitude: segments[idxReturn].startPoint.coordinate.longitude)
        
        if locStick.distance(from: locReturn) > 250 {
            return false // Stick too wide
        }
        
        // 2. CHECK HEAD: The Loop must be SIGNIFICANT (> 600m)
        // Increased from 400m -> 600m to ignore large park turnarounds
        
        let idxTop1 = Int(Double(count) * 0.45)
        let idxTop2 = Int(Double(count) * 0.55)
        let locTop1 = CLLocation(latitude: segments[idxTop1].startPoint.coordinate.latitude, longitude: segments[idxTop1].startPoint.coordinate.longitude)
        let locTop2 = CLLocation(latitude: segments[idxTop2].startPoint.coordinate.latitude, longitude: segments[idxTop2].startPoint.coordinate.longitude)
        let distTop = locTop1.distance(from: locTop2)
        
        let idxMid1 = Int(Double(count) * 0.40)
        let idxMid2 = Int(Double(count) * 0.60)
        let locMid1 = CLLocation(latitude: segments[idxMid1].startPoint.coordinate.latitude, longitude: segments[idxMid1].startPoint.coordinate.longitude)
        let locMid2 = CLLocation(latitude: segments[idxMid2].startPoint.coordinate.latitude, longitude: segments[idxMid2].startPoint.coordinate.longitude)
        let distMid = locMid1.distance(from: locMid2)
        
        // REQUIREMENT: > 600m wide loop
        return distTop > 600 || distMid > 600
    }

    // MARK: - Detailed Descriptions
    
    private func describeLocationsDetailed(
        startCoord: CLLocationCoordinate2D?,
        endCoord: CLLocationCoordinate2D?,
        routeType: RouteType,
        segments: [PowerRouteSegment]
    ) async -> String? {
        
        guard let startName = await getDetailedLocationName(for: startCoord) else { return nil }
        
        switch routeType {
        case .outAndBack:
            if let turnaround = findTurnaroundPoint(segments: segments) {
                let turnName = await getDetailedLocationName(for: turnaround.coordinate) ?? "turnaround point"
                let turnDist = formatDistance(turnaround.distance)
                return "\(routeType.emoji) Out-and-Back route starting on \(startName). It travels to \(turnName) (at \(turnDist)) before returning"
            }
            return "\(routeType.emoji) Out-and-Back route starting on \(startName)"
            
        case .loop:
            return "\(routeType.emoji) Loop route starting and finishing on \(startName)"
            
        case .lollipop:
            return "\(routeType.emoji) Lollipop route starting on \(startName) with a loop section"
            
        case .figure8:
            return "\(routeType.emoji) Figure-8 route centered on \(startName)"
            
        case .pointToPoint:
            if let endName = await getDetailedLocationName(for: endCoord), endName != startName {
                return "\(routeType.emoji) Point-to-Point route from \(startName) to \(endName)"
            }
            return "\(routeType.emoji) Route starting on \(startName)"
        }
    }
    
    private func findTurnaroundPoint(segments: [PowerRouteSegment]) -> (coordinate: CLLocationCoordinate2D, distance: Double)? {
        guard let start = segments.first?.startPoint.coordinate else { return nil }
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        
        var maxDist: Double = 0
        var bestSeg: PowerRouteSegment?
        
        // Scan middle 50% for furthest point
        let startIdx = Int(Double(segments.count) * 0.25)
        let endIdx = Int(Double(segments.count) * 0.75)
        let searchSlice = segments[startIdx...endIdx]
        
        for seg in searchSlice {
            let loc = CLLocation(latitude: seg.startPoint.coordinate.latitude, longitude: seg.startPoint.coordinate.longitude)
            let d = loc.distance(from: startLoc)
            if d > maxDist {
                maxDist = d
                bestSeg = seg
            }
        }
        
        if let seg = bestSeg {
            return (seg.startPoint.coordinate, seg.startPoint.distance)
        }
        return nil
    }
    
    // MARK: - Helpers (Climb & Formats)
    
    private func formatDistance(_ meters: Double) -> String {
        if settings.units == .metric {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.1f mi", meters / 1609.34)
        }
    }

    private func describeMajorClimbs(
        powerSegments: [PowerRouteSegment],
        elevationAnalysis: ElevationAnalysis
    ) -> [String] {
        
        struct DetectedClimb {
            let startDistance: Double
            let length: Double
            let gain: Double
            let maxGrade: Double
        }
        
        var climbs: [DetectedClimb] = []
        var currentClimb: (start: Double, gain: Double, grades: [Double])? = nil
        
        for seg in powerSegments {
            let grade = seg.elevationGrade * 100
            let gainThisSegment = max(0, seg.elevationGrade * seg.distanceMeters)
            
            if grade > 2.5 {
                if var climb = currentClimb {
                    climb.gain += gainThisSegment
                    climb.grades.append(grade)
                    currentClimb = climb
                } else {
                    currentClimb = (seg.startPoint.distance, gainThisSegment, [grade])
                }
            } else if let climb = currentClimb {
                let minGain = settings.units == .metric ? 100.0 : 91.44
                if climb.gain > minGain {
                    let length = seg.startPoint.distance - climb.start
                    let maxGrade = climb.grades.max() ?? 0
                    climbs.append(DetectedClimb(startDistance: climb.start, length: length, gain: climb.gain, maxGrade: maxGrade))
                }
                currentClimb = nil
            }
        }
        
        let majorClimbs = climbs.sorted { $0.gain > $1.gain }.prefix(3)
        var descriptions: [String] = []
        
        for (index, climb) in majorClimbs.enumerated() {
            let startDist = formatDistance(climb.startDistance)
            let gainStr = settings.units == .metric ? "\(Int(climb.gain))m" : "\(Int(climb.gain * 3.28084))ft"
            
            var desc = index == 0 ? "There is a" : "Another"
            if climb.maxGrade > 12 { desc += " very steep" }
            else if climb.maxGrade > 10 { desc += " steep" }
            else if climb.maxGrade > 7 { desc += " challenging" }
            else { desc += " moderate" }
            
            desc += " climb starting at \(startDist) with \(gainStr) gain"
            descriptions.append(desc)
        }
        return descriptions
    }
    
    private func describeOverallTerrain(powerSegments: [PowerRouteSegment], elevationAnalysis: ElevationAnalysis) -> String? {
        let dist = powerSegments.last?.endPoint.distance ?? 1
        let gain = elevationAnalysis.totalGain
        let density = (gain / dist) * 1000
        let distStr = formatDistance(dist)
        let gainStr = settings.units == .metric ? "\(Int(gain))m" : "\(Int(gain * 3.28))ft"
        
        if density > 20 { return "The \(distStr) route is mountainous with \(gainStr) of total climbing" }
        if density > 10 { return "The \(distStr) route features rolling terrain with \(gainStr) of elevation" }
        return "The \(distStr) route is relatively flat with \(gainStr) of gain"
    }
}
