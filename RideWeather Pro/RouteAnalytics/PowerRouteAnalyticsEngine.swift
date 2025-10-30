//
//  PowerRouteAnalyticsEngine.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation

// -----------------------------
// MARK: - Public Data Types
// -----------------------------

struct PowerRouteSegment {
    let startPoint: RouteWeatherPoint
    let endPoint: RouteWeatherPoint
    let distanceMeters: Double
    let elevationGrade: Double // decimal (0.05 = 5%)
    let averageHeadwindMps: Double
    let averageCrosswindMps: Double
    let averageTemperatureC: Double
    let averageHumidity: Double
    let calculatedSpeedMps: Double
    let timeSeconds: Double
    let powerRequired: Double // watts
    let segmentType: PowerRouteSegment.SegmentType

    enum SegmentType: String, Codable {  // ADD: String, Codable
        case climb = "climb"
        case descent = "descent"
        case flat = "flat"
        case rolling = "rolling"  // ADD this case if used elsewhere

        var description: String {
            switch self {
            case .climb: return "Climb"
            case .descent: return "Descent"
            case .flat: return "Flat"
            case .rolling: return "Rolling"  // ADD this
            }
        }

        static func from(grade: Double) -> SegmentType {
            if grade > 0.035 { return .climb }      // Steeper threshold for climb
            if grade < -0.025 { return .descent }   // Threshold for descent
            if abs(grade) > 0.015 { return .rolling } // ADD: Rolling terrain
            return .flat
        }
    }
}

struct PowerRouteAnalysisResult {
    let segments: [PowerRouteSegment]
    let totalTimeSeconds: Double
    let averageSpeedMps: Double
    let totalEnergyKilojoules: Double
    let powerDistribution: PowerDistribution
    let comparisonWithTraditional: SpeedComparisonResult
    let terrainBreakdown: TerrainBreakdown

    var totalTimeMinutes: Double { totalTimeSeconds / 60.0 }
    var averageSpeedUserUnits: Double { averageSpeedMps * 3.6 } // km/h (convert further in UI)
    
    static var empty: PowerRouteAnalysisResult {
        .init(
            segments: [],
            totalTimeSeconds: 0,
            averageSpeedMps: 0,
            totalEnergyKilojoules: 0,
            powerDistribution: .empty,
            comparisonWithTraditional: .init(traditionalTimeMinutes: 0, powerBasedTimeMinutes: 0, timeDifferenceMinutes: 0, significantSegments: []),
            terrainBreakdown: .init(flatDistanceMeters: 0, climbingDistanceMeters: 0, descendingDistanceMeters: 0, averageClimbGrade: 0, averageDescentGrade: 0, steepestClimbGrade: 0, steepestDescentGrade: 0)
        )
    }

}

struct PowerDistribution {
    let averagePower: Double
    let normalizedPower: Double
    let timeInZones: PowerZones
    let intensityFactor: Double

    static var empty: PowerDistribution {
        .init(averagePower: 0, normalizedPower: 0, timeInZones: .init(zone1Seconds: 0, zone2Seconds: 0, zone3Seconds: 0, zone4Seconds: 0, zone5Seconds: 0), intensityFactor: 0)
    }
    
    struct PowerZones {
        let zone1Seconds: Double
        let zone2Seconds: Double
        let zone3Seconds: Double
        let zone4Seconds: Double
        let zone5Seconds: Double
    }
}

struct SpeedComparisonResult {
    let traditionalTimeMinutes: Double
    let powerBasedTimeMinutes: Double
    let timeDifferenceMinutes: Double
    let significantSegments: [String]

    var improvementPercentage: Double {
        guard traditionalTimeMinutes > 0 else { return 0 }
        return ((traditionalTimeMinutes - powerBasedTimeMinutes) / traditionalTimeMinutes) * 100.0
    }
}

struct TerrainBreakdown {
    let flatDistanceMeters: Double
    let climbingDistanceMeters: Double
    let descendingDistanceMeters: Double
    let averageClimbGrade: Double
    let averageDescentGrade: Double
    let steepestClimbGrade: Double
    let steepestDescentGrade: Double
}

// -----------------------------
// MARK: - Engine
// -----------------------------

final class PowerRouteAnalyticsEngine {
    private let weatherPoints: [RouteWeatherPoint] // sparse anchors (coordinate, distance, eta, weather)
    private let settings: AppSettings
    private let elevationAnalysis: ElevationAnalysis?
    private let physicsEngine: PowerPhysicsEngine

    // segmentation config
//    private let segmentTargetLength: Double = 100.0
//    private let minimumSegmentLength: Double = 75.0

    // Adaptive segmentation config
    private let flatSegmentLength: Double = 400.0      // 🔧 Increased from 100m
    private let climbSegmentLength: Double = 400.0     // 🔧 Increased from 250m
    private let descentSegmentLength: Double = 250.0   // 🔧 Increased from 150m
    private let minimumSegmentLength: Double = 100.0   // 🔧 Increased from 50m

    init(weatherPoints: [RouteWeatherPoint],
         settings: AppSettings,
         elevationAnalysis: ElevationAnalysis?) {
        self.weatherPoints = weatherPoints
        self.settings = settings
        self.elevationAnalysis = elevationAnalysis
        self.physicsEngine = PowerPhysicsEngine(settings: settings)
    }
    
    // MARK: - Public API
        func analyzePowerBasedRoute() -> PowerRouteAnalysisResult {
            guard let first = weatherPoints.first, let last = weatherPoints.last else { return .empty }

            var segments: [PowerRouteSegment] = []
            var finalPowerDistribution: PowerDistribution = .empty
            
            let initialTotalDistance = last.distance - first.distance
            var estimatedDurationHours = max(0.1, initialTotalDistance / 25_000.0)
            
            // Loop to converge on a stable Normalized Power and time
            for i in 0..<3 {
                let ftp = Double(settings.functionalThresholdPower)
                // ✅ FIX: Capture totalGain here to pass it to the validation function later
                let totalClimb = elevationAnalysis?.totalGain ?? 0.0
                let totalDistanceKm = (last.distance - first.distance) / 1000.0
                let targetIF = intensityFactor(for: estimatedDurationHours,
                                               totalClimbMeters: totalClimb,
                                               distanceKm: totalDistanceKm)
                let targetNP = ftp * targetIF

                segments = createPowerSegments(targetNormalizedPower: targetNP)
                
                validatePowerOutput(segments: segments)

                guard !segments.isEmpty else { break }
                
                finalPowerDistribution = calculatePowerDistribution(segments: segments)
                let totalTimeSeconds = segments.reduce(0.0) { $0 + $1.timeSeconds }
                estimatedDurationHours = totalTimeSeconds / 3600.0
                print(String(format: "✅ Adjusted route IF: %.2f (NP %.0f W)",
                             targetIF, targetNP))

                #if DEBUG
                print("➡️ Iteration \(i+1): Target NP = \(Int(targetNP))W, Resulting NP = \(Int(finalPowerDistribution.normalizedPower))W, Resulting Time = \(estimatedDurationHours.formatted(.number.precision(.fractionLength(2))))h")
                #endif
            }
            
            let totalTime = segments.reduce(0.0) { $0 + $1.timeSeconds }
            let totalDistance = segments.reduce(0.0) { $0 + $1.distanceMeters }
            let terrainBreakdown = calculateTerrainBreakdown(segments: segments)
            
            let coastingAdjustment = calculateCoastingAdjustment(segments: segments, terrain: terrainBreakdown)
            let adjustedTotalTime = totalTime + coastingAdjustment
            
            let avgSpeed = adjustedTotalTime > 0 ? totalDistance / adjustedTotalTime : 0
            let totalEnergy = calculateTotalEnergyKilojoules(segments: segments)
            let comparison = compareWithTraditionalMethod(totalDistance: totalDistance, powerBasedTime: adjustedTotalTime)

            // ✅ FIX: Pass the actual totalGain to the validation function
            let validatedTime = validateTimeEstimate(
                totalTimeSeconds: adjustedTotalTime,
                totalDistanceMeters: totalDistance,
                elevationGain: self.elevationAnalysis?.totalGain ?? 0.0
            )
        
            let finalAvgSpeed = validatedTime > 0 ? totalDistance / validatedTime : 0
            
            return PowerRouteAnalysisResult(
                segments: segments,
                totalTimeSeconds: validatedTime,
                averageSpeedMps: finalAvgSpeed,
                totalEnergyKilojoules: totalEnergy,
                powerDistribution: finalPowerDistribution,
                comparisonWithTraditional: comparison,
                terrainBreakdown: terrainBreakdown
            )
        }
    
    /// Returns target Intensity Factor (IF) adjusted for ride duration and total climbing difficulty.
    /// - Parameters:
    ///   - hours: estimated ride duration
    ///   - totalClimbMeters: total elevation gain of the route
    ///   - distanceKm: total route distance
    private func intensityFactor(for hours: Double,
                                 totalClimbMeters: Double,
                                 distanceKm: Double) -> Double {
        // Base IF by duration (Coggan-inspired)
        let baseIF: Double
        switch hours {
        case 0..<1.0:  baseIF = 0.95
        case 1.0..<1.5: baseIF = 0.90
        case 1.5..<2.0: baseIF = 0.87
        case 2.0..<3.0: baseIF = 0.84
        case 3.0..<5.0: baseIF = 0.80
        case 5.0..<6.0: baseIF = 0.75
        default:        baseIF = 0.70
        }

        // --- Terrain penalty ---
        // Compute climbing intensity as vertical-meters per km (m/km)
        let climbDensity = distanceKm > 0 ? totalClimbMeters / distanceKm : 0.0
        // Typical road rides: 5–15 m/km; mountain routes: 20–40 m/km+
        var terrainPenalty: Double = 0.0
        if climbDensity > 15 {
            // each +5 m/km above 15 reduces IF by about 1.5 %
            terrainPenalty = min(0.15, ((climbDensity - 15) / 5.0) * 0.015)
        }

        // --- Combined result ---
        let adjustedIF = baseIF * (1.0 - terrainPenalty)

        #if DEBUG
        print(String(format:
            "🎯 IntensityFactor: base=%.2f  climbDensity=%.1f m/km  penalty=−%.1f %% → adjusted=%.2f",
            baseIF, climbDensity, terrainPenalty*100, adjustedIF))
        #endif

        return adjustedIF
    }

    /// Calculates an additional time adjustment to account for coasting on descents.
    /// - Parameters:
    ///   - segments: The array of all route segments.
    ///   - terrain: The terrain breakdown of the route.
    /// - Returns: Additional time in seconds to add to the total estimate.
    private func calculateCoastingAdjustment(segments: [PowerRouteSegment], terrain: TerrainBreakdown) -> Double {
        let totalTime = segments.reduce(0) { $0 + $1.timeSeconds }
        let totalDistance = segments.reduce(0) { $0 + $1.distanceMeters }
        
        guard totalDistance > 0 else { return 0 }
        
        // Find the total time spent on descents
        let descentTime = segments.filter { $0.segmentType == .descent }
                                   .reduce(0) { $0 + $1.timeSeconds }
        
        // Heuristic: Assume a percentage of descent time is spent coasting (zero power).
        // A hilly route will have more coasting.
        let descentPercentage = terrain.descendingDistanceMeters / totalDistance
        
        // A simple model: for every 10% of the ride that is downhill,
        // assume 5% of that downhill time is spent coasting.
        let coastingFactor = (descentPercentage / 0.10) * 0.05
        
        let adjustment = descentTime * coastingFactor
        
        print("⏱️ Coasting Adjustment: Adding \(String(format: "%.1f", adjustment / 60)) minutes for descents.")
        
        return adjustment
    }
    
    // MARK: - Realistic Power Adjustment (NEW)
    /// Returns realistic target power based on terrain, conditions, and rider capability

    private func adjustedSegmentPower(
        baseTarget: Double,
        grade: Double,
        ftp: Double,
        segmentDistance: Double,
        totalDistance: Double,
        roughDurationHours: Double,
        cumulativeClimbDistance: Double,
        headwindMps: Double
    ) -> Double {
        
        let zone2 = ftp * 0.75  // Endurance
        let zone3 = ftp * 0.90  // Tempo
        let threshold = ftp * 1.00  // Threshold
        let vo2max = ftp * 1.15     // VO2 Max
        
        var targetPower: Double

        // ✅ NEW, SMARTER LOGIC
        // Handle special cases first.
        if grade < -0.03 && headwindMps > 3.0 {
            // SPECIAL CASE: Descent WITH a moderate/strong headwind. You must pedal.
            targetPower = zone3
            print("   💨⬇️ DESCENT w/ HEADWIND: Maintaining Tempo power.")
        } else if grade > 0.08 { // STEEP CLIMBS (>8%)
            if segmentDistance < 300 { targetPower = vo2max }
            else { targetPower = threshold * 1.05 }
        } else if grade > 0.035 { // MODERATE CLIMBS (3.5-8%)
            targetPower = threshold
        } else if grade > -0.03 { // FLATS & ROLLERS (-3% to 3.5%)
            targetPower = zone3
        } else { // DESCENTS (<-3%) with no significant headwind
            targetPower = zone2 * 0.8 // Target low-endurance/high-recovery
        }
        
        // Apply duration-based fatigue
        let rideDurationFactor: Double
        switch roughDurationHours {
        case 0..<1.5: rideDurationFactor = 1.02 // Slightly higher for short rides
        case 1.5..<2.5: rideDurationFactor = 1.00
        case 2.5..<4.0: rideDurationFactor = 0.97
        default: rideDurationFactor = 0.94
        }
        targetPower *= rideDurationFactor

        // Apply continuous climb fatigue
        if cumulativeClimbDistance > 800 && grade > 0.03 {
            let climbFatigue = min(0.10, (cumulativeClimbDistance - 800) / 4000.0 * 0.10)
            targetPower *= (1.0 - climbFatigue)
        }

        // Final safety clamping
        let absoluteMin = (grade < -0.04) ? ftp * 0.45 : ftp * 0.60
        let absoluteMax = ftp * 1.25
        targetPower = max(absoluteMin, min(targetPower, absoluteMax))
        
        return targetPower
    }

    // MARK: - Debug Helper (NEW)
    /// Debug function to validate power calculations
    private func validatePowerOutput(segments: [PowerRouteSegment]) {
        let ftp = Double(settings.functionalThresholdPower)
        guard ftp > 0, !segments.isEmpty else { return }
        
        let totalTime = segments.reduce(0.0) { $0 + $1.timeSeconds }
        let totalDistance = segments.reduce(0.0) { $0 + $1.distanceMeters }
        
        let avgSpeed = (totalDistance / totalTime) * 3.6  // km/h
        let powerStats = segments.map { $0.powerRequired }
        let avgPower = powerStats.reduce(0, +) / Double(powerStats.count)
        
        print("\n🔍 POWER VALIDATION:")
        print("   Average Speed: \(String(format: "%.1f", avgSpeed)) km/h")
        print("   Average Power: \(Int(avgPower))W (\(Int(avgPower/ftp*100))% FTP)")
        print("   Power Range: \(Int(powerStats.min() ?? 0))W - \(Int(powerStats.max() ?? 0))W")
        print("   Total Time: \(String(format: "%.1f", totalTime/3600)) hours")
        
        if avgPower < ftp * 0.65 { print("   ⚠️ WARNING: Average power seems too conservative!") }
        if avgPower > ftp * 0.95 { print("   ⚠️ WARNING: Average power may be unsustainable!") }
    }

    private func createPowerSegments(targetNormalizedPower: Double) -> [PowerRouteSegment] {
        guard weatherPoints.count > 1 else { return [] }

        print("🚀 ADAPTIVE SEGMENTATION ACTIVE")
        print("   Flat: \(flatSegmentLength)m | Climb: \(climbSegmentLength)m | Descent: \(descentSegmentLength)m")

        var resultSegments: [PowerRouteSegment] = []

        let totalDistance = weatherPoints.last!.distance - weatherPoints.first!.distance
        let roughDurationHours = max(0.1, totalDistance / 25000.0)
        let ftp = Double(settings.functionalThresholdPower)

        var cumulativeClimbDistance: Double = 0.0
        var lastWasClimb = false

        for i in 1..<weatherPoints.count {
            let a = weatherPoints[i - 1]
            let b = weatherPoints[i]
            let interval = b.distance - a.distance
            if interval <= 0 { continue }

            let roughGrade = estimateIntervalGrade(startPoint: a, endPoint: b, distance: interval)
            let targetSegmentLength = chooseSegmentLength(for: roughGrade, interval: interval)

            let subCount = max(1, Int(ceil(interval / targetSegmentLength)))
            let subLen = interval / Double(subCount)

            for k in 0..<subCount {
                let subStartDist = a.distance + Double(k) * subLen
                let subEndDist = min(b.distance, subStartDist + subLen)
                guard let subStart = interpolateRouteWeatherPoint(at: subStartDist),
                      let subEnd = interpolateRouteWeatherPoint(at: subEndDist) else { continue }

                let subDistance = subEndDist - subStartDist
                if subDistance < 1.0 { continue }
                let grade = calculateElevationGrade(startPoint: subStart, endPoint: subEnd, distance: subDistance)

                if grade > 0.02 {
                    if lastWasClimb { cumulativeClimbDistance += subDistance }
                    else {
                        cumulativeClimbDistance = subDistance
                        lastWasClimb = true
                    }
                } else {
                    cumulativeClimbDistance = 0
                    lastWasClimb = false
                }

                let nearestWeather = nearestWeather(for: subStart.coordinate)
                let tempC = convertToCelsius(nearestWeather.weather.temp)
                let humidity = Double(nearestWeather.weather.humidity)
                let bearing = calculateBearing(from: subStart.coordinate, to: subEnd.coordinate)

                let headwind = physicsEngine.calculateHeadwindComponent(
                    windSpeedMps: convertToMps(nearestWeather.weather.windSpeed),
                    windDirectionDegrees: Double(nearestWeather.weather.windDeg),
                    rideDirectionDegrees: bearing
                )
                let crosswind = physicsEngine.calculateCrosswindComponent(
                    windSpeedMps: convertToMps(nearestWeather.weather.windSpeed),
                    windDirectionDegrees: Double(nearestWeather.weather.windDeg),
                    rideDirectionDegrees: bearing
                )

                let startElev = elevationAnalysis?.elevation(at: subStart.distance) ?? 0
                let endElev = elevationAnalysis?.elevation(at: subEnd.distance) ?? 0
                let midAltitude = (startElev + endElev) / 2.0
                let airDensityKgM3 = airDensity(atAltitudeMeters: midAltitude, temperatureC: tempC)

                // ✅ REPLACED: Use the new intelligent power allocation model.
                let segmentPower = adjustedSegmentPower(
                    baseTarget: targetNormalizedPower,
                    grade: grade,
                    ftp: ftp,
                    segmentDistance: subDistance,
                    totalDistance: totalDistance,
                    roughDurationHours: roughDurationHours,
                    cumulativeClimbDistance: cumulativeClimbDistance,
                    headwindMps: headwind
                )
                
                let isWet = nearestWeather.weather.pop >= 0.4

                let speed = physicsEngine.calculateSpeed(
                    targetPowerWatts: segmentPower,
                    elevationGrade: grade,
                    headwindSpeedMps: headwind,
                    crosswindSpeedMps: crosswind,
                    temperature: tempC,
                    humidity: humidity,
                    airDensity: airDensityKgM3,
                    isWet: isWet
                )

                let time = subDistance > 0 ? subDistance / speed : 0
            
                let segment = PowerRouteSegment(
                    startPoint: subStart,
                    endPoint: subEnd,
                    distanceMeters: subDistance,
                    elevationGrade: grade,
                    averageHeadwindMps: headwind,
                    averageCrosswindMps: crosswind,
                    averageTemperatureC: tempC,
                    averageHumidity: humidity,
                    calculatedSpeedMps: speed,
                    timeSeconds: time,
                    powerRequired: segmentPower,
                    segmentType: PowerRouteSegment.SegmentType.from(grade: grade)
                )

                resultSegments.append(segment)
            }
        }

        let mergedSegments = optimizeSegmentation(segments: resultSegments)
        print("✅ After merging: \(mergedSegments.count) segments\n")

        return mergedSegments
    }

    // MARK: - Ultra-Aggressive Sustained Climb Merging

    private func mergeSustainedClimbs(segments: [PowerRouteSegment]) -> [PowerRouteSegment] {
        guard !segments.isEmpty else { return [] }
        
        var merged: [PowerRouteSegment] = []
        var climbBuffer: [PowerRouteSegment] = []
        
        // Ultra-aggressive configuration for rolling terrain
        let minClimbGrade = 0.018           // 1.8% minimum (was 2.0%)
        let gradeVarianceTolerance = 0.045  // ±4.5% variance (was 3.5%)
        let minSustainedDistance = 200.0    // Lower threshold (was 250m)
        let maxNonClimbDistance = 300.0     // Allow 300m of interruption (was 200m)
        let maxNonClimbSegments = 6         // Allow up to 6 segments (was 4)
        
        // For gentle rolling terrain, be extra lenient
        let gentleGradeThreshold = 0.03     // Grades under 3% are "gentle"
        let gentleGradeVarianceTolerance = 0.055  // Even more lenient for gentle grades
        
        func isClimbing(_ segment: PowerRouteSegment) -> Bool {
            return segment.elevationGrade > minClimbGrade
        }
        
        func averageGrade(_ segments: [PowerRouteSegment]) -> Double {
            guard !segments.isEmpty else { return 0 }
            return segments.map { $0.elevationGrade }.reduce(0, +) / Double(segments.count)
        }
        
        func isSimilarGrade(to referenceGrade: Double, segment: PowerRouteSegment) -> Bool {
            let isGentle = referenceGrade < gentleGradeThreshold
            let tolerance = isGentle ? gentleGradeVarianceTolerance : gradeVarianceTolerance
            
            // For gentle grades, be super lenient
            if isGentle && segment.elevationGrade > minClimbGrade {
                return abs(segment.elevationGrade - referenceGrade) <= tolerance
            }
            
            return abs(segment.elevationGrade - referenceGrade) <= tolerance
        }
        
        func shouldMerge() -> Bool {
            let totalDist = climbBuffer.reduce(0.0) { $0 + $1.distanceMeters }
            
            // Always merge if reasonably long
            if totalDist >= 350 { return true }
            
            // For shorter climbs, check quality
            if totalDist < minSustainedDistance { return false }
            
            let grades = climbBuffer.map { $0.elevationGrade }
            let avgGrade = grades.reduce(0, +) / Double(grades.count)
            let variance = grades.map { pow($0 - avgGrade, 2) }.reduce(0, +) / Double(grades.count)
            let stdDev = sqrt(variance)
            
            // For gentle rolling terrain (most of your route), be very lenient
            if avgGrade < 0.035 && stdDev < 0.05 { return true }
            
            // Steep climbs: more lenient on variance
            if avgGrade > 0.05 && stdDev < 0.04 { return true }
            
            // Moderate climbs: still pretty lenient
            if avgGrade > 0.03 && stdDev < 0.035 { return true }
            
            return false
        }
        
        func flushClimbBuffer() {
            guard !climbBuffer.isEmpty else { return }
            
            if !shouldMerge() {
                merged.append(contentsOf: climbBuffer)
                climbBuffer.removeAll()
                return
            }
            
            // Single long segment
            if climbBuffer.count == 1 {
                merged.append(climbBuffer[0])
                climbBuffer.removeAll()
                return
            }
            
            // Merge the climb
            let totalDist = climbBuffer.reduce(0.0) { $0 + $1.distanceMeters }
            let totalTime = climbBuffer.reduce(0.0) { $0 + $1.timeSeconds }
            let totalElevGain = climbBuffer.reduce(0.0) { $0 + max(0, $1.elevationGrade * $1.distanceMeters) }
            let avgGrade = averageGrade(climbBuffer)
            
            // Weight-averaged conditions by distance
            let avgHeadwind = climbBuffer.reduce(0.0) { $0 + ($1.averageHeadwindMps * $1.distanceMeters) } / totalDist
            let avgCrosswind = climbBuffer.reduce(0.0) { $0 + ($1.averageCrosswindMps * $1.distanceMeters) } / totalDist
            let avgTemp = climbBuffer.reduce(0.0) { $0 + ($1.averageTemperatureC * $1.distanceMeters) } / totalDist
            let avgHumidity = climbBuffer.reduce(0.0) { $0 + ($1.averageHumidity * $1.distanceMeters) } / totalDist
            let avgPower = climbBuffer.reduce(0.0) { $0 + ($1.powerRequired * $1.distanceMeters) } / totalDist
            
            // Sustainability scaling based on total climb length AND grade
            let sustainabilityFactor: Double
            if avgGrade < 0.03 {
                // Gentle sustained climbs - less fatigue
                if totalDist < 600 {
                    sustainabilityFactor = 0.98      // 2% reduction
                } else if totalDist < 1200 {
                    sustainabilityFactor = 0.96      // 4% reduction
                } else {
                    sustainabilityFactor = 0.94      // 6% reduction
                }
            } else if totalDist < 500 {
                sustainabilityFactor = 0.97          // 3% reduction
            } else if totalDist < 1000 {
                sustainabilityFactor = 0.95          // 5% reduction
            } else if totalDist < 2000 {
                sustainabilityFactor = 0.93          // 7% reduction
            } else if totalDist < 4000 {
                sustainabilityFactor = 0.91          // 9% reduction
            } else {
                sustainabilityFactor = 0.88          // 12% reduction for epic climbs
            }
            
            let combinedSegment = PowerRouteSegment(
                startPoint: climbBuffer.first!.startPoint,
                endPoint: climbBuffer.last!.endPoint,
                distanceMeters: totalDist,
                elevationGrade: avgGrade,
                averageHeadwindMps: avgHeadwind,
                averageCrosswindMps: avgCrosswind,
                averageTemperatureC: avgTemp,
                averageHumidity: avgHumidity,
                calculatedSpeedMps: totalDist / totalTime,
                timeSeconds: totalTime,
                powerRequired: avgPower * sustainabilityFactor,
                segmentType: .climb
            )
            
            print("""
                🔗 Merged sustained climb:
                   Distance: \(Int(totalDist))m (\(String(format: "%.1f", totalDist/1000))km)
                   Grade: \(String(format: "%.1f", avgGrade*100))%
                   Elevation: +\(Int(totalElevGain))m
                   Segments: \(climbBuffer.count) → 1
                   Power: \(Int(avgPower))W → \(Int(avgPower * sustainabilityFactor))W
                   Sustainability: \(Int((1-sustainabilityFactor)*100))% reduction
                """)
            
            merged.append(combinedSegment)
            climbBuffer.removeAll()
        }
        
        // Track interruptions with more sophisticated logic
        var nonClimbAccumulator: [PowerRouteSegment] = []
        var nonClimbDistance = 0.0
        
        for segment in segments {
            if isClimbing(segment) {
                // We're climbing
                
                if climbBuffer.isEmpty {
                    // Start new climb
                    climbBuffer.append(segment)
                    nonClimbAccumulator.removeAll()
                    nonClimbDistance = 0
                } else {
                    // Check if this continues the current climb
                    let referenceGrade = averageGrade(climbBuffer)
                    
                    // Three levels of tolerance
                    if isSimilarGrade(to: referenceGrade, segment: segment) {
                        // Very similar - definitely continue
                        climbBuffer.append(contentsOf: nonClimbAccumulator)
                        climbBuffer.append(segment)
                        nonClimbAccumulator.removeAll()
                        nonClimbDistance = 0
                    } else if abs(segment.elevationGrade - referenceGrade) < gradeVarianceTolerance * 1.8 {
                        // Somewhat different but still compatible
                        // Only include if interruption wasn't too long
                        if nonClimbDistance < 150 {
                            climbBuffer.append(contentsOf: nonClimbAccumulator)
                            climbBuffer.append(segment)
                            nonClimbAccumulator.removeAll()
                            nonClimbDistance = 0
                        } else {
                            // Start new climb
                            flushClimbBuffer()
                            climbBuffer.append(segment)
                            nonClimbAccumulator.removeAll()
                            nonClimbDistance = 0
                        }
                    } else {
                        // Grade changed significantly - start new climb
                        flushClimbBuffer()
                        climbBuffer.append(segment)
                        nonClimbAccumulator.removeAll()
                        nonClimbDistance = 0
                    }
                }
                
            } else if !climbBuffer.isEmpty {
                // We're in a climb but hit a non-climbing segment
                
                // Check if it's a descent or just flat/gentle
                let isSignificantDescent = segment.elevationGrade < -0.02
                let isGentle = !isSignificantDescent && segment.elevationGrade > -0.01
                
                nonClimbAccumulator.append(segment)
                nonClimbDistance += segment.distanceMeters
                
                // Different tolerance for different interruption types
                let maxAllowedDistance = isSignificantDescent ? 100.0 : maxNonClimbDistance
                let maxAllowedSegments = isGentle ? maxNonClimbSegments + 2 : maxNonClimbSegments
                
                // Check if we've had too much interruption
                if nonClimbDistance > maxAllowedDistance ||
                   nonClimbAccumulator.count > maxAllowedSegments {
                    // Too much interruption - end the climb
                    flushClimbBuffer()
                    merged.append(contentsOf: nonClimbAccumulator)
                    nonClimbAccumulator.removeAll()
                    nonClimbDistance = 0
                }
                
            } else {
                // Normal segment outside of any climb
                merged.append(segment)
            }
        }
        
        // Flush any remaining climb and buffered segments
        flushClimbBuffer()
        merged.append(contentsOf: nonClimbAccumulator)
        
        let reductionPct = Double(segments.count - merged.count) / Double(segments.count) * 100
        print("""
            ✅ Climb merging complete:
               \(segments.count) → \(merged.count) segments
               Reduction: \(Int(reductionPct))%
            """)
        
        return merged
    }

    private func mergeSustainedDescents(segments: [PowerRouteSegment]) -> [PowerRouteSegment] {
        guard !segments.isEmpty else { return [] }
        
        var merged: [PowerRouteSegment] = []
        var descentBuffer: [PowerRouteSegment] = []
        
        // Configuration for descent merging
        let minDescentGrade = -0.02           // -2% minimum
        let gradeVarianceTolerance = 0.04     // ±4% variance allowed
        let minSustainedDistance = 200.0      // Minimum 200m to consider merging
        let maxNonDescentDistance = 150.0     // Allow 150m interruption
        let maxNonDescentSegments = 4         // Allow up to 4 flat/climb segments
        
        func isDescending(_ segment: PowerRouteSegment) -> Bool {
            return segment.elevationGrade < minDescentGrade
        }
        
        func averageGrade(_ segments: [PowerRouteSegment]) -> Double {
            guard !segments.isEmpty else { return 0 }
            return segments.map { $0.elevationGrade }.reduce(0, +) / Double(segments.count)
        }
        
        func isSimilarGrade(to referenceGrade: Double, segment: PowerRouteSegment) -> Bool {
            return abs(segment.elevationGrade - referenceGrade) <= gradeVarianceTolerance
        }
        
        func shouldMerge() -> Bool {
            let totalDist = descentBuffer.reduce(0.0) { $0 + $1.distanceMeters }
            
            // Always merge if reasonably long
            if totalDist >= 400 { return true }
            
            // For shorter descents, check quality
            if totalDist < minSustainedDistance { return false }
            
            let grades = descentBuffer.map { $0.elevationGrade }
            let avgGrade = grades.reduce(0, +) / Double(grades.count)
            let variance = grades.map { pow($0 - avgGrade, 2) }.reduce(0, +) / Double(grades.count)
            let stdDev = sqrt(variance)
            
            // Sustained steep descents
            if avgGrade < -0.05 && stdDev < 0.04 { return true }
            
            // Moderate descents
            if avgGrade < -0.03 && stdDev < 0.035 { return true }
            
            return false
        }
        
        func flushDescentBuffer() {
            guard !descentBuffer.isEmpty else { return }
            
            if !shouldMerge() {
                merged.append(contentsOf: descentBuffer)
                descentBuffer.removeAll()
                return
            }
            
            // Single segment - just add it
            if descentBuffer.count == 1 {
                merged.append(descentBuffer[0])
                descentBuffer.removeAll()
                return
            }
            
            // Merge the descent
            let totalDist = descentBuffer.reduce(0.0) { $0 + $1.distanceMeters }
            let avgGrade = averageGrade(descentBuffer)
            
            // Weight-averaged conditions by distance
            let avgHeadwind = descentBuffer.reduce(0.0) { $0 + ($1.averageHeadwindMps * $1.distanceMeters) } / totalDist
            let avgCrosswind = descentBuffer.reduce(0.0) { $0 + ($1.averageCrosswindMps * $1.distanceMeters) } / totalDist
            let avgTemp = descentBuffer.reduce(0.0) { $0 + ($1.averageTemperatureC * $1.distanceMeters) } / totalDist
            let avgHumidity = descentBuffer.reduce(0.0) { $0 + ($1.averageHumidity * $1.distanceMeters) } / totalDist
            
            // For descents, use MINIMUM power (most realistic for coasting)
            let minPower = descentBuffer.map { $0.powerRequired }.min() ?? 50.0
            
            // 🔥 CRITICAL: Recalculate speed using descent physics
            let startElev = elevationAnalysis?.elevation(at: descentBuffer.first!.startPoint.distance) ?? 0
            let endElev = elevationAnalysis?.elevation(at: descentBuffer.last!.endPoint.distance) ?? 0
            let midAltitude = (startElev + endElev) / 2.0
            let airDensityKgM3 = airDensity(atAltitudeMeters: midAltitude, temperatureC: avgTemp)
            
            // Create temporary segment for speed calculation
            let tempSegment = PowerRouteSegment(
                startPoint: descentBuffer.first!.startPoint,
                endPoint: descentBuffer.last!.endPoint,
                distanceMeters: totalDist,
                elevationGrade: avgGrade,
                averageHeadwindMps: avgHeadwind,
                averageCrosswindMps: avgCrosswind,
                averageTemperatureC: avgTemp,
                averageHumidity: avgHumidity,
                calculatedSpeedMps: 10.0, // Temporary placeholder
                timeSeconds: 0,
                powerRequired: minPower,
                segmentType: .descent
            )
            
            // Calculate realistic descent speed
            let descentSpeed = calculateDescentSpeed(
                segment: tempSegment,
                power: minPower,
                airDensity: airDensityKgM3
            )
            
            let totalTime = totalDist / descentSpeed
            
            let combinedSegment = PowerRouteSegment(
                startPoint: descentBuffer.first!.startPoint,
                endPoint: descentBuffer.last!.endPoint,
                distanceMeters: totalDist,
                elevationGrade: avgGrade,
                averageHeadwindMps: avgHeadwind,
                averageCrosswindMps: avgCrosswind,
                averageTemperatureC: avgTemp,
                averageHumidity: avgHumidity,
                calculatedSpeedMps: descentSpeed,  // Use recalculated speed
                timeSeconds: totalTime,            // Use recalculated time
                powerRequired: minPower,
                segmentType: .descent
            )
            
            print("""
                🔗 Merged sustained descent:
                   Distance: \(Int(totalDist))m (\(String(format: "%.1f", totalDist/1000))km)
                   Grade: \(String(format: "%.1f", avgGrade*100))%
                   Segments: \(descentBuffer.count) → 1
                   Power: \(Int(minPower))W (coasting)
                   Speed: \(String(format: "%.1f", descentSpeed * 3.6)) km/h (\(String(format: "%.1f", descentSpeed * 2.237)) mph)
                   Time: \(String(format: "%.1f", totalTime/60)) minutes
                """)
            
            merged.append(combinedSegment)
            descentBuffer.removeAll()
        }

        // Track interruptions
        var nonDescentAccumulator: [PowerRouteSegment] = []
        var nonDescentDistance = 0.0
        
        for segment in segments {
            if isDescending(segment) {
                // We're descending
                
                if descentBuffer.isEmpty {
                    // Start new descent
                    descentBuffer.append(segment)
                    nonDescentAccumulator.removeAll()
                    nonDescentDistance = 0
                } else {
                    // Check if this continues the current descent
                    let referenceGrade = averageGrade(descentBuffer)
                    
                    if isSimilarGrade(to: referenceGrade, segment: segment) {
                        // Very similar - definitely continue
                        descentBuffer.append(contentsOf: nonDescentAccumulator)
                        descentBuffer.append(segment)
                        nonDescentAccumulator.removeAll()
                        nonDescentDistance = 0
                    } else if abs(segment.elevationGrade - referenceGrade) < gradeVarianceTolerance * 1.5 {
                        // Somewhat different but compatible
                        if nonDescentDistance < 100 {
                            descentBuffer.append(contentsOf: nonDescentAccumulator)
                            descentBuffer.append(segment)
                            nonDescentAccumulator.removeAll()
                            nonDescentDistance = 0
                        } else {
                            // Start new descent
                            flushDescentBuffer()
                            descentBuffer.append(segment)
                            nonDescentAccumulator.removeAll()
                            nonDescentDistance = 0
                        }
                    } else {
                        // Grade changed significantly
                        flushDescentBuffer()
                        descentBuffer.append(segment)
                        nonDescentAccumulator.removeAll()
                        nonDescentDistance = 0
                    }
                }
                
            } else if !descentBuffer.isEmpty {
                // We're in a descent but hit a non-descending segment
                
                nonDescentAccumulator.append(segment)
                nonDescentDistance += segment.distanceMeters
                
                // Check if we've had too much interruption
                if nonDescentDistance > maxNonDescentDistance ||
                   nonDescentAccumulator.count > maxNonDescentSegments {
                    // Too much interruption - end the descent
                    flushDescentBuffer()
                    merged.append(contentsOf: nonDescentAccumulator)
                    nonDescentAccumulator.removeAll()
                    nonDescentDistance = 0
                }
                
            } else {
                // Normal segment outside of any descent
                merged.append(segment)
            }
        }
        
        // Flush any remaining descent and buffered segments
        flushDescentBuffer()
        merged.append(contentsOf: nonDescentAccumulator)
        
        let reductionPct = Double(segments.count - merged.count) / Double(segments.count) * 100
        print("""
            ✅ Descent merging complete:
               \(segments.count) → \(merged.count) segments
               Reduction: \(Int(reductionPct))%
            """)
        
        return merged
    }


    // MARK: - Aggressive Short Segment Merging

    private func mergeShortFlats(segments: [PowerRouteSegment]) -> [PowerRouteSegment] {
        guard segments.count > 1 else { return segments }
        
        var merged: [PowerRouteSegment] = []
        var buffer: [PowerRouteSegment] = []
        
        func shouldMergeFlats() -> Bool {
            guard !buffer.isEmpty else { return false }
            let totalDist = buffer.reduce(0.0, { $0 + $1.distanceMeters })
            let avgGrade = buffer.map { $0.elevationGrade }.reduce(0, +) / Double(buffer.count)
            
            // Merge if: short segments, similar grades, and relatively flat
            return totalDist < 800 && abs(avgGrade) < 0.03
        }
        
        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            
            if buffer.count == 1 || !shouldMergeFlats() {
                merged.append(contentsOf: buffer)
            } else {
                // Merge short flat/gentle segments
                let totalDist = buffer.reduce(0.0) { $0 + $1.distanceMeters }
                let totalTime = buffer.reduce(0.0) { $0 + $1.timeSeconds }
                let avgPower = buffer.reduce(0.0) { $0 + ($1.powerRequired * $1.distanceMeters) } / totalDist
                
                let combined = PowerRouteSegment(
                    startPoint: buffer.first!.startPoint,
                    endPoint: buffer.last!.endPoint,
                    distanceMeters: totalDist,
                    elevationGrade: buffer.map { $0.elevationGrade }.reduce(0, +) / Double(buffer.count),
                    averageHeadwindMps: buffer.reduce(0.0) { $0 + ($1.averageHeadwindMps * $1.distanceMeters) } / totalDist,
                    averageCrosswindMps: buffer.reduce(0.0) { $0 + ($1.averageCrosswindMps * $1.distanceMeters) } / totalDist,
                    averageTemperatureC: buffer.reduce(0.0) { $0 + ($1.averageTemperatureC * $1.distanceMeters) } / totalDist,
                    averageHumidity: buffer.reduce(0.0) { $0 + ($1.averageHumidity * $1.distanceMeters) } / totalDist,
                    calculatedSpeedMps: totalDist / totalTime,
                    timeSeconds: totalTime,
                    powerRequired: avgPower,
                    segmentType: buffer.first!.segmentType
                )
                merged.append(combined)
            }
            buffer.removeAll()
        }
        
        for seg in segments {
            // Buffer short non-climb segments
            if seg.distanceMeters < 250 && abs(seg.elevationGrade) < 0.03 {
                // Check if compatible with buffer
                if buffer.isEmpty {
                    buffer.append(seg)
                } else {
                    let avgGrade = buffer.map { $0.elevationGrade }.reduce(0, +) / Double(buffer.count)
                    if abs(seg.elevationGrade - avgGrade) < 0.025 {
                        buffer.append(seg)
                    } else {
                        flushBuffer()
                        buffer.append(seg)
                    }
                }
            } else {
                flushBuffer()
                merged.append(seg)
            }
        }
        flushBuffer()
        
        if merged.count < segments.count {
            print("🔗 Merged short flats: \(segments.count) → \(merged.count) segments")
        }
        
        return merged
    }

    // MARK: - Combined Optimization Pipeline

    private func optimizeSegmentation(segments: [PowerRouteSegment]) -> [PowerRouteSegment] {
        print("\n🔧 Starting segmentation optimization...")
        print("   Initial segments: \(segments.count)\n")
        
        // First pass: merge climbs
        let afterClimbMerge = mergeSustainedClimbs(segments: segments)
        
        // Second pass: merge descents
        let afterDescentMerge = mergeSustainedDescents(segments: afterClimbMerge)
        
        // Third pass: merge short flats
        let afterFlatMerge = mergeShortFlats(segments: afterDescentMerge)
        
        // Optional: Final pass on climbs if we created new opportunities
        let finalPass = mergeSustainedClimbs(segments: afterFlatMerge)
        
        let totalReduction = Double(segments.count - finalPass.count) / Double(segments.count) * 100
        
        print("""
            
            📊 Final segmentation summary:
               Original: \(segments.count)
               After climb merge: \(afterClimbMerge.count)
               After descent merge: \(afterDescentMerge.count)
               After flat merge: \(afterFlatMerge.count)
               After final pass: \(finalPass.count)
               Total reduction: \(Int(totalReduction))%
            """)
        
        return finalPass
    }

    // MARK: - Adaptive Segmentation Helpers

    /// Estimates grade by finding the steepest concentrated section within an interval
    private func estimateIntervalGrade(startPoint: RouteWeatherPoint, endPoint: RouteWeatherPoint, distance: Double) -> Double {
        
        guard let ea = elevationAnalysis, ea.hasActualData, !ea.elevationProfile.isEmpty else {
            return 0.0
        }
        
        let startDist = startPoint.distance
        let endDist = endPoint.distance
        
        let intervalPoints = ea.elevationProfile.filter {
            $0.distance >= startDist && $0.distance <= endDist
        }
        
        guard intervalPoints.count >= 10 else {
            // Fallback for short intervals
            guard let startElev = findClosestElevation(distance: startDist, profile: ea.elevationProfile),
                  let endElev = findClosestElevation(distance: endDist, profile: ea.elevationProfile),
                  distance > 0 else {
                return 0.0
            }
            return (endElev - startElev) / distance
        }
        
        // 🔹 NEW APPROACH: Find the steepest concentrated section using sliding windows
        
        // Define window sizes to check (in meters)
        let windowSizes = [200.0, 400.0, 800.0, 1500.0]
        
        var maxConcentratedGrade: Double = 0
        var maxConcentratedClimbing: Double = 0
        var isClimbing = true
        
        for windowSize in windowSizes {
            // Only check windows that fit in our interval
            guard windowSize < (endDist - startDist) * 0.8 else { continue }
            
            // Slide a window through the interval
            var i = 0
            while i < intervalPoints.count - 5 {
                let windowStart = intervalPoints[i]
                
                // Find points within windowSize distance
                var j = i + 1
                while j < intervalPoints.count &&
                      (intervalPoints[j].distance - windowStart.distance) < windowSize {
                    j += 1
                }
                
                guard j < intervalPoints.count else { break }
                
                let windowEnd = intervalPoints[j]
                let windowDist = windowEnd.distance - windowStart.distance
                
                guard windowDist > 10 else {
                    i += 1
                    continue
                }
                
                // Calculate stats for this window
                var windowClimbing: Double = 0
                var windowDescending: Double = 0
                
                for k in i..<j {
                    let elevChange = intervalPoints[k+1].elevation - intervalPoints[k].elevation
                    if elevChange > 0.1 {
                        windowClimbing += elevChange
                    } else if elevChange < -0.1 {
                        windowDescending += abs(elevChange)
                    }
                }
                
                // Calculate average grade for this window
                let windowGrade = (windowClimbing - windowDescending) / windowDist
                
                // Check if this is a significant concentrated section
                if abs(windowGrade) > abs(maxConcentratedGrade) {
                    maxConcentratedGrade = windowGrade
                    maxConcentratedClimbing = windowGrade > 0 ? windowClimbing : windowDescending
                    isClimbing = windowGrade > 0
                }
                
                i += 5 // Skip forward to avoid overlapping windows
            }
        }
        
        print("   📊 Max concentrated grade: \(String(format: "%.1f", maxConcentratedGrade * 100))% over \(String(format: "%.0f", maxConcentratedClimbing))m")
        
        // 🔹 Decision logic based on concentrated sections
        
        // Significant steep concentrated climbing
        if maxConcentratedGrade > 0.07 && maxConcentratedClimbing > 25 {
            print("   ✅ STEEP CONCENTRATED CLIMB: \(String(format: "%.1f", maxConcentratedGrade * 100))%")
            return min(0.10, maxConcentratedGrade)
        }
        
        // Significant moderate concentrated climbing
        if maxConcentratedGrade > 0.04 && maxConcentratedClimbing > 30 {
            print("   ✅ MODERATE CONCENTRATED CLIMB: \(String(format: "%.1f", maxConcentratedGrade * 100))%")
            return min(0.06, maxConcentratedGrade)
        }
        
        // Significant concentrated descent
        if maxConcentratedGrade < -0.04 && maxConcentratedClimbing > 30 {
            print("   ✅ CONCENTRATED DESCENT: \(String(format: "%.1f", maxConcentratedGrade * 100))%")
            return max(-0.06, maxConcentratedGrade)
        }
        
        // Gentle climbing/descending
        if abs(maxConcentratedGrade) > 0.02 && maxConcentratedClimbing > 20 {
            let direction = maxConcentratedGrade > 0 ? "CLIMB" : "DESCENT"
            print("   ✅ GENTLE \(direction): \(String(format: "%.1f", maxConcentratedGrade * 100))%")
            return maxConcentratedGrade > 0 ? 0.025 : -0.025
        }
        
        // Flat/mixed
        print("   ✅ FLAT/MIXED: Max section grade \(String(format: "%.1f", maxConcentratedGrade * 100))%")
        return 0.0
    }
    
    /// Chooses appropriate segment length based on terrain gradient
    private func chooseSegmentLength(for grade: Double, interval: Double) -> Double {
        let absGrade = abs(grade)
        
        // For very short intervals, just use the interval itself
        if interval < minimumSegmentLength * 2 {
            return max(minimumSegmentLength, interval)
        }
        
        // 🔧 INCREASED SEGMENT SIZES for better performance and realism
        if absGrade > 0.08 {
            // Steep terrain (>8%) - 400m segments
            return 400.0  // Was 250m
        } else if absGrade > 0.03 {
            // Moderate terrain (3-8%) - 300m segments
            return 300.0  // Was 200m
        } else if absGrade < -0.05 {
            // Steep descents - 250m segments
            return 250.0  // Was 150m
        } else {
            // 🔧 KEY FIX: MUCH LARGER segments for flats and gentle terrain
            // This is where most of your route lives!
            if absGrade > 0.01 {
                return 250.0  // Gentle rolling (was 150m)
            } else {
                return 400.0  // Pure flats (was 200m)
            }
        }
    }
    
// Returns air density in kg/m^3 given altitude in meters
    private func airDensity(atAltitudeMeters altitude: Double, temperatureC: Double) -> Double {
        let P0 = 101325.0            // sea level pressure (Pa)
        let T0 = 288.15              // sea level temperature (K)
        let L = 0.0065               // temperature lapse rate (K/m)
        let R = 8.31447              // universal gas constant (J/(mol*K))
        let M = 0.0289644             // molar mass of air (kg/mol)
        let g = 9.80665              // gravity (m/s^2)

        // approximate pressure at altitude
        let T = T0 - L * altitude
        let P = P0 * pow(T / T0, g * M / (R * L))

        // ideal gas law: ρ = P / (R_specific * T)
        let R_specific = 287.05      // J/(kg*K)
        return P / (R_specific * (temperatureC + 273.15))
    }

    private func calculateDescentSpeed(
        segment: PowerRouteSegment,
        power: Double,
        airDensity: Double
    ) -> Double {
        
        let grade = segment.elevationGrade
        
        // Only use this for actual descents
        guard grade < -0.01 else {
            // Not a descent, use normal calculation
            return physicsEngine.calculateSpeed(
                targetPowerWatts: power,
                elevationGrade: grade,
                headwindSpeedMps: segment.averageHeadwindMps,
                crosswindSpeedMps: segment.averageCrosswindMps,
                temperature: segment.averageTemperatureC,
                humidity: segment.averageHumidity,
                airDensity: airDensity,
                isWet: false
            )
        }
        
        // For descents, calculate terminal velocity limited by drag
        let totalMass = settings.bodyWeight + settings.bikeAndEquipmentWeight
        let g = 9.81 // gravity
        let Crr = 0.004 // rolling resistance (better on descents)
        
        // Gravitational force component (negative grade = downhill force)
        let gravityForce = totalMass * g * abs(grade)
        
        // Rolling resistance force
        let rollingForce = totalMass * g * Crr * cos(atan(grade))
        
        // Net force available for acceleration (before air resistance)
        let netForce = gravityForce - rollingForce
        
        // Estimate speed iteratively considering drag
        // Air resistance: F_drag = 0.5 * rho * Cd * A * v^2
        let Cd = 0.88 // drag coefficient
        let A = 0.4   // frontal area (m^2)
        
        // Terminal velocity when gravity = drag + rolling resistance + braking
        // This is a simplified calculation
        let dragCoefficient = 0.5 * airDensity * Cd * A
        
        // Add power input (even low power helps on descents)
        var estimatedSpeed: Double
        
        if power < 50 {
            // Pure coasting - find equilibrium speed
            // v = sqrt(netForce / dragCoefficient)
            estimatedSpeed = sqrt(max(0, netForce / dragCoefficient))
        } else {
            // With pedaling power: P = F*v, so v = P/F + gravity component
            let powerComponent = power / totalMass
            estimatedSpeed = sqrt(max(0, (netForce + powerComponent * 10) / dragCoefficient))
        }
        
        // Account for headwind (increases effective drag)
        let effectiveHeadwind = segment.averageHeadwindMps
        if effectiveHeadwind > 0 {
            // Headwind reduces speed significantly
            let windReduction = effectiveHeadwind * 0.3 // Approximate reduction factor
            estimatedSpeed = max(5.0, estimatedSpeed - windReduction)
        }
        
        // Realistic speed bounds for descents
        if grade < -0.08 {
            // Steep descent (>8%)
            estimatedSpeed = min(estimatedSpeed, 25.0) // Max ~90 km/h (safety limiting)
            estimatedSpeed = max(estimatedSpeed, 12.0) // Min ~43 km/h (heavy braking)
        } else if grade < -0.05 {
            // Moderate descent (5-8%)
            estimatedSpeed = min(estimatedSpeed, 20.0) // Max ~72 km/h
            estimatedSpeed = max(estimatedSpeed, 10.0) // Min ~36 km/h
        } else if grade < -0.03 {
            // Gentle descent (3-5%)
            estimatedSpeed = min(estimatedSpeed, 15.0) // Max ~54 km/h
            estimatedSpeed = max(estimatedSpeed, 8.0)  // Min ~29 km/h
        } else {
            // Slight descent (1-3%)
            estimatedSpeed = min(estimatedSpeed, 12.0) // Max ~43 km/h
            estimatedSpeed = max(estimatedSpeed, 7.0)  // Min ~25 km/h
        }
        
        print("""
            🏔️ Descent Speed Calculation:
               Grade: \(String(format: "%.1f", grade * 100))%
               Power: \(Int(power))W
               Calculated Speed: \(String(format: "%.1f", estimatedSpeed * 3.6)) km/h
            """)
        
        return estimatedSpeed
    }

    // Interpolate a RouteWeatherPoint at a given distance along the route.
    // This uses linear interpolation between the two nearest weatherPoints.
    private func interpolateRouteWeatherPoint(at distance: Double) -> RouteWeatherPoint? {
        guard let first = weatherPoints.first, let last = weatherPoints.last else { return nil }
        if distance <= first.distance { return first }
        if distance >= last.distance { return last }

        for i in 1..<weatherPoints.count {
            let p0 = weatherPoints[i - 1]
            let p1 = weatherPoints[i]
            if distance >= p0.distance && distance <= p1.distance {
                let denom = max(1e-9, p1.distance - p0.distance)
                let ratio = (distance - p0.distance) / denom

                let lat = p0.coordinate.latitude + ratio * (p1.coordinate.latitude - p0.coordinate.latitude)
                let lon = p0.coordinate.longitude + ratio * (p1.coordinate.longitude - p0.coordinate.longitude)
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

                // interpolate ETA if both anchors have valid Date values; otherwise fallback to p0.eta
                let eta: Date
                let t0 = p0.eta
                let t1 = p1.eta
                let dt = t1.timeIntervalSince1970 - t0.timeIntervalSince1970
                eta = t0.addingTimeInterval(ratio * dt)
                
                // use nearest weather anchor for conditions
                let nearest = nearestWeather(for: coord)

                // Build RouteWeatherPoint — adjust constructor if your type is different
                return RouteWeatherPoint(coordinate: coord, distance: distance, eta: eta, weather: nearest.weather)
            }
        }

        return nil
    }

    private func nearestWeather(for coordinate: CLLocationCoordinate2D) -> RouteWeatherPoint {
        guard let closest = weatherPoints.min(by: {
            $0.coordinate.distance(from: coordinate) < $1.coordinate.distance(from: coordinate)
        }) else {
            return weatherPoints.first!
        }
        return closest
    }

    // -----------------------------
    // MARK: - Grade calculation
    // -----------------------------

    private func calculateElevationGrade(startPoint: RouteWeatherPoint, endPoint: RouteWeatherPoint, distance: Double) -> Double {
        // Prefer elevationAnalysis if available
        if let ea = elevationAnalysis, ea.hasActualData, !ea.elevationProfile.isEmpty {
            if let sElev = findClosestElevation(distance: startPoint.distance, profile: ea.elevationProfile),
               let eElev = findClosestElevation(distance: endPoint.distance, profile: ea.elevationProfile),
               distance > 0 {
                return physicsEngine.calculateGrade(startElevationM: sElev, endElevationM: eElev, horizontalDistanceM: distance)
            }
        }

        // No point-level elevation available — fallback to an approximate grade:
        return physicsEngine.estimateAverageGrade(totalDistanceM: max(1.0, weatherPoints.last?.distance ?? 1000.0),
                                                 totalElevationGainM: elevationAnalysis?.totalGain ?? 0.0)
    }

    private func findClosestElevation(distance: Double, profile: [ElevationPoint]) -> Double? {
        let closest = profile.min { abs($0.distance - distance) < abs($1.distance - distance) }
        return closest?.elevation
    }

    // -----------------------------
    // MARK: - Heuristics + analysis helpers
    // -----------------------------

    private func calculateTotalEnergyKilojoules(segments: [PowerRouteSegment]) -> Double {
        let totalJ = segments.reduce(0.0) { $0 + ($1.powerRequired * $1.timeSeconds) }
        return totalJ / 1000.0
    }

    private func calculatePowerDistribution(segments: [PowerRouteSegment]) -> PowerDistribution {
        let totalTime = segments.reduce(0.0) { $0 + $1.timeSeconds }
        let ftp = Double(settings.functionalThresholdPower)

        var z1: Double = 0, z2: Double = 0, z3: Double = 0, z4: Double = 0, z5: Double = 0
        var fourthSum: Double = 0
        var weightedSum: Double = 0

        for s in segments {
            let pct = s.powerRequired / ftp
            switch pct {
            case ..<0.55: z1 += s.timeSeconds
            case 0.55..<0.75: z2 += s.timeSeconds
            case 0.75..<0.90: z3 += s.timeSeconds
            case 0.90..<1.05: z4 += s.timeSeconds
            default: z5 += s.timeSeconds
            }
 //           fourthSum += pow(s.powerRequired, 4) * s.timeSeconds
            weightedSum += s.powerRequired * s.timeSeconds
        }

        let avgPower = totalTime > 0 ? weightedSum / totalTime : 0.0
//        let np = totalTime > 0 ? pow(fourthSum / totalTime, 0.25) : 0.0
        let np = normalizedPower(segments: segments)

        let ifactor = ftp > 0 ? np / ftp : 0.0

        return PowerDistribution(
            averagePower: avgPower,
            normalizedPower: np,
            timeInZones: PowerDistribution.PowerZones(
                zone1Seconds: z1,
                zone2Seconds: z2,
                zone3Seconds: z3,
                zone4Seconds: z4,
                zone5Seconds: z5
            ),
            intensityFactor: ifactor
        )
    }

    private func normalizedPower(segments: [PowerRouteSegment]) -> Double {
        guard !segments.isEmpty else { return 0.0 }

        // Expand segments into 1-second power samples
        var samples: [Double] = []
        for seg in segments {
            let secCount = max(1, Int(seg.timeSeconds.rounded()))
            samples.append(contentsOf: Array(repeating: seg.powerRequired, count: secCount))
        }

        // Rolling 30s average
        let windowSize = 30
        var rolling: [Double] = []
        var windowSum: Double = 0
        var queue: [Double] = []

        for p in samples {
            queue.append(p)
            windowSum += p
            if queue.count > windowSize {
                windowSum -= queue.removeFirst()
            }
            rolling.append(windowSum / Double(queue.count))
        }

        // Fourth power transform
        let fourths = rolling.map { pow($0, 4) }
        let meanFourth = fourths.reduce(0, +) / Double(fourths.count)

        return pow(meanFourth, 0.25)
    }

    private func compareWithTraditionalMethod(totalDistance: Double, powerBasedTime: Double) -> SpeedComparisonResult {
        let powerMin = powerBasedTime / 60.0
        let tradSpeedMps = convertToMps(settings.averageSpeed)
        let tradMin = (totalDistance / max(0.1, tradSpeedMps)) / 60.0
        
        return SpeedComparisonResult(
            traditionalTimeMinutes: tradMin,
            powerBasedTimeMinutes: powerMin,
            timeDifferenceMinutes: powerMin - tradMin,
            significantSegments: [] // This can be populated elsewhere if needed
        )
    }
    
    private func calculateTerrainBreakdown(segments: [PowerRouteSegment]) -> TerrainBreakdown {
        var flat: Double = 0, climb: Double = 0, descend: Double = 0
        var climbGrades: [Double] = [], descendGrades: [Double] = []
        var steepestClimb: Double = 0, steepestDescent: Double = 0

        for s in segments {
            switch s.segmentType {
            case .flat: flat += s.distanceMeters
            case .rolling:  // ADD THIS CASE
                flat += s.distanceMeters  // Treat rolling as flat for distance calculation
            case .climb:
                climb += s.distanceMeters
                climbGrades.append(s.elevationGrade)
                steepestClimb = max(steepestClimb, s.elevationGrade)
            case .descent:
                descend += s.distanceMeters
                descendGrades.append(abs(s.elevationGrade))
                steepestDescent = min(steepestDescent, s.elevationGrade)
            }
        }

        return TerrainBreakdown(
            flatDistanceMeters: flat,
            climbingDistanceMeters: climb,
            descendingDistanceMeters: descend,
            averageClimbGrade: climbGrades.isEmpty ? 0.0 : (climbGrades.reduce(0, +) / Double(climbGrades.count)),
            averageDescentGrade: descendGrades.isEmpty ? 0.0 : (descendGrades.reduce(0, +) / Double(descendGrades.count)),
            steepestClimbGrade: steepestClimb,
            steepestDescentGrade: steepestDescent
        )
    }

    // -----------------------------
    // MARK: - Unit helpers (assume same as your code)
    // -----------------------------
    private func convertToCelsius(_ temp: Double) -> Double {
        return settings.units == .metric ? temp : (temp - 32.0) * 5.0 / 9.0
    }

    private func convertToMps(_ speed: Double) -> Double {
        return settings.units == .metric ? speed / 3.6 : speed * 0.44704
    }

    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1)*sin(lat2) - sin(lat1)*cos(lat2)*cos(dLon)
        let rad = atan2(y, x)
        return (rad * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
    
    // MARK: - Reality Check

        /// Validates that the calculated time is realistic
        private func validateTimeEstimate(
            totalTimeSeconds: Double,
            totalDistanceMeters: Double,
            elevationGain: Double // ✅ FIX: Function now accepts elevationGain
        ) -> Double {
            let hours = totalTimeSeconds / 3600.0
            let distanceKm = totalDistanceMeters / 1000.0
            // Handle division by zero if hours is 0
            let avgSpeedKph = hours > 0 ? (distanceKm / hours) : 0
            
            print("\n🎯 REALITY CHECK:")
            print("   Distance: \(String(format: "%.1f", distanceKm)) km")
            print("   Time: \(String(format: "%.2f", hours)) hours")
            print("   Average Speed: \(String(format: "%.1f", avgSpeedKph)) km/h")
            // ✅ FIX: Use the passed-in elevationGain value
            print("   Elevation Gain: \(Int(elevationGain)) m")
            
            // Calculate reasonable bounds based on conditions
            // Handle division by zero if distanceKm is 0
            let gainPerKm = distanceKm > 0 ? elevationGain / distanceKm : 0
            
            // Minimum realistic speed (very hilly with strong headwind)
            let minSpeedKph: Double = 15.0  // 9.3 mph
            
            // Maximum realistic speed (flat with tailwind)
            let maxSpeedKph: Double = 45.0  // 28 mph
            
            // Expected speed range based on terrain
            var expectedMinSpeed = 18.0  // Moderate pace
            var expectedMaxSpeed = 32.0  // Fast pace
            
            // Adjust for elevation
            if gainPerKm > 20 {
                // Very hilly
                expectedMinSpeed = 16.0
                expectedMaxSpeed = 24.0
            } else if gainPerKm > 10 {
                // Hilly
                expectedMinSpeed = 18.0
                expectedMaxSpeed = 28.0
            }
            
            // 🚨 CRITICAL: Detect obviously wrong estimates
            if avgSpeedKph < minSpeedKph {
                print("   🚨 ESTIMATE TOO SLOW! Adjusting...")
                let correctedHours = distanceKm / expectedMinSpeed
                print("   ✅ Corrected to: \(String(format: "%.2f", correctedHours)) hours (\(String(format: "%.1f", expectedMinSpeed)) km/h)")
                return correctedHours * 3600.0
            }
            
            if avgSpeedKph > maxSpeedKph {
                print("   🚨 ESTIMATE TOO FAST! Adjusting...")
                let correctedHours = distanceKm / expectedMaxSpeed
                print("   ✅ Corrected to: \(String(format: "%.2f", correctedHours)) hours (\(String(format: "%.1f", expectedMaxSpeed)) km/h)")
                return correctedHours * 3600.0
            }
            
            if avgSpeedKph < expectedMinSpeed {
                print("   ⚠️  Speed is lower than expected. Review power targets.")
            } else if avgSpeedKph > expectedMaxSpeed {
                print("   ⚠️  Speed is higher than expected. Review descent handling.")
            } else {
                print("   ✅ Estimate appears realistic!")
            }
            
            return totalTimeSeconds
        }

}

extension CLLocationCoordinate2D {
    func distance(from other: CLLocationCoordinate2D) -> CLLocationDistance {
        let loc1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}
