//
//  AIRouteSummaryGenerator.swift
//  RideWeather Pro
//
//  Enhanced Cyclist-Focused Route Descriptions
//  - Actual road names for turnarounds
//  - Compass directions
//  - Evocative terrain language
//  - Local landmark references
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
        
        // 1. Check Cache
        if let cached = RouteSummaryCacheManager.shared.getCachedSummary(start: startCoord, end: endCoord, distance: distance) {
            return RouteSummaryResult(summary: cached.summary, routeType: cached.routeType, fromCache: true)
        }
        
        let start = startCoord ?? coordinates.first ?? CLLocationCoordinate2D()
        let end = endCoord ?? coordinates.last ?? CLLocationCoordinate2D()
        
        // 2. Intelligent Type Detection
        let routeType = detectRouteType(
            coordinates: coordinates,
            totalDistance: distance,
            start: start,
            end: end
        )
        
        // 3. Deep Analysis
        async let trailAnalysis = analyzeTrailUsage(coordinates: coordinates)
        async let startLocation = getRichLocationName(for: start)
        async let endLocation = getRichLocationName(for: end)
        async let turnaroundInfo = (routeType == .outAndBack) ? findTurnaroundContext(coordinates: coordinates, start: start) : nil
        
        let (trailInfo, startDetails, endDetails, turnaround) = await (trailAnalysis, startLocation, endLocation, turnaroundInfo)
        
        // 4. Craft Description
        var parts: [String] = []
        
        // -- OPENING --
        let direction = calculateInitialDirection(coordinates: coordinates)
        
        if let startName = startDetails?.shortName {
            switch routeType {
            case .loop:
                if let trail = trailInfo.primaryTrail {
                    parts.append("\(routeType.emoji) \(trail) Loop from \(startName)")
                } else {
                    parts.append("\(routeType.emoji) Loop route starting and ending at \(startName)")
                }
                
            case .outAndBack:
                if let turn = turnaround {
                    // Use POI or Road Name, fallback to generic
                    let destName = turn.poi ?? turn.roadName ?? "turnaround point"
                    let distStr = formatDistance(turn.distance)
                    
                    if let trail = trailInfo.primaryTrail {
                        parts.append("\(routeType.emoji) Out-and-back on \(trail) from \(startName) to \(destName) (\(distStr))")
                    } else {
                        parts.append("\(routeType.emoji) Out-and-back ride from \(startName), heading \(direction) to \(destName)")
                    }
                } else {
                    parts.append("\(routeType.emoji) Out-and-back route from \(startName)")
                }
                
            case .pointToPoint:
                if let endName = endDetails?.shortName, endName != startName {
                    parts.append("\(routeType.emoji) Point-to-point from \(startName) to \(endName)")
                } else {
                    parts.append("\(routeType.emoji) Point-to-point route starting from \(startName)")
                }
                
            case .lollipop:
                parts.append("\(routeType.emoji) Lollipop route from \(startName) with a mid-ride loop")
                
            case .figure8:
                parts.append("\(routeType.emoji) Figure-8 route centered at \(startName)")
            }
        }
        
        // -- TERRAIN & CHARACTER --
        let density = (elevationGain / distance) * 1000
        let isHilly = density > 10
        
        if trailInfo.isLikelyTrail && trailInfo.primaryTrail == nil {
            parts.append("The geometry suggests this is primarily a dedicated bike path or rail-trail")
        }
        
        if isHilly {
            parts.append("Features significant climbing totaling \(Int(elevationGain))m")
        } else {
            parts.append("Mostly flat terrain suitable for steady pacing")
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
    
    // MARK: - Improved Geometric Detection
    
    private func detectRouteType(
        coordinates: [CLLocationCoordinate2D],
        totalDistance: Double,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> RouteType {
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let gapDistance = endLoc.distance(from: startLoc)
        
        // A 50km ride ending 2km from start is likely a loop.
        let loopThreshold = min(10000, max(2000, totalDistance * 0.10))
        
        if gapDistance > loopThreshold {
            return .pointToPoint
        }
        
        // Check for Figure-8
        if coordinates.count > 100 {
            let midIdx = coordinates.count / 2
            let midLoc = CLLocation(latitude: coordinates[midIdx].latitude, longitude: coordinates[midIdx].longitude)
            if startLoc.distance(from: midLoc) < 500 {
                return .figure8
            }
        }
        
        let polygonPoints = coordinates.enumerated().filter { $0.offset % 20 == 0 }.map { $0.element }
        let area = calculatePolygonArea(coordinates: polygonPoints)
        let ratio = area / (totalDistance * totalDistance)
        
        if ratio > 0.02 {
            return .loop
        } else if detectLollipopGeometry(coordinates: coordinates) {
            return .lollipop
        } else {
            return .outAndBack
        }
    }
    
    private func detectLollipopGeometry(coordinates: [CLLocationCoordinate2D]) -> Bool {
        guard coordinates.count > 50 else { return false }
        
        let idxStick = Int(Double(coordinates.count) * 0.25)
        let idxReturn = Int(Double(coordinates.count) * 0.75)
        
        let p1 = CLLocation(latitude: coordinates[idxStick].latitude, longitude: coordinates[idxStick].longitude)
        let p2 = CLLocation(latitude: coordinates[idxReturn].latitude, longitude: coordinates[idxReturn].longitude)
        
        return p1.distance(from: p2) < 300
    }
    
    // MARK: - Improved Turnaround Detection (FIXED: No Zip Codes)
    
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
        
        // Scan middle 60% of route
        let startScan = Int(Double(coordinates.count) * 0.2)
        let endScan = Int(Double(coordinates.count) * 0.8)
        
        for i in startScan..<endScan {
            let loc = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            let d = loc.distance(from: startLoc)
            if d > maxDist {
                maxDist = d
                apexIndex = i
            }
        }
        
        guard maxDist > 0 else { return nil }
        let apexCoord = coordinates[apexIndex]
        
        // Use rich location to get verified name (No Zips)
        let details = await getRichLocationName(for: apexCoord)
        
        // You can check your TurnaroundInfo struct definition.
        // If it requires roadName and poi separately:
        return TurnaroundInfo(
            coordinate: apexCoord,
            distance: maxDist,
            roadName: details?.shortName,
            poi: nil // details.shortName handles the best name (POI or Road)
        )
    }
    // MARK: - Trail Analysis
    
    struct TrailInfo {
        let primaryTrail: String?
        let isLikelyTrail: Bool
    }
    
    private func analyzeTrailUsage(coordinates: [CLLocationCoordinate2D]) async -> TrailInfo {
        let step = max(10, coordinates.count / 15)
        var trailCounts: [String: Int] = [:]
        
        for i in stride(from: 0, to: coordinates.count, by: step) {
            let loc = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            if let placemark = try? await GeocodingManager.shared.reverseGeocode(location: loc) {
                let candidates = [placemark.thoroughfare, placemark.areasOfInterest?.first]
                for candidate in candidates.compactMap({ $0 }) {
                    let lower = candidate.lowercased()
                    if lower.contains("trail") || lower.contains("path") || lower.contains("greenway") || lower.contains("rail") {
                        trailCounts[candidate, default: 0] += 1
                    }
                }
            }
        }
        
        if let best = trailCounts.max(by: { $0.value < $1.value }) {
            if best.value >= 2 {
                return TrailInfo(primaryTrail: best.key, isLikelyTrail: true)
            }
        }
        
        return TrailInfo(primaryTrail: nil, isLikelyTrail: false)
    }
    
    // MARK: - Helper: Location Name (FIXED: Improved Fallbacks)
    
    struct LocationDetails {
        let shortName: String
        let fullName: String
    }
    
    private func getRichLocationName(for coord: CLLocationCoordinate2D) async -> LocationDetails? {
        if let cached = RouteSummaryCacheManager.shared.getCachedLocationName(for: coord) {
            return LocationDetails(shortName: cached.components(separatedBy: ",").first ?? cached, fullName: cached)
        }
        
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        
        do {
            if let placemark = try await GeocodingManager.shared.reverseGeocode(location: location) {
                var parts: [String] = []
                var shortName = ""
                
                // 1. Try Area of Interest (Park, Trail)
                if let poi = placemark.areasOfInterest?.first {
                    shortName = poi
                    parts.append(poi)
                    if let city = placemark.locality { parts.append(city) }
                }
                // 2. Try Street Address
                else if let street = placemark.thoroughfare {
                    shortName = street
                    parts.append(street)
                    if let city = placemark.locality { parts.append(city) }
                }
                // 3. Fallback to Name (STRICT VALIDATION)
                else if let rawName = placemark.name {
                    // Check if it's a zip code or just numbers
                    let isDigits = CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: rawName))
                    let isZip = rawName == placemark.postalCode
                    
                    if !isDigits && !isZip {
                        shortName = rawName
                        parts.append(rawName)
                        if let city = placemark.locality { parts.append(city) }
                    } else {
                        // It's a zip code or number, skip it and use city
                        if let city = placemark.locality {
                            shortName = city
                            parts.append(city)
                        } else {
                            shortName = "Unknown Location"
                        }
                    }
                }
                // 4. Locality
                else if let city = placemark.locality {
                    shortName = city
                    parts.append(city)
                }
                
                // Add state/admin area
                if let state = placemark.administrativeArea {
                    parts.append(state)
                }
                
                let fullName = parts.joined(separator: ", ")
                
                if !fullName.isEmpty {
                    RouteSummaryCacheManager.shared.cacheLocationName(fullName, for: coord)
                    // Simple logic for details - you can expand this if your struct requires more fields
                    return LocationDetails(shortName: shortName, fullName: fullName)
                }
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
    
    private func calculateInitialDirection(coordinates: [CLLocationCoordinate2D]) -> String {
        guard coordinates.count > 5 else { return "North" }
        let start = coordinates[0]
        let end = coordinates[min(10, coordinates.count-1)]
        let dLon = (end.longitude - start.longitude)
        let y = sin(dLon) * cos(end.latitude)
        let x = cos(start.latitude) * sin(end.latitude) - sin(start.latitude) * cos(end.latitude) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        let directions = ["North", "NE", "East", "SE", "South", "SW", "West", "NW"]
        let index = Int(((bearing + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45.0) % 8
        return directions[index]
    }
    
    private func formatDistance(_ meters: Double) -> String {
        return String(format: "%.1f km", meters / 1000)
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

// MARK: - Route Summary Cache Manager (File System Based)
class RouteSummaryCacheManager {
    static let shared = RouteSummaryCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("RouteAnalysisCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Size Calculation (Required for SettingsView)
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
    
    // MARK: - Clear Cache (Required for SettingsView)
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
        
        // Expire after 30 days
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

// MARK: - Enhanced AI Generator

extension AIWeatherPacingInsights {
    
    func generateRouteSummary(metadata: RideMetadata? = nil) async -> RouteSummaryResult? {
        guard !weatherPoints.isEmpty else { return nil }
        
        // FIX: Prefer dense power segments over sparse weather points
        // This gives the Engine 100x more points to analyze for turns/loops
        let denseCoords = powerAnalysis?.segments.map { $0.startPoint.coordinate }
        let coords = (denseCoords?.count ?? 0) > 10 ? denseCoords! : weatherPoints.map { $0.coordinate }
        
        let totalDist = powerAnalysis?.segments.last?.endPoint.distance ?? 0
        let totalGain = elevationAnalysis?.totalGain ?? 0
        
        return await RouteIntelligenceEngine.shared.generateSummary(
            coordinates: coords,
            distance: totalDist,
            elevationGain: totalGain,
            startCoord: metadata?.startCoordinate ?? coords.first,
            endCoord: metadata?.endCoordinate ?? coords.last
        )
    }
    
    // MARK: - Cyclist-Focused Opening Description
    
    private func craftOpeningDescription(
        startCoord: CLLocationCoordinate2D?,
        endCoord: CLLocationCoordinate2D?,
        routeType: RouteType,
        segments: [PowerRouteSegment]
    ) async -> String? {
        
        guard let start = startCoord else { return nil }
        
        // Check if route is primarily on a single trail
        let trailInfo = await analyzeTrailUsage(segments: segments)
        
        // Get start location details
        guard let startDetails = await getRichLocationName(for: start) else {
            return nil
        }
        let direction = calculateInitialDirection(segments: segments)
        
        switch routeType {
        case .outAndBack:
            // Find turnaround point with road name
            if let turnaround = await findTurnaroundWithRoadName(segments: segments) {
                let turnDist = formatDistance(turnaround.distance)
                
                // If we have an explicit trail name
                if let trail = trailInfo.primaryTrail {
                    if let roadName = turnaround.roadName {
                        return "\(routeType.emoji) Out-and-back on \(trail), starting from \(startDetails.shortName), heading \(direction) to \(roadName) (\(turnDist))"
                    } else {
                        return "\(routeType.emoji) Out-and-back on \(trail), starting from \(startDetails.shortName), heading \(direction) for \(turnDist)"
                    }
                }
                
                // If geometry suggests trail but no name
                if trailInfo.isLikelyTrail {
                    if let roadName = turnaround.roadName {
                        return "\(routeType.emoji) Out-and-back on dedicated bike path from \(startDetails.shortName), heading \(direction) to \(roadName) (\(turnDist))"
                    } else {
                        return "\(routeType.emoji) Out-and-back on dedicated bike path from \(startDetails.shortName), heading \(direction) for \(turnDist)"
                    }
                }
                
                // Standard road-based out-and-back
                if let roadName = turnaround.roadName {
                    return "\(routeType.emoji) Head \(direction) from \(startDetails.shortName) to \(roadName) (\(turnDist)), then return the same way"
                } else {
                    return "\(routeType.emoji) Head \(direction) from \(startDetails.shortName) for \(turnDist) before turning back"
                }
            }
            
            // Fallback with trail if available
            if let trail = trailInfo.primaryTrail {
                return "\(routeType.emoji) Out-and-back on \(trail), starting from \(startDetails.shortName)"
            }
            if trailInfo.isLikelyTrail {
                return "\(routeType.emoji) Out-and-back on dedicated bike path from \(startDetails.shortName)"
            }
            
            return "\(routeType.emoji) Out-and-back ride starting from \(startDetails.shortName)"
            
        case .loop:
            let loopCharacter = analyzeLoopCharacter(segments: segments)
            
            // If primarily on a trail
            if let trail = trailInfo.primaryTrail {
                return "\(routeType.emoji) \(loopCharacter) loop on \(trail), starting from \(startDetails.shortName)"
            }
            
            return "\(routeType.emoji) \(loopCharacter) loop starting and finishing at \(startDetails.shortName)"
            
        case .lollipop:
            if let loopStart = findLoopStartPoint(segments: segments) {
                let loopDist = formatDistance(loopStart.distance)
                
                // Trail-based lollipop
                if let trail = trailInfo.primaryTrail {
                    return "\(routeType.emoji) Out-and-back on \(trail) from \(startDetails.shortName) with a loop section at \(loopDist)"
                }
                
                return "\(routeType.emoji) Head \(direction) from \(startDetails.shortName) to a loop section at \(loopDist), then return"
            }
            return "\(routeType.emoji) Lollipop route from \(startDetails.shortName) with a loop section"
            
        case .figure8:
            if let trail = trailInfo.primaryTrail {
                return "\(routeType.emoji) Figure-8 route on \(trail), centered at \(startDetails.shortName)"
            }
            return "\(routeType.emoji) Figure-8 route centered on \(startDetails.shortName)"
            
        case .pointToPoint:
            if let end = endCoord,
               let endDetails = await getRichLocationName(for: end),
               endDetails.shortName != startDetails.shortName {
                
                // Trail-based point-to-point
                if let trail = trailInfo.primaryTrail {
                    return "\(routeType.emoji) Point-to-point on \(trail) from \(startDetails.shortName) to \(endDetails.shortName)"
                }
                
                return "\(routeType.emoji) Point-to-point from \(startDetails.shortName) to \(endDetails.shortName), heading \(direction)"
            }
            return "\(routeType.emoji) Route starting from \(startDetails.shortName), heading \(direction)"
        }
    }
    
    // MARK: - Trail Usage Analysis
    
    private struct TrailAnalysis {
        let primaryTrail: String?
        let trailPercentage: Double
        let isLikelyTrail: Bool // New: geometric detection
    }
    
    private func analyzeTrailUsage(segments: [PowerRouteSegment]) async -> TrailAnalysis {
        guard segments.count > 10 else {
            return TrailAnalysis(primaryTrail: nil, trailPercentage: 0, isLikelyTrail: false)
        }
        
        // APPROACH 1: Try to find trail names via geocoding
        var trailNames: [String] = []
        let sampleCount = min(15, segments.count)
        let step = max(1, segments.count / sampleCount)
        
        print("🔍 Analyzing trail usage: sampling \(sampleCount) points over \(segments.count) segments...")
        
        for i in stride(from: 0, to: segments.count, by: step) {
            let coord = segments[i].startPoint.coordinate
            if let name = await getTrailOrRoadName(for: coord) {
                print("  📍 Sample \(i/step + 1): Found '\(name)'")
                trailNames.append(name)
            } else {
                print("  ⚠️ Sample \(i/step + 1): No name found")
            }
            
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // Check for trail names in geocoding results
        var foundTrailName: String?
        if !trailNames.isEmpty {
            var nameCounts: [String: Int] = [:]
            for name in trailNames {
                nameCounts[name, default: 0] += 1
            }
            
            print("  📊 Name frequency:")
            for (name, count) in nameCounts.sorted(by: { $0.value > $1.value }).prefix(3) {
                let pct = Int(Double(count) * 100.0 / Double(trailNames.count))
                print("    - '\(name)': \(count)/\(trailNames.count) (\(pct)%)")
            }
            
            // Look for explicit trail names
            for (name, count) in nameCounts {
                let lowerName = name.lowercased()
                if lowerName.contains("trail") ||
                   lowerName.contains("path") ||
                   lowerName.contains("greenway") ||
                   lowerName.contains("bikeway") {
                    let percentage = Double(count) / Double(trailNames.count)
                    if percentage >= 0.3 { // Only need 30% if it has "trail" in the name
                        foundTrailName = name
                        print("  ✅ Found trail name: '\(name)' (\(Int(percentage * 100))%)")
                        break
                    }
                }
            }
        }
        
        // APPROACH 2: Geometric detection for "trail-like" routes
        let isLikelyTrail = detectTrailLikeGeometry(segments: segments)
        
        if foundTrailName != nil {
            return TrailAnalysis(primaryTrail: foundTrailName, trailPercentage: 1.0, isLikelyTrail: true)
        } else if isLikelyTrail {
            print("  🛤️ Route geometry suggests dedicated trail/path (but no name found)")
            return TrailAnalysis(primaryTrail: nil, trailPercentage: 0, isLikelyTrail: true)
        } else {
            print("  ℹ️ Standard road route")
            return TrailAnalysis(primaryTrail: nil, trailPercentage: 0, isLikelyTrail: false)
        }
    }
    
    // MARK: - Geometric Trail Detection
    
    private func detectTrailLikeGeometry(segments: [PowerRouteSegment]) -> Bool {
        guard segments.count > 20 else { return false }
        
        // Trails often have:
        // 1. Very few sharp turns (smooth, flowing geometry)
        // 2. Consistent direction over long stretches
        // 3. Not aligned to street grid
        
        var significantTurns = 0
        var bearingChanges: [Double] = []
        
        for i in 1..<min(segments.count, 50) { // Sample first 50 segments
            let prev = segments[i-1].startPoint.coordinate
            let curr = segments[i].startPoint.coordinate
            
            if i > 1 {
                let prevPrev = segments[i-2].startPoint.coordinate
                let bearing1 = calculateBearing(from: prevPrev, to: prev)
                let bearing2 = calculateBearing(from: prev, to: curr)
                
                var change = abs(bearing2 - bearing1)
                if change > 180 { change = 360 - change }
                
                bearingChanges.append(change)
                
                // Count turns > 45 degrees (street corners)
                if change > 45 {
                    significantTurns += 1
                }
            }
        }
        
        let avgBearingChange = bearingChanges.isEmpty ? 0 : bearingChanges.reduce(0, +) / Double(bearingChanges.count)
        
        // Trail characteristics:
        // - Average bearing change < 15° (smooth curves)
        // - Fewer than 3 sharp turns in first 50 segments
        let isTrailLike = avgBearingChange < 15 && significantTurns < 3
        
        if isTrailLike {
            print("  📐 Geometry: avg turn \(String(format: "%.1f", avgBearingChange))°, sharp turns: \(significantTurns) → Trail-like")
        } else {
            print("  📐 Geometry: avg turn \(String(format: "%.1f", avgBearingChange))°, sharp turns: \(significantTurns) → Road-like")
        }
        
        return isTrailLike
    }
    
    private func getTrailOrRoadName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            if let placemark = try await GeocodingManager.shared.reverseGeocode(location: location) {
                // PRIORITY 1: Areas of interest (trails, parks)
                if let poi = placemark.areasOfInterest?.first {
                    return poi
                }
                // PRIORITY 2: Check thoroughfare for trail names
                if let road = placemark.thoroughfare {
                    // Even if it's a "road", if it has trail keywords, prefer it
                    let lowerRoad = road.lowercased()
                    if lowerRoad.contains("trail") ||
                       lowerRoad.contains("path") ||
                       lowerRoad.contains("greenway") ||
                       lowerRoad.contains("bikeway") {
                        return road
                    }
                    // Return regular road name too
                    return road
                }
                // FALLBACK: Area name
                if let area = placemark.subLocality ?? placemark.locality {
                    return area
                }
            }
        } catch {
            // Rate limiting is expected - silently skip
        }
        
        return nil
    }
    
    private struct LocationDetails {
        let shortName: String // "Alum Creek Trail" or "Schiller Park" or "Downtown Columbus"
        let fullName: String  // "Alum Creek Trail, Columbus, OH"
        let hasStreet: Bool
        let hasPointOfInterest: Bool // Trail, park, or landmark
    }
    
    private func getRichLocationName(for coordinate: CLLocationCoordinate2D) async -> LocationDetails? {
        // Check cache first
        if let cached = RouteSummaryCacheManager.shared.getCachedLocationName(for: coordinate) {
            return parseLocationDetails(from: cached)
        }
        
        // Geocode
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            if let placemark = try await GeocodingManager.shared.reverseGeocode(location: location) {
                var parts: [String] = []
                var shortName = ""
                var hasStreet = false
                var hasPointOfInterest = false
                
                // PRIORITY 1: Points of Interest (trails, parks, landmarks)
                if let poi = placemark.areasOfInterest?.first {
                    shortName = poi
                    parts.append(poi)
                    hasPointOfInterest = true
                    
                    // Add neighborhood for context (not just city)
                    if let neighborhood = placemark.subLocality {
                        parts.append(neighborhood)
                    } else if let city = placemark.locality {
                        parts.append(city)
                    }
                }
                // PRIORITY 2: Street + Neighborhood (better than just city)
                else if let street = placemark.thoroughfare {
                    shortName = street
                    parts.append(street)
                    hasStreet = true
                    
                    // Add neighborhood for specificity
                    if let neighborhood = placemark.subLocality {
                        shortName = "\(street), \(neighborhood)"
                        parts.append(neighborhood)
                    } else if let city = placemark.locality {
                        parts.append(city)
                    }
                }
                // PRIORITY 3: Neighborhood (better than just city)
                else if let neighborhood = placemark.subLocality {
                    shortName = neighborhood
                    parts.append(neighborhood)
                    
                    if let city = placemark.locality {
                        parts.append(city)
                    }
                }
                // FALLBACK: Just city
                else if let city = placemark.locality {
                    shortName = city
                    parts.append(city)
                }
                
                // Add state for full name
                if let state = placemark.administrativeArea {
                    parts.append(state)
                }
                
                let fullName = parts.joined(separator: ", ")
                
                if !fullName.isEmpty {
                    RouteSummaryCacheManager.shared.cacheLocationName(fullName, for: coordinate)
                    return LocationDetails(
                        shortName: shortName,
                        fullName: fullName,
                        hasStreet: hasStreet,
                        hasPointOfInterest: hasPointOfInterest
                    )
                }
            }
        } catch {
            print("⚠️ Geocoding skipped: \(error.localizedDescription)")
        }
        
        // Return nil instead of fallback - let caller handle it
        return nil
    }
    
    private func parseLocationDetails(from cached: String) -> LocationDetails {
        let parts = cached.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        let shortName = parts.first ?? cached
        
        // Detect if it's a point of interest (trails, parks often have these keywords)
        let poiKeywords = ["trail", "park", "creek", "river", "lake", "forest", "preserve", "greenway"]
        let hasPointOfInterest = poiKeywords.contains { shortName.lowercased().contains($0) }
        
        let hasStreet = parts.count >= 2 && !hasPointOfInterest
        
        return LocationDetails(
            shortName: shortName,
            fullName: cached,
            hasStreet: hasStreet,
            hasPointOfInterest: hasPointOfInterest
        )
    }
    
    // MARK: - Direction Calculation
    
    private func calculateInitialDirection(segments: [PowerRouteSegment]) -> String {
        guard segments.count >= 5 else { return "" }
        
        // Average bearing over first 5 segments for stability
        let start = segments[0].startPoint.coordinate
        var bearings: [Double] = []
        
        for i in 1...min(5, segments.count - 1) {
            let end = segments[i].startPoint.coordinate
            let bearing = calculateBearing(from: start, to: end)
            bearings.append(bearing)
        }
        
        let avgBearing = bearings.reduce(0, +) / Double(bearings.count)
        return bearingToCardinal(avgBearing)
    }
    
    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
    
    private func bearingToCardinal(_ bearing: Double) -> String {
        let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let index = Int((bearing + 22.5) / 45.0) % 8
        return directions[index]
    }
    
    // MARK: - Turnaround Detection with Road Name
    
    private struct TurnaroundPoint {
        let coordinate: CLLocationCoordinate2D
        let distance: Double
        let roadName: String?
    }
    
    private func findTurnaroundWithRoadName(segments: [PowerRouteSegment]) async -> TurnaroundPoint? {
        guard let start = segments.first?.startPoint.coordinate else { return nil }
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        
        var maxDist: Double = 0
        var bestSeg: PowerRouteSegment?
        
        // Search middle 50% for furthest point
        let startIdx = Int(Double(segments.count) * 0.25)
        let endIdx = Int(Double(segments.count) * 0.75)
        let searchSlice = segments[startIdx..<endIdx]
        
        print("🔍 Finding turnaround point...")
        
        for seg in searchSlice {
            let loc = CLLocation(latitude: seg.startPoint.coordinate.latitude, longitude: seg.startPoint.coordinate.longitude)
            let d = loc.distance(from: startLoc)
            if d > maxDist {
                maxDist = d
                bestSeg = seg
            }
        }
        
        guard let turnaroundSeg = bestSeg else {
            print("  ⚠️ No turnaround segment found")
            return nil
        }
        
        print("  📍 Turnaround at \(formatDistance(turnaroundSeg.startPoint.distance))")
        
        // Get road name at turnaround
        let roadName = await getRoadName(for: turnaroundSeg.startPoint.coordinate)
        
        if let name = roadName {
            print("  ✅ Turnaround location: \(name)")
        } else {
            print("  ℹ️ No specific turnaround name found")
        }
        
        return TurnaroundPoint(
            coordinate: turnaroundSeg.startPoint.coordinate,
            distance: turnaroundSeg.startPoint.distance,
            roadName: roadName
        )
    }
    
    private func getRoadName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            if let placemark = try await GeocodingManager.shared.reverseGeocode(location: location) {
                // Prefer thoroughfare (road name)
                if let road = placemark.thoroughfare {
                    print("  🛣️ Found road: \(road)")
                    return road
                }
                // Fallback to area name
                if let area = placemark.subLocality ?? placemark.locality {
                    print("  📍 Found area: \(area)")
                    return area
                }
                // Check for POI
                if let poi = placemark.areasOfInterest?.first {
                    print("  🏞️ Found POI: \(poi)")
                    return poi
                }
            }
        } catch {
            print("  ⚠️ Geocoding failed: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: - Loop Character Analysis
    
    private func analyzeLoopCharacter(segments: [PowerRouteSegment]) -> String {
        let totalGain = segments.reduce(0.0) { sum, seg in
            sum + max(0, seg.elevationGrade * seg.distanceMeters)
        }
        let distance = segments.last?.endPoint.distance ?? 1
        let density = (totalGain / distance) * 1000
        
        if density > 20 {
            return "Challenging mountainous"
        } else if density > 12 {
            return "Rolling"
        } else if density > 6 {
            return "Gently rolling"
        } else {
            return "Fast, flat"
        }
    }
    
    // MARK: - Loop Start Detection (for Lollipop)
    
    private func findLoopStartPoint(segments: [PowerRouteSegment]) -> (distance: Double, coordinate: CLLocationCoordinate2D)? {
        let count = segments.count
        guard count > 50 else { return nil }
        
        // Loop typically starts around 40% mark for lollipop
        let loopStartIdx = Int(Double(count) * 0.40)
        guard loopStartIdx < segments.count else { return nil }
        
        let seg = segments[loopStartIdx]
        return (seg.startPoint.distance, seg.startPoint.coordinate)
    }
    
    // MARK: - Named Climbs with Road Context and Mountain Passes
    
    private func describeNamedClimbs(
        powerSegments: [PowerRouteSegment],
        elevationAnalysis: ElevationAnalysis
    ) async -> [String] {
        
        struct DetectedClimb {
            let startDistance: Double
            let endDistance: Double
            let startCoordinate: CLLocationCoordinate2D
            let peakCoordinate: CLLocationCoordinate2D
            let length: Double
            let gain: Double
            let maxGrade: Double
            let peakElevation: Double
        }
        
        var climbs: [DetectedClimb] = []
        var currentClimb: (start: Double, startCoord: CLLocationCoordinate2D, gain: Double, grades: [Double], peakElev: Double, peakCoord: CLLocationCoordinate2D)? = nil
        
        // Use elevation profile from elevationAnalysis
        let elevationProfile = elevationAnalysis.elevationProfile
        
        for (index, seg) in powerSegments.enumerated() {
            let grade = seg.elevationGrade * 100
            let gainThisSegment = max(0, seg.elevationGrade * seg.distanceMeters)
            
            // Get elevation from profile if available, otherwise estimate
            let currentElevation: Double
            if index < elevationProfile.count {
                currentElevation = elevationProfile[index].elevation
            } else {
                // Fallback: estimate based on previous elevation + gain
                currentElevation = (currentClimb?.peakElev ?? 0) + gainThisSegment
            }
            
            if grade > 2.5 {
                if var climb = currentClimb {
                    climb.gain += gainThisSegment
                    climb.grades.append(grade)
                    // Track highest point in this climb
                    if currentElevation > climb.peakElev {
                        climb.peakElev = currentElevation
                        climb.peakCoord = seg.startPoint.coordinate
                    }
                    currentClimb = climb
                } else {
                    currentClimb = (seg.startPoint.distance, seg.startPoint.coordinate, gainThisSegment, [grade], currentElevation, seg.startPoint.coordinate)
                }
            } else if let climb = currentClimb {
                let minGain = settings.units == .metric ? 100.0 : 91.44
                if climb.gain > minGain {
                    let endDistance = seg.startPoint.distance
                    let length = endDistance - climb.start
                    let maxGrade = climb.grades.max() ?? 0
                    climbs.append(DetectedClimb(
                        startDistance: climb.start,
                        endDistance: endDistance,
                        startCoordinate: climb.startCoord,
                        peakCoordinate: climb.peakCoord,
                        length: length,
                        gain: climb.gain,
                        maxGrade: maxGrade,
                        peakElevation: climb.peakElev
                    ))
                }
                currentClimb = nil
            }
        }
        
        let majorClimbs = climbs.sorted { $0.gain > $1.gain }.prefix(3)
        var descriptions: [String] = []
        var usedRoadNames = Set<String>() // Track roads to avoid duplicates
        
        for (index, climb) in majorClimbs.enumerated() {
            let climbLengthStr = formatDistance(climb.length)
            let gainStr = settings.units == .metric ? "\(Int(climb.gain))m" : "\(Int(climb.gain * 3.28084))ft"
            
            // Check if this is a mountain pass (high elevation + significant gain)
            let isMountainPass = climb.peakElevation > (settings.units == .metric ? 2000 : 6562) && climb.gain > (settings.units == .metric ? 400 : 1312)
            
            var roadName: String?
            var passName: String?
            
            if isMountainPass {
                // Try to get pass name from peak
                passName = await getMountainPassName(for: climb.peakCoordinate)
                // If no pass name, try road name at base
                if passName == nil {
                    roadName = await getRoadName(for: climb.startCoordinate)
                }
            } else {
                // Standard climb - get road name
                roadName = await getRoadName(for: climb.startCoordinate)
            }
            
            // Skip if we already mentioned this road
            if let road = roadName, usedRoadNames.contains(road.lowercased()) {
                continue
            }
            
            // Build evocative description
            var desc = index == 0 ? "The main challenge is" : "Another climb"
            
            // Add location context
            if let pass = passName {
                desc += " to \(pass)"
                usedRoadNames.insert(pass.lowercased())
            } else if let road = roadName {
                desc += " on \(road)"
                usedRoadNames.insert(road.lowercased())
            } else {
                let startDist = formatDistance(climb.startDistance)
                desc += " at \(startDist)"
            }
            
            // Characterize the climb with LENGTH AND GAIN
            if isMountainPass {
                let peakElevStr = settings.units == .metric ?
                    String(format: "%.0fm", climb.peakElevation) :
                    String(format: "%.0fft", climb.peakElevation * 3.28084)
                desc += ": \(gainStr) over \(climbLengthStr) to \(peakElevStr)"
            } else if climb.maxGrade > 12 {
                desc += ": \(gainStr) of steep climbing over \(climbLengthStr)"
            } else if climb.maxGrade > 10 {
                desc += ": \(gainStr) of sustained climbing over \(climbLengthStr)"
            } else if climb.maxGrade > 7 {
                desc += ": \(gainStr) at a steady gradient over \(climbLengthStr)"
            } else {
                desc += ": \(gainStr) of gradual climbing over \(climbLengthStr)"
            }
            
            if climb.maxGrade > 10 {
                desc += " (max \(Int(climb.maxGrade))%)"
            }
            
            descriptions.append(desc)
        }
        
        return descriptions
    }
    
    // MARK: - Mountain Pass Detection
    
    private func getMountainPassName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        print("  🏔️ Checking for mountain pass...")
        
        do {
            if let placemark = try await GeocodingManager.shared.reverseGeocode(location: location) {
                // Look for pass names in areas of interest
                if let poi = placemark.areasOfInterest?.first {
                    let lowerPOI = poi.lowercased()
                    if lowerPOI.contains("pass") || lowerPOI.contains("summit") || lowerPOI.contains("col") {
                        print("  ✅ Found pass in POI: \(poi)")
                        return poi
                    }
                }
                
                // Check for pass keywords in name
                if let name = placemark.name {
                    let lowerName = name.lowercased()
                    if lowerName.contains("pass") || lowerName.contains("summit") {
                        print("  ✅ Found pass in name: \(name)")
                        return name
                    }
                }
                
                // Also check thoroughfare (some passes are roads)
                if let road = placemark.thoroughfare {
                    let lowerRoad = road.lowercased()
                    if lowerRoad.contains("pass") {
                        print("  ✅ Found pass in road: \(road)")
                        return road
                    }
                }
                
                print("  ℹ️ No pass keywords found")
            }
        } catch {
            print("  ⚠️ Pass geocoding failed: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: - Terrain Character (More Evocative)
    
    private func describeTerrainCharacter(
        powerSegments: [PowerRouteSegment],
        elevationAnalysis: ElevationAnalysis,
        routeType: RouteType
    ) -> String? {
        let dist = powerSegments.last?.endPoint.distance ?? 1
        let gain = elevationAnalysis.totalGain
        let density = (gain / dist) * 1000
        let distStr = formatDistance(dist)
        let gainStr = settings.units == .metric ? "\(Int(gain))m" : "\(Int(gain * 3.28))ft"
        
        // Count descent sections for character
        let descents = powerSegments.filter { $0.elevationGrade < -0.03 }.count
        let hasSignificantDescents = Double(descents) / Double(powerSegments.count) > 0.2
        
        if density > 20 {
            return "This \(distStr) mountain route packs in \(gainStr) of climbing"
        } else if density > 12 {
            if hasSignificantDescents {
                return "Expect \(gainStr) of climbing over \(distStr) with fast descents between"
            } else {
                return "The \(distStr) route rolls continuously with \(gainStr) of elevation change"
            }
        } else if density > 6 {
            return "A \(distStr) ride with gentle rollers totaling \(gainStr)"
        } else {
            if routeType == .outAndBack {
                return "The \(distStr) route is mostly flat (\(gainStr) total), perfect for speed work"
            } else {
                return "Fast and flat for \(distStr) with just \(gainStr) of climbing"
            }
        }
    }
    
    // MARK: - Geometric Route Detection (Unchanged)
    
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
        
        if gapDistance > 1500 { return .pointToPoint }
        
        let polygonPoints = powerSegments.enumerated()
            .filter { $0.offset % 10 == 0 }
            .map { $0.element.startPoint.coordinate }
        
        let area = calculatePolygonArea(coordinates: polygonPoints)
        let ratio = area / (totalDistance * totalDistance)
        
        if ratio > 0.025 {
            if detectFigure8(segments: powerSegments) {
                return .figure8
            }
            return .loop
        } else {
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
    
    private func detectLollipop(segments: [PowerRouteSegment]) -> Bool {
        let count = segments.count
        guard count > 50 else { return false }
        
        // STRICTER: Check stick sections at 20% and 80%
        let idxStick = Int(Double(count) * 0.20)
        let idxReturn = Int(Double(count) * 0.80)
        
        let locStick = CLLocation(latitude: segments[idxStick].startPoint.coordinate.latitude, longitude: segments[idxStick].startPoint.coordinate.longitude)
        let locReturn = CLLocation(latitude: segments[idxReturn].startPoint.coordinate.latitude, longitude: segments[idxReturn].startPoint.coordinate.longitude)
        
        // Stick must be VERY close (150m instead of 250m)
        if locStick.distance(from: locReturn) > 150 {
            return false
        }
        
        // NEW: Also check 30% and 70% to ensure entire stick is tight
        let idxStick2 = Int(Double(count) * 0.30)
        let idxReturn2 = Int(Double(count) * 0.70)
        let locStick2 = CLLocation(latitude: segments[idxStick2].startPoint.coordinate.latitude, longitude: segments[idxStick2].startPoint.coordinate.longitude)
        let locReturn2 = CLLocation(latitude: segments[idxReturn2].startPoint.coordinate.latitude, longitude: segments[idxReturn2].startPoint.coordinate.longitude)
        
        if locStick2.distance(from: locReturn2) > 150 {
            return false
        }
        
        // Check loop head width - must be SIGNIFICANT (800m instead of 600m)
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
        
        // Require 800m+ width to be a true lollipop loop
        return distTop > 800 || distMid > 800
    }
    
    // MARK: - Helper: Format Distance
    
    private func formatDistance(_ meters: Double) -> String {
        if settings.units == .metric {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.1f mi", meters / 1609.34)
        }
    }
}
