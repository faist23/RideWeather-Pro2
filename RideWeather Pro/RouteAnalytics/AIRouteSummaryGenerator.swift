//
//  AIRouteSummaryGenerator.swift
//  RideWeather Pro
//
//  Enhanced Cyclist-Focused Route Descriptions
//  - Fixed: "First Grade" phrasing (Smart omissions for unknown locations)
//  - Fixed: Lollipop false positives (Stricter geometry checks)
//  - Fixed: Loop direction (Now points to Apex, not End)
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Shared Intelligence Engine
/// A standalone engine that can analyze ANY route (Forecast or History)
actor RouteIntelligenceEngine {
    static let shared = RouteIntelligenceEngine()
    
    // MARK: - Main Generation Interface
    
    func generateSummary(
        coordinates: [CLLocationCoordinate2D],
        distance: Double,
        elevationGain: Double,
        startCoord: CLLocationCoordinate2D?,
        endCoord: CLLocationCoordinate2D?
    ) async -> RouteSummaryResult {
        
        // 0. Validation
        guard coordinates.count > 5 else {
            return RouteSummaryResult(summary: "Route data insufficient for analysis.", routeType: .pointToPoint, fromCache: false)
        }
        
        // 1. Check Cache
        if let cached = RouteSummaryCacheManager.shared.getCachedSummary(start: startCoord, end: endCoord, distance: distance) {
            return RouteSummaryResult(summary: cached.summary, routeType: cached.routeType, fromCache: true)
        }
        
        let start = startCoord ?? coordinates.first!
        let end = endCoord ?? coordinates.last!
        
        // 2. Intelligent Type Detection
        let routeType = detectRouteType(
            coordinates: coordinates,
            totalDistance: distance,
            start: start,
            end: end
        )
        
        // 3. Deep Analysis (Parallel Execution)
        async let trailAnalysis = analyzeTrailUsage(coordinates: coordinates, distance: distance)
        async let startLocation = getRichLocationName(for: start, preferStreet: false)
        async let endLocation = getRichLocationName(for: end, preferStreet: false)
        async let turnaroundInfo = findTurnaroundContext(coordinates: coordinates, start: start)
        
        // Await all results
        let (trailInfo, startDetails, endDetails, turnaround) = await (trailAnalysis, startLocation, endLocation, turnaroundInfo)
        
        // 4. Craft Professional Description
        var parts: [String] = []
        
        // -- DIRECTION LOGIC --
        // For Loops/O&B, heading is Start -> Apex. For Point-to-Point, it's Start -> End.
        let direction: String
        if routeType == .pointToPoint {
            direction = calculateGeneralDirection(coordinates: coordinates, distance: distance)
        } else if let apex = turnaround?.coordinate {
            direction = calculateBearingDetails(from: start, to: apex).cardinalDirection
        } else {
            direction = calculateGeneralDirection(coordinates: coordinates, distance: distance)
        }
        
        let emoji = routeType.emoji
        let isTrail = trailInfo.isLikelyTrail || trailInfo.primaryTrail != nil
        let pathName = trailInfo.primaryTrail ?? "bike path"
        
        // -- OPENING SENTENCE --
        // Only include Start Name if we actually found one. Don't say "From Start".
        let startPhrase = startDetails != nil ? " from \(startDetails!.shortName)" : ""
        
        switch routeType {
        case .loop:
            if isTrail {
                parts.append("\(emoji) \(pathName.capitalized) loop\(startPhrase), heading \(direction)")
            } else {
                parts.append("\(emoji) Loop route\(startPhrase), heading \(direction)")
            }
            
        case .outAndBack:
            // "Out-and-back heading West to Maple St"
            var destPhrase = ""
            if let t = turnaround, let name = t.roadName, name.lowercased() != "turnaround" {
                destPhrase = " to \(name)"
            } else if let t = turnaround, let poi = t.poi {
                destPhrase = " to \(poi)"
            }
            
            if isTrail {
                parts.append("\(emoji) Out-and-back on \(pathName)\(startPhrase), heading \(direction)\(destPhrase)")
            } else {
                parts.append("\(emoji) Out-and-back route\(startPhrase), heading \(direction)\(destPhrase)")
            }
            
        case .pointToPoint:
            let endPhrase = endDetails != nil ? " to \(endDetails!.shortName)" : ""
            parts.append("\(emoji) Point-to-point\(startPhrase)\(endPhrase), heading \(direction)")
            
        case .lollipop:
             parts.append("\(emoji) Lollipop route\(startPhrase), heading \(direction)")
            
        case .figure8:
            parts.append("\(emoji) Figure-8 route\(startPhrase)")
        }
        
        // -- TERRAIN & CHARACTER --
        let density = distance > 0 ? (elevationGain / distance) * 1000 : 0
        
        if density > 20 {
             parts.append("Features challenging climbing totaling \(Int(elevationGain))m")
        } else if density > 10 {
            parts.append("Rolling terrain with \(Int(elevationGain))m of gain")
        } else {
            parts.append("Mostly flat terrain suitable for steady pacing")
        }
        
        // Add trail note if valid and not already mentioned
        if trailInfo.isLikelyTrail && trailInfo.primaryTrail == nil && parts.first?.lowercased().contains("bike path") == false {
            parts.append("Route geometry suggests dedicated bike path")
        }
        
        let fullSummary = parts.joined(separator: ". ") + "."
        
        // 5. Cache
        RouteSummaryCacheManager.shared.cacheSummary(
            fullSummary,
            start: start,
            end: end,
            distance: distance,
            routeType: routeType
        )
        
        return RouteSummaryResult(summary: fullSummary, routeType: routeType, fromCache: false)
    }
    
    // MARK: - Geometric Detection (Strict)
    
    private func detectRouteType(
        coordinates: [CLLocationCoordinate2D],
        totalDistance: Double,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> CyclingRouteType {
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let gapDistance = endLoc.distance(from: startLoc)
        
        // 1. Check if Point-to-Point (Gap > 15% of ride)
        let p2pThreshold = max(2000, totalDistance * 0.15)
        if gapDistance > p2pThreshold {
            return .pointToPoint
        }
        
        // 2. Polygon Area Analysis (Fat vs Thin)
        let sampleStep = max(1, coordinates.count / 100)
        let polygonPoints = stride(from: 0, to: coordinates.count, by: sampleStep).map { coordinates[$0] }
        let area = calculatePolygonArea(coordinates: polygonPoints)
        
        // Ratio of Area to Length^2.
        // Pure Out-and-Back is ~0.0. Circle is ~0.16.
        let ratio = area / (totalDistance * totalDistance)
        
        // If it's extremely thin, it's Out-and-Back (ignore Lollipop check to be safe)
        if ratio < 0.005 {
            return .outAndBack
        }
        
        if ratio > 0.02 {
            // Wide Routes
            if detectFigure8(coordinates: coordinates) {
                return .figure8
            }
            return .loop
        } else {
            // Narrow Routes (0.005 - 0.02)
            if detectLollipopGeometry(coordinates: coordinates) {
                return .lollipop
            }
            return .outAndBack
        }
    }
    
    private func detectFigure8(coordinates: [CLLocationCoordinate2D]) -> Bool {
        guard coordinates.count > 50 else { return false }
        let midIdx = coordinates.count / 2
        let startLoc = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
        let midLoc = CLLocation(latitude: coordinates[midIdx].latitude, longitude: coordinates[midIdx].longitude)
        return startLoc.distance(from: midLoc) < 500
    }
    
    // FIX: Stricter Lollipop Detection
    private func detectLollipopGeometry(coordinates: [CLLocationCoordinate2D]) -> Bool {
        // If data is sparse (< 30 points), assume Out-and-Back to avoid false positives
        guard coordinates.count > 30 else { return false }
        
        // 1. Stick Check (Start/End must be retraced close together)
        let idxStickA = Int(Double(coordinates.count) * 0.15)
        let idxStickB = Int(Double(coordinates.count) * 0.85)
        
        let pStickA = CLLocation(latitude: coordinates[idxStickA].latitude, longitude: coordinates[idxStickA].longitude)
        let pStickB = CLLocation(latitude: coordinates[idxStickB].latitude, longitude: coordinates[idxStickB].longitude)
        
        if pStickA.distance(from: pStickB) > 300 {
            return false
        }
        
        // 2. Head Check (Middle must be WIDE)
        // Compare points at 40% and 60% (shoulders of the turnaround)
        let idxHeadA = Int(Double(coordinates.count) * 0.40)
        let idxHeadB = Int(Double(coordinates.count) * 0.60)
        
        let pHeadA = CLLocation(latitude: coordinates[idxHeadA].latitude, longitude: coordinates[idxHeadA].longitude)
        let pHeadB = CLLocation(latitude: coordinates[idxHeadB].latitude, longitude: coordinates[idxHeadB].longitude)
        
        let headWidth = pHeadA.distance(from: pHeadB)
        
        // Threshold increased to 800m.
        // A true loop usually has points separated by km. A messy O&B might be 300-400m apart.
        return headWidth > 800
    }
    
    // MARK: - Differential Turnaround Detection
    
    struct TurnaroundInfo {
        let coordinate: CLLocationCoordinate2D
        let distance: Double
        let roadName: String?
        let poi: String?
    }
    
    private func findTurnaroundContext(coordinates: [CLLocationCoordinate2D], start: CLLocationCoordinate2D) async -> TurnaroundInfo? {
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        var maxDist: Double = 0
        var apexIndex = 0
        
        // 1. Find Apex (Wide Scan)
        let startScan = Int(Double(coordinates.count) * 0.10)
        let endScan = Int(Double(coordinates.count) * 0.90)
        guard startScan < endScan else { return nil }
        
        for i in startScan..<endScan {
            let loc = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            let d = loc.distance(from: startLoc)
            if d > maxDist {
                maxDist = d
                apexIndex = i
            }
        }
        
        guard maxDist > 1000 else { return nil }
        let apexCoord = coordinates[apexIndex]
        
        // 2. Differential Sampling (Avoid "Parallel Roads")
        let incomingIndices = [max(0, apexIndex - 20), max(0, apexIndex - 10)]
        let apexIndices = [max(0, apexIndex - 2), apexIndex, min(coordinates.count - 1, apexIndex + 2)]
        
        var incomingNames: Set<String> = []
        var apexNames: Set<String> = []
        
        for idx in incomingIndices {
            if let details = await getRichLocationName(for: coordinates[idx], preferStreet: true) {
                incomingNames.insert(details.shortName)
            }
        }
        // Also exclude Start Location from Turnaround Candidates
        if let startDetails = await getRichLocationName(for: start, preferStreet: true) {
            incomingNames.insert(startDetails.shortName)
        }
        
        for idx in apexIndices {
            if let details = await getRichLocationName(for: coordinates[idx], preferStreet: true) {
                apexNames.insert(details.shortName)
            }
        }
        
        let uniqueTurnaroundNames = apexNames.subtracting(incomingNames)
        let candidates = uniqueTurnaroundNames.isEmpty ? apexNames : uniqueTurnaroundNames
        
        // Score: Streets > Parks > Trails > Highways
        let bestName = candidates.sorted {
            scoreLocationName($0) > scoreLocationName($1)
        }.first
        
        return TurnaroundInfo(
            coordinate: apexCoord,
            distance: maxDist,
            roadName: bestName,
            poi: nil
        )
    }
    
    private func scoreLocationName(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower.contains("turnaround") { return -1 } // Bad fallback
        if lower.contains("state route") || lower.contains("sr-") || lower.contains("hwy") { return 0 }
        if lower.contains("trail") || lower.contains("path") { return 2 } // Prefer street over trail for "To X"
        if lower.contains("park") || lower.contains("forest") { return 5 } // Park is okay but vague
        return 10 // Specific street name is best
    }
    
    // MARK: - Trail Analysis
    
    struct TrailInfo {
        let primaryTrail: String?
        let isLikelyTrail: Bool
    }
    
    private func analyzeTrailUsage(coordinates: [CLLocationCoordinate2D], distance: Double) async -> TrailInfo {
        let isGeometricallyTrail = detectTrailGeometry(coordinates: coordinates, distance: distance)
        let step = max(5, coordinates.count / 20)
        var trailCounts: [String: Int] = [:]
        
        for i in stride(from: 0, to: coordinates.count, by: step) {
            let loc = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            if let placemark = try? await GeocodingManager.shared.reverseGeocode(location: loc) {
                let candidates = [placemark.areasOfInterest?.first, placemark.thoroughfare]
                for candidate in candidates.compactMap({ $0 }) {
                    let lower = candidate.lowercased()
                    if lower.contains("trail") || lower.contains("path") || lower.contains("greenway") || lower.contains("rail") || lower.contains("bikeway") {
                        trailCounts[candidate, default: 0] += 1
                    }
                }
            }
        }
        
        if let best = trailCounts.max(by: { $0.value < $1.value }) {
            return TrailInfo(primaryTrail: best.key, isLikelyTrail: true)
        }
        return TrailInfo(primaryTrail: nil, isLikelyTrail: isGeometricallyTrail)
    }
    
    private func detectTrailGeometry(coordinates: [CLLocationCoordinate2D], distance: Double) -> Bool {
        guard coordinates.count > 10 else { return false }
        let avgSegmentLength = distance / Double(coordinates.count)
        if avgSegmentLength > 200 { return false } // Too sparse
        
        var sharpTurns = 0
        let step = max(1, coordinates.count / 50)
        
        for i in stride(from: 0, to: coordinates.count - step * 2, by: step) {
            let p1 = coordinates[i]
            let p2 = coordinates[i + step]
            let p3 = coordinates[i + step * 2]
            
            let bearing1 = calculateBearingDetails(from: p1, to: p2).degrees
            let bearing2 = calculateBearingDetails(from: p2, to: p3).degrees
            
            var diff = abs(bearing1 - bearing2)
            if diff > 180 { diff = 360 - diff }
            if diff > 60 { sharpTurns += 1 }
        }
        return sharpTurns < 3
    }
    
    // MARK: - Helper: Location Name
    
    struct LocationDetails {
        let shortName: String
        let fullName: String
    }
    
    private func getRichLocationName(for coord: CLLocationCoordinate2D, preferStreet: Bool) async -> LocationDetails? {
        if let cached = RouteSummaryCacheManager.shared.getCachedLocationName(for: coord) {
            return LocationDetails(shortName: cached.components(separatedBy: ",").first ?? cached, fullName: cached)
        }
        
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        
        do {
            if let placemark = try await GeocodingManager.shared.reverseGeocode(location: location) {
                var shortName = ""
                let poi = placemark.areasOfInterest?.first
                let street = placemark.thoroughfare
                let city = placemark.locality
                
                if preferStreet, let s = street { shortName = s }
                else if let p = poi { shortName = p }
                else if let s = street { shortName = s }
                else if let c = city { shortName = c }
                else { shortName = "Unknown" } // Will be filtered out later
                
                // Filter out numbers/zips
                if shortName.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil && shortName.count < 6 {
                    if let s = street { shortName = s }
                    else if let c = city { shortName = c }
                }
                
                if shortName == "Unknown" { return nil }
                
                let fullName = [shortName, placemark.locality].compactMap { $0 }.joined(separator: ", ")
                RouteSummaryCacheManager.shared.cacheLocationName(fullName, for: coord)
                return LocationDetails(shortName: shortName, fullName: fullName)
            }
        } catch { }
        return nil
    }
    
    // MARK: - Math Helpers
    
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
    
    private func calculateGeneralDirection(coordinates: [CLLocationCoordinate2D], distance: Double) -> String {
        guard coordinates.count > 5 else { return "North" }
        let lookahead = min(distance * 0.1, 1000)
        let start = coordinates.first!
        var target = coordinates.last!
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        
        for coord in coordinates {
            if CLLocation(latitude: coord.latitude, longitude: coord.longitude).distance(from: startLoc) > lookahead {
                target = coord
                break
            }
        }
        return calculateBearingDetails(from: start, to: target).cardinalDirection
    }
    
    private func calculateBearingDetails(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> (degrees: Double, cardinalDirection: String) {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        let degrees = (bearing + 360).truncatingRemainder(dividingBy: 360)
        
        let directions = ["North", "NE", "East", "SE", "South", "SW", "West", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        
        return (degrees, directions[index])
    }
}

// MARK: - Route Summary Result & Types

struct CachedRouteSummary: Codable { let summary: String; let routeType: CyclingRouteType; let timestamp: Date }
struct CachedGeocode: Codable { let locationName: String; let timestamp: Date }
struct RouteSummaryResult { let summary: String; let routeType: CyclingRouteType; let fromCache: Bool }

enum CyclingRouteType: String, Codable, Sendable {
    case outAndBack = "Out-and-Back"
    case loop = "Loop"
    case pointToPoint = "Point-to-Point"
    case figure8 = "Figure-8"
    case lollipop = "Lollipop"
    
    nonisolated var emoji: String {
        switch self {
        case .outAndBack: return "↔️"
        case .loop: return "🔄"
        case .pointToPoint: return "➡️"
        case .figure8: return "8️⃣"
        case .lollipop: return "🍭"
        }
    }
}

// MARK: - Route Summary Cache Manager
class RouteSummaryCacheManager {
    static let shared = RouteSummaryCacheManager()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("RouteAnalysisCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func getCacheSize() -> String {
        guard let urls = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return "0 KB" }
        var totalSize: Int64 = 0
        for url in urls {
            if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]), let fileSize = resourceValues.fileSize { totalSize += Int64(fileSize) }
        }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    func clearCache() {
        try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil).forEach { try? fileManager.removeItem(at: $0) }
    }
    
    private func getSummaryFileURL(start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?, distance: Double) -> URL {
        let startStr = start.map { String(format: "%.4f_%.4f", $0.latitude, $0.longitude) } ?? "nil"
        let endStr = end.map { String(format: "%.4f_%.4f", $0.latitude, $0.longitude) } ?? "nil"
        let rawString = "\(startStr)-\(endStr)-\(Int(distance))"
        let filename = "summary_\(rawString.hashValue).json"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    func getCachedSummary(start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?, distance: Double) -> CachedRouteSummary? {
        let url = getSummaryFileURL(start: start, end: end, distance: distance)
        guard let data = try? Data(contentsOf: url), let cached = try? JSONDecoder().decode(CachedRouteSummary.self, from: data) else { return nil }
        if Date().timeIntervalSince(cached.timestamp) > (30 * 24 * 60 * 60) { try? fileManager.removeItem(at: url); return nil }
        return cached
    }
    
    func cacheSummary(_ summary: String, start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?, distance: Double, routeType: CyclingRouteType) {
        let url = getSummaryFileURL(start: start, end: end, distance: distance)
        let object = CachedRouteSummary(summary: summary, routeType: routeType, timestamp: Date())
        if let data = try? JSONEncoder().encode(object) { try? data.write(to: url) }
    }
    
    private func getGeocodeFileURL(for coord: CLLocationCoordinate2D) -> URL {
        let rawString = String(format: "geo_%.3f_%.3f", coord.latitude, coord.longitude)
        return cacheDirectory.appendingPathComponent("\(rawString).json")
    }
    
    func getCachedLocationName(for coord: CLLocationCoordinate2D) -> String? {
        let url = getGeocodeFileURL(for: coord)
        guard let data = try? Data(contentsOf: url), let cached = try? JSONDecoder().decode(CachedGeocode.self, from: data) else { return nil }
        return cached.locationName
    }
    
    func cacheLocationName(_ name: String, for coord: CLLocationCoordinate2D) {
        let url = getGeocodeFileURL(for: coord)
        let object = CachedGeocode(locationName: name, timestamp: Date())
        if let data = try? JSONEncoder().encode(object) { try? data.write(to: url) }
    }
}

// MARK: - Extension for AIWeatherPacingInsights
extension AIWeatherPacingInsights {
    func generateRouteSummary(
        metadata: RideMetadata? = nil,
        denseCoordinates: [CLLocationCoordinate2D]? = nil
    ) async -> RouteSummaryResult? {
        
        guard !weatherPoints.isEmpty else { return nil }
        
        let coordsToUse: [CLLocationCoordinate2D]
        if let passedCoords = denseCoordinates, !passedCoords.isEmpty {
            coordsToUse = passedCoords
        } else if let powerSegments = powerAnalysis?.segments, !powerSegments.isEmpty {
            coordsToUse = powerSegments.map { $0.startPoint.coordinate }
        } else {
            coordsToUse = weatherPoints.map { $0.coordinate }
        }
        
        let totalDist = powerAnalysis?.segments.last?.endPoint.distance ?? 0
        let totalGain = elevationAnalysis?.totalGain ?? 0
        
        return await RouteIntelligenceEngine.shared.generateSummary(
            coordinates: coordsToUse,
            distance: totalDist,
            elevationGain: totalGain,
            startCoord: metadata?.startCoordinate ?? coordsToUse.first,
            endCoord: metadata?.endCoordinate ?? coordsToUse.last
        )
    }
}
