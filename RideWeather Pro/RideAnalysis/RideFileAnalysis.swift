//
//  RideFileAnalysis.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation
import FitFileParser

// MARK: - Ride Analysis Models

// MARK: - Graphable Data
struct GraphableDataPoint: Codable, Identifiable {
    let id: UUID
    let time: TimeInterval
    let value: Double
    
    init(time: TimeInterval, value: Double) {
        self.id = UUID()
        self.time = time
        self.value = value
    }
}

struct RideAnalysis: Codable, Identifiable {
    let id: UUID
    let date: Date
    var rideName: String
    let duration: TimeInterval // Moving time
    let distance: Double // meters
    
    // Ride metadata
    let metadata: RideMetadata?
    
    // Power Metrics
    let averagePower: Double
    let normalizedPower: Double
    let intensityFactor: Double
    let trainingStressScore: Double
    let variabilityIndex: Double
    
    // Peak Powers
    let peakPower5s: Double
    let peakPower1min: Double
    let peakPower5min: Double
    let peakPower20min: Double
    
    // Terrain-aware analysis
    let terrainSegments: [TerrainSegment]?
    let powerAllocation: PowerAllocationAnalysis?
    
    // Pacing Analysis (now terrain-aware)
    let consistencyScore: Double // 0-100
    let pacingRating: PacingRating
    let powerVariability: Double // coefficient of variation
    
    // Fatigue Detection
    let fatigueDetected: Bool
    let fatigueOnsetTime: TimeInterval? // seconds into ride
    let powerDeclineRate: Double? // watts per hour
    
    // Segment Comparison (if plan exists)
    let plannedRideId: UUID?
    let segmentComparisons: [SegmentComparison]
    let overallDeviation: Double // % difference from plan
    
    // Deviations
    let surgeCount: Int
    let pacingErrors: [PacingError]
    
    // Performance Score
    let performanceScore: Double // 0-100
    
    // Insights
    let insights: [RideInsight]
    
    // Power Zone Distribution
    let powerZoneDistribution: PowerZoneDistribution
    
    let averageHeartRate: Double?
    let powerGraphData: [GraphableDataPoint]?
    let heartRateGraphData: [GraphableDataPoint]?

    let elevationGraphData: [GraphableDataPoint]? // <-- ADD THIS
    
    init(id: UUID = UUID(), date: Date, rideName: String, duration: TimeInterval,
         distance: Double, metadata: RideMetadata?, averagePower: Double, normalizedPower: Double,
         intensityFactor: Double, trainingStressScore: Double, variabilityIndex: Double,
         peakPower5s: Double, peakPower1min: Double, peakPower5min: Double,
         peakPower20min: Double, terrainSegments: [TerrainSegment]?, powerAllocation: PowerAllocationAnalysis?,
         consistencyScore: Double, pacingRating: PacingRating,
         powerVariability: Double, fatigueDetected: Bool, fatigueOnsetTime: TimeInterval?,
         powerDeclineRate: Double?, plannedRideId: UUID?, segmentComparisons: [SegmentComparison],
         overallDeviation: Double, surgeCount: Int, pacingErrors: [PacingError],
         performanceScore: Double, insights: [RideInsight], powerZoneDistribution: PowerZoneDistribution, averageHeartRate: Double?,
         powerGraphData: [GraphableDataPoint]?,
         heartRateGraphData: [GraphableDataPoint]?,
         elevationGraphData: [GraphableDataPoint]?
    ) {
        self.id = id
        self.date = date
        self.rideName = rideName
        self.duration = duration
        self.distance = distance
        self.metadata = metadata
        self.averagePower = averagePower
        self.normalizedPower = normalizedPower
        self.intensityFactor = intensityFactor
        self.trainingStressScore = trainingStressScore
        self.variabilityIndex = variabilityIndex
        self.peakPower5s = peakPower5s
        self.peakPower1min = peakPower1min
        self.peakPower5min = peakPower5min
        self.peakPower20min = peakPower20min
        self.terrainSegments = terrainSegments
        self.powerAllocation = powerAllocation
        self.consistencyScore = consistencyScore
        self.pacingRating = pacingRating
        self.powerVariability = powerVariability
        self.fatigueDetected = fatigueDetected
        self.fatigueOnsetTime = fatigueOnsetTime
        self.powerDeclineRate = powerDeclineRate
        self.plannedRideId = plannedRideId
        self.segmentComparisons = segmentComparisons
        self.overallDeviation = overallDeviation
        self.surgeCount = surgeCount
        self.pacingErrors = pacingErrors
        self.performanceScore = performanceScore
        self.insights = insights
        self.powerZoneDistribution = powerZoneDistribution
        self.averageHeartRate = averageHeartRate
        self.powerGraphData = powerGraphData
        self.heartRateGraphData = heartRateGraphData
        self.elevationGraphData = elevationGraphData // <-- ADD THIS
    }
}

// Add Codable conformance for new types
extension TerrainSegment: Codable {}
extension TerrainSegment.TerrainType: Codable {}
extension PowerAllocationAnalysis: Codable {}
extension PowerAllocationRecommendation: Codable {}

enum PacingRating: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
}

struct SegmentComparison: Codable, Identifiable {
    let id: UUID
    let segmentName: String
    let plannedPower: Double
    let actualPower: Double
    let deviation: Double // percentage
    let plannedTime: TimeInterval
    let actualTime: TimeInterval
    let timeDifference: TimeInterval
    
    var deviationStatus: DeviationStatus {
        if abs(deviation) < 5 { return .onTarget }
        if deviation > 0 { return .tooHard }
        return .tooEasy
    }
}

enum DeviationStatus {
    case tooHard, onTarget, tooEasy
    
    var color: String {
        switch self {
        case .tooHard: return "red"
        case .onTarget: return "green"
        case .tooEasy: return "orange"
        }
    }
}

struct PacingError: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let type: ErrorType
    let magnitude: Double
    let description: String
    
    enum ErrorType: String, Codable {
        case surge = "Power Surge"
        case drop = "Power Drop"
        case prolongedHigh = "Prolonged High Effort"
        case earlyHard = "Too Hard Early"
        case tooEasy = "Too Easy"
    }
}

struct RideInsight: Codable, Identifiable {
    let id: UUID
    let priority: Priority
    let category: Category
    let title: String
    let description: String
    let recommendation: String
    
    enum Priority: String, Codable {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
    }
    
    enum Category: String, Codable {
        case pacing = "Pacing"
        case power = "Power"
        case fatigue = "Fatigue"
        case efficiency = "Efficiency"
        case performance = "Performance"
    }
}

struct PowerZoneDistribution: Codable {
    let zone1Time: TimeInterval // Active Recovery (< 55% FTP)
    let zone2Time: TimeInterval // Endurance (55-75%)
    let zone3Time: TimeInterval // Tempo (75-88%)
    let zone4Time: TimeInterval // Sweet Spot (88-94%)
    let zone5Time: TimeInterval // Threshold (94-105%)
    let zone6Time: TimeInterval // VO2 Max (105-120%)
    let zone7Time: TimeInterval // Anaerobic (> 120%)
    
    func percentage(for zone: Int, totalTime: TimeInterval) -> Double {
        let zoneTime: TimeInterval
        switch zone {
        case 1: zoneTime = zone1Time
        case 2: zoneTime = zone2Time
        case 3: zoneTime = zone3Time
        case 4: zoneTime = zone4Time
        case 5: zoneTime = zone5Time
        case 6: zoneTime = zone6Time
        case 7: zoneTime = zone6Time
        default: return 0
        }
        return (zoneTime / totalTime) * 100
    }
}

// MARK: - FIT File Data Point

struct FITDataPoint {
    let timestamp: Date
    let power: Double?
    let heartRate: Int?
    let cadence: Int?
    let speed: Double? // m/s
    let distance: Double? // meters
    let altitude: Double? // meters
    let position: CLLocationCoordinate2D?
}

// MARK: - Ride File Analyzer

class RideFileAnalyzer {
    
    // Add a settings property
    private let settings: AppSettings
    
    // Add initializer
    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }
    
    // MARK: - Main Analysis Function
    
    func analyzeRide(
        dataPoints: [FITDataPoint],
        ftp: Double,
        weight: Double,
        plannedRide: PacingPlan? = nil,
        isPreFiltered: Bool = false,
        elapsedTimeOverride: TimeInterval? = nil,
        movingTimeOverride: TimeInterval? = nil,
        averageHeartRate: Double?,
        powerGraphData: [GraphableDataPoint]?,
        heartRateGraphData: [GraphableDataPoint]?,
        elevationGraphData: [GraphableDataPoint]?
    ) -> RideAnalysis {
        
        // Filter valid power data
        let validPoints = dataPoints.filter {
            if let power = $0.power {
                return power >= 0
            }
            return false
        }
        
        guard !validPoints.isEmpty else {
            return createEmptyAnalysis()
        }
        
        // Calculate distance FIRST
        let totalDistanceMeters = dataPoints.last?.distance ?? calculateDistance(dataPoints: validPoints)
        
        // Calculate moving vs elapsed time
        let movingPoints: [FITDataPoint]
        let elapsedTime: TimeInterval
        let movingTime: TimeInterval
        
        if isPreFiltered {
            movingPoints = validPoints
            elapsedTime = elapsedTimeOverride ?? calculateDuration(dataPoints: validPoints)
            
            if let stravaMovingTime = movingTimeOverride {
                movingTime = stravaMovingTime
            } else {
                movingTime = calculateDuration(dataPoints: movingPoints)
            }
        } else {
            movingPoints = identifyMovingSegments(dataPoints: validPoints)
            elapsedTime = calculateDuration(dataPoints: validPoints)
            movingTime = calculateDuration(dataPoints: movingPoints)
        }
        
        let stoppedTime = elapsedTime - movingTime
        let powers = movingPoints.compactMap { $0.power }
        
        // Build metadata FIRST (without elevation display values)
        let metadataRaw = buildRideMetadata(
            dataPoints: validPoints,
            movingPoints: movingPoints,
            elapsedTime: elapsedTime,
            movingTime: movingTime,
            stoppedTime: stoppedTime
        )
        
        // Calculate display values using metadata
        let totalDistance = settings.units == .metric ?
        totalDistanceMeters / 1000 : // km
        totalDistanceMeters / 1609.34 // miles
        let distanceUnit = settings.units == .metric ? "km" : "mi"
        
        let avgSpeed = (totalDistance / (movingTime / 3600.0))
        let speedUnit = settings.units == .metric ? "km/h" : "mph"
        
        let elevation = settings.units == .metric ?
        metadataRaw.elevationGain : // meters
        metadataRaw.elevationGain * 3.28084 // feet
        let elevationUnit = settings.units == .metric ? "m" : "ft"
        
        // Create final metadata with display values
        let metadata = RideMetadata(
            routeName: metadataRaw.routeName,
            totalTime: metadataRaw.totalTime,
            movingTime: metadataRaw.movingTime,
            stoppedTime: metadataRaw.stoppedTime,
            date: metadataRaw.date,
            elevationGain: metadataRaw.elevationGain,
            elevationLoss: metadataRaw.elevationLoss,
            avgGradient: metadataRaw.avgGradient,
            maxGradient: metadataRaw.maxGradient,
            totalDistance: totalDistance,
            distanceUnit: distanceUnit,
            avgSpeed: avgSpeed,
            speedUnit: speedUnit,
            elevation: elevation,
            elevationUnit: elevationUnit,
            startCoordinate: metadataRaw.startCoordinate,
            endCoordinate: metadataRaw.endCoordinate,
            routeBreadcrumbs: metadataRaw.routeBreadcrumbs
        )
        
        print("📊 SPEED VERIFICATION:")
        print("   Total distance: \(String(format: "%.2f", totalDistance)) \(distanceUnit)")
        print("   Moving time: \(formatDuration(movingTime))")
        print("   Calculated avg speed: \(String(format: "%.1f", avgSpeed)) \(speedUnit)")
        
        // Terrain segmentation (uses meters internally)
        let terrainSegments = segmentByTerrainImproved(
            dataPoints: movingPoints,
            ftp: ftp,
            weight: weight,
            totalDistance: totalDistanceMeters
        )
        
        print("🎯 SEGMENTATION: \(terrainSegments.count) segments for \(movingPoints.count) data points")
        
        // Power allocation analysis
        let powerAllocation = analyzePowerAllocation(
            terrainSegments: terrainSegments,
            ftp: ftp,
            movingTime: movingTime
        )
        
        // Rest of the analysis
        let avgPower = calculateAveragePower(powers: powers)
        let normalizedPower = calculateNormalizedPower(powers: powers)
        let intensityFactor = normalizedPower / ftp
        let tss = calculateTSS(normalizedPower: normalizedPower, duration: movingTime, ftp: ftp)
        let variabilityIndex = normalizedPower / avgPower
        
        let peaks = calculatePeakPowers(dataPoints: movingPoints)
        
        let consistency = calculateTerrainAwarePacingScore(terrainSegments: terrainSegments)
        let powerVariability = calculateCoefficientOfVariation(powers: powers)
        let pacingRating = determinePacingRating(consistency: consistency, variability: powerVariability)
        
        let (fatigueDetected, fatigueOnset, declineRate) = detectFatigue(dataPoints: movingPoints)
        
        var segmentComparisons: [SegmentComparison] = []
        var overallDeviation: Double = 0
        if let plan = plannedRide {
            segmentComparisons = compareSegments(dataPoints: movingPoints, plan: plan, ftp: ftp)
            overallDeviation = calculateOverallDeviation(comparisons: segmentComparisons)
        }
        
        let (surgeCount, pacingErrors) = detectTerrainAwarePacingErrors(
            terrainSegments: terrainSegments,
            targetPower: normalizedPower
        )
        
        let powerZones = calculatePowerZoneDistribution(dataPoints: movingPoints, ftp: ftp)
        
        let (powerGraphData, hrGraphData, elevationGraphData) = generateGraphData(dataPoints: movingPoints)
        
        let heartRates = movingPoints.compactMap { $0.heartRate }
        let averageHeartRate = heartRates.isEmpty ? nil : (Double(heartRates.reduce(0, +)) / Double(heartRates.count))
        
        let perfScore = calculateTerrainAwarePerformanceScore(
            powerAllocation: powerAllocation,
            consistency: consistency,
            variability: powerVariability,
            fatigueDetected: fatigueDetected,
            terrainSegments: terrainSegments
        )
        
        let insights = generateEnhancedInsights(
            metadata: metadata,
            terrainSegments: terrainSegments,
            powerAllocation: powerAllocation,
            intensityFactor: intensityFactor,
            fatigueDetected: fatigueDetected,
            fatigueOnset: fatigueOnset,
            performanceScore: perfScore,
            ftp: ftp,
            avgPower: avgPower,
            normalizedPower: normalizedPower,
            totalDistance: totalDistance
        )
        
        return RideAnalysis(
            date: dataPoints.first?.timestamp ?? Date(),
            rideName: "Ride Analysis",
            duration: movingTime,
            distance: totalDistanceMeters,
            metadata: metadata,
            averagePower: avgPower,
            normalizedPower: normalizedPower,
            intensityFactor: intensityFactor,
            trainingStressScore: tss,
            variabilityIndex: variabilityIndex,
            peakPower5s: peaks.peak5s,
            peakPower1min: peaks.peak1min,
            peakPower5min: peaks.peak5min,
            peakPower20min: peaks.peak20min,
            terrainSegments: terrainSegments,
            powerAllocation: powerAllocation,
            consistencyScore: consistency,
            pacingRating: pacingRating,
            powerVariability: powerVariability,
            fatigueDetected: fatigueDetected,
            fatigueOnsetTime: fatigueOnset,
            powerDeclineRate: declineRate,
            plannedRideId: nil,
            segmentComparisons: segmentComparisons,
            overallDeviation: overallDeviation,
            surgeCount: surgeCount,
            pacingErrors: pacingErrors,
            performanceScore: perfScore,
            insights: insights,
            powerZoneDistribution: powerZones,
            averageHeartRate: averageHeartRate,
            powerGraphData: powerGraphData,
            heartRateGraphData: hrGraphData,
            elevationGraphData: elevationGraphData
        )
    }
    
    // Extract GPS points at regular intervals for route fingerprinting
    private func extractRouteBreadcrumbs(
        from dataPoints: [FITDataPoint],
        intervalMeters: Double = 500
    ) -> [CLLocationCoordinate2D] {
        
        var breadcrumbs: [CLLocationCoordinate2D] = []
        var lastBreadcrumbDistance: Double = 0
        
        for point in dataPoints {
            guard let coord = point.position,
                  let distance = point.distance,
                  coord.latitude != 0,
                  coord.longitude != 0,
                  abs(coord.latitude) < 90,
                  abs(coord.longitude) < 180 else { continue }
            
            // Add first point
            if breadcrumbs.isEmpty {
                breadcrumbs.append(coord)
                lastBreadcrumbDistance = distance
                continue
            }
            
            // Add breadcrumb every intervalMeters
            if distance - lastBreadcrumbDistance >= intervalMeters {
                breadcrumbs.append(coord)
                lastBreadcrumbDistance = distance
            }
        }
        
        // Always add the last point if we have more than one
        if breadcrumbs.count > 1,
           let lastPoint = dataPoints.last?.position,
           lastPoint.latitude != 0,
           lastPoint.longitude != 0 {
            // Only add if it's not too close to the previous breadcrumb
            if let lastBreadcrumb = breadcrumbs.last,
               lastPoint.distance(from: lastBreadcrumb) > 100 {
                breadcrumbs.append(lastPoint)
            }
        }
        
        print("📍 Route breadcrumbs: \(breadcrumbs.count) points covering \(String(format: "%.1f", lastBreadcrumbDistance/1000))km")
        
        return breadcrumbs
    }
    
    // Simplified buildRideMetadata - just calculates, doesn't format
    private func buildRideMetadata(
        dataPoints: [FITDataPoint],
        movingPoints: [FITDataPoint],
        elapsedTime: TimeInterval,
        movingTime: TimeInterval,
        stoppedTime: TimeInterval
    ) -> RideMetadata {
        
        let altitudes = dataPoints.compactMap { $0.altitude }
        var elevationGain: Double = 0
        var elevationLoss: Double = 0
        var maxGradient: Double = 0
        
        if altitudes.count > 1 {
            let smoothedAltitudes = smoothAltitudeData(altitudes, windowSize: 11)
            let threshold: Double = 1.0
            
            var accumulatedGain: Double = 0
            var accumulatedLoss: Double = 0
            
            for i in 1..<smoothedAltitudes.count {
                let change = smoothedAltitudes[i] - smoothedAltitudes[i-1]
                
                if change > 0 {
                    accumulatedGain += change
                    if accumulatedGain >= threshold {
                        elevationGain += accumulatedGain
                        accumulatedGain = 0
                    }
                } else if change < 0 {
                    accumulatedLoss += abs(change)
                    if accumulatedLoss >= threshold {
                        elevationLoss += accumulatedLoss
                        accumulatedLoss = 0
                    }
                }
                
                if let dist1 = dataPoints[i-1].distance, let dist2 = dataPoints[i].distance {
                    let horizontalDist = dist2 - dist1
                    if horizontalDist > 0 {
                        let gradient = (change / horizontalDist) * 100
                        maxGradient = max(maxGradient, abs(gradient))
                    }
                }
            }
        }
        
        let totalDistance = dataPoints.compactMap { $0.distance }.last ?? 0
        let avgGradient = totalDistance > 0 ? (elevationGain / totalDistance) * 100 : 0
        
        // Extract start and end coordinates
        let startCoordinate = findFirstValidCoordinate(in: dataPoints)
        let endCoordinate = findLastValidCoordinate(in: dataPoints)
        
        if let start = startCoordinate {
            print("📍 Start location: \(String(format: "%.4f", start.latitude)), \(String(format: "%.4f", start.longitude))")
        } else {
            print("⚠️ No start coordinate found")
        }
        
        if let end = endCoordinate {
            print("📍 End location: \(String(format: "%.4f", end.latitude)), \(String(format: "%.4f", end.longitude))")
        } else {
            print("⚠️ No end coordinate found")
        }
        
        // Extract route breadcrumbs
        let breadcrumbs = extractRouteBreadcrumbs(from: dataPoints, intervalMeters: 500)
        
        // Return metadata with only calculated values, no display formatting yet
        return RideMetadata(
            routeName: "Ride",
            totalTime: elapsedTime,
            movingTime: movingTime,
            stoppedTime: stoppedTime,
            date: dataPoints.first?.timestamp ?? Date(),
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            avgGradient: avgGradient,
            maxGradient: maxGradient,
            totalDistance: 0,  // Will be set later
            distanceUnit: "",  // Will be set later
            avgSpeed: 0,       // Will be set later
            speedUnit: "",     // Will be set later
            elevation: 0,      // Will be set later
            elevationUnit: "", // Will be set later
            startCoordinate: startCoordinate,
            endCoordinate: endCoordinate,
            routeBreadcrumbs: breadcrumbs
        )
    }
    
    // Find first valid GPS coordinate (skip initial zeros)
    private func findFirstValidCoordinate(in dataPoints: [FITDataPoint]) -> CLLocationCoordinate2D? {
        for point in dataPoints.prefix(100) { // Check first 100 points
            if let coord = point.position,
               coord.latitude != 0,
               coord.longitude != 0,
               abs(coord.latitude) < 90,  // Sanity check
               abs(coord.longitude) < 180 {
                return coord
            }
        }
        return nil
    }
    
    // Find last valid GPS coordinate (skip trailing zeros)
    private func findLastValidCoordinate(in dataPoints: [FITDataPoint]) -> CLLocationCoordinate2D? {
        for point in dataPoints.suffix(100).reversed() { // Check last 100 points
            if let coord = point.position,
               coord.latitude != 0,
               coord.longitude != 0,
               abs(coord.latitude) < 90,
               abs(coord.longitude) < 180 {
                return coord
            }
        }
        return nil
    }
    
    // MARK: - IMPROVED TERRAIN SEGMENTATION
    
    private func segmentByTerrainImproved(
        dataPoints: [FITDataPoint],
        ftp: Double,
        weight: Double,
        totalDistance: Double
    ) -> [TerrainSegment] {
        
        var segments: [TerrainSegment] = []
        
        guard dataPoints.count > 10 else { return segments }
        
        // 🎯 ADAPTIVE WINDOW SIZES based on data density
        let windowSize = max(10, min(30, dataPoints.count / 100))  // 10-30 seconds
        let minSegmentPoints = 30  // Minimum 30 seconds per segment
        let maxSegmentPoints = 300 // Maximum 5 minutes per segment
        
        var currentSegmentStart = 0
        var currentTerrainType: TerrainSegment.TerrainType = .flat
        var pointsInCurrentSegment = 0
        
        print("🎯 Segmentation Config:")
        print("   Window size: \(windowSize)s")
        print("   Min segment: \(minSegmentPoints)s")
        print("   Max segment: \(maxSegmentPoints)s")
        
        for i in windowSize..<dataPoints.count {
            // Calculate gradient over window
            let gradient = calculateGradient(dataPoints: dataPoints, endIndex: i, windowSize: windowSize)
            let newTerrainType = classifyTerrain(gradient: gradient)
            
            pointsInCurrentSegment += 1
            
            // Decide if we should close the current segment
            let shouldClose =
            (newTerrainType != currentTerrainType && pointsInCurrentSegment > minSegmentPoints) ||
            (pointsInCurrentSegment >= maxSegmentPoints)
            
            if shouldClose {
                if let segment = createTerrainSegment(
                    dataPoints: dataPoints,
                    startIndex: currentSegmentStart,
                    endIndex: i - 1,
                    type: currentTerrainType,
                    ftp: ftp,
                    weight: weight
                ) {
                    segments.append(segment)
                }
                
                currentSegmentStart = i
                currentTerrainType = newTerrainType
                pointsInCurrentSegment = 0
            }
        }
        
        // Close final segment
        if pointsInCurrentSegment > minSegmentPoints {
            if let segment = createTerrainSegment(
                dataPoints: dataPoints,
                startIndex: currentSegmentStart,
                endIndex: dataPoints.count - 1,
                type: currentTerrainType,
                ftp: ftp,
                weight: weight
            ) {
                segments.append(segment)
            }
        }
        
        // Smart merging - only adjacent similar segments
        let mergedSegments = mergeAdjacentSimilarSegments(segments: segments)
        
        return mergedSegments
    }
    
    // MARK: - SMARTER SEGMENT MERGING
    
    private func mergeAdjacentSimilarSegments(segments: [TerrainSegment]) -> [TerrainSegment] {
        guard segments.count > 1 else { return segments }
        
        var merged: [TerrainSegment] = []
        var i = 0
        
        while i < segments.count {
            var currentGroup = [segments[i]]
            var j = i + 1
            
            // Look ahead for similar adjacent segments
            while j < segments.count {
                let current = currentGroup.last!
                let next = segments[j]
                
                // Merge if: same type, similar grade, and combined not too long
                let shouldMerge =
                current.type == next.type &&
                abs(current.gradient - next.gradient) < 0.02 &&  // Within 2%
                (currentGroup.reduce(0.0) { $0 + $1.duration } + next.duration) < 600  // Max 10min
                
                if shouldMerge {
                    currentGroup.append(next)
                    j += 1
                } else {
                    break
                }
            }
            
            // Create merged segment if we have multiple to merge
            if currentGroup.count > 1 {
                let totalDist = currentGroup.reduce(0.0) { $0 + $1.distance }
                let totalTime = currentGroup.reduce(0.0) { $0 + $1.duration }
                let avgGrade = currentGroup.reduce(0.0) { $0 + $1.gradient * $1.distance } / totalDist
                let avgPower = currentGroup.reduce(0.0) { $0 + $1.averagePower * $1.distance } / totalDist
                let avgNP = currentGroup.reduce(0.0) { $0 + $1.normalizedPower * $1.distance } / totalDist
                
                merged.append(TerrainSegment(
                    startIndex: currentGroup.first!.startIndex,
                    endIndex: currentGroup.last!.endIndex,
                    type: currentGroup.first!.type,
                    distance: totalDist,
                    elevationGain: currentGroup.reduce(0.0) { $0 + $1.elevationGain },
                    gradient: avgGrade,
                    duration: totalTime,
                    averagePower: avgPower,
                    normalizedPower: avgNP,
                    optimalPowerForTime: currentGroup.first!.optimalPowerForTime,
                    powerEfficiency: (avgPower / currentGroup.first!.optimalPowerForTime) * 100
                ))
            } else {
                merged.append(currentGroup[0])
            }
            
            i = j
        }
        
        let reduction = segments.count - merged.count
        if reduction > 0 {
            print("🔗 Merged \(reduction) similar segments: \(segments.count) → \(merged.count)")
        }
        
        return merged
    }
    
    // MARK: - ENHANCED INSIGHTS GENERATION with Location Context
    
    private func generateEnhancedInsights(
        metadata: RideMetadata,
        terrainSegments: [TerrainSegment],
        powerAllocation: PowerAllocationAnalysis,
        intensityFactor: Double,
        fatigueDetected: Bool,
        fatigueOnset: TimeInterval?,
        performanceScore: Double,
        ftp: Double,
        avgPower: Double,
        normalizedPower: Double,
        totalDistance: Double
    ) -> [RideInsight] {
        
        var insights: [RideInsight] = []
        
        let movingMinutes = Int(metadata.movingTime / 60)
        let elapsedMinutes = Int(metadata.totalTime / 60)
        let stoppedMinutes = Int(metadata.stoppedTime / 60)
        
        // Calculate cumulative distances for location context
        var cumulativeDistance: Double = 0
        var segmentLocations: [(segment: TerrainSegment, distanceKm: Double)] = []
        for segment in terrainSegments {
            segmentLocations.append((segment, cumulativeDistance / 1000))
            cumulativeDistance += segment.distance
        }
        
        // Use the units stored in metadata
        insights.append(RideInsight(
            id: UUID(),
            priority: .low,
            category: .performance,
            title: "📊 Ride Overview",
            description: """
            Moving Time: \(movingMinutes)min | Elapsed: \(elapsedMinutes)min
            Stopped: \(stoppedMinutes)min (\(Int((metadata.stoppedTime/metadata.totalTime)*100))%)
            Distance: \(String(format: "%.1f", metadata.totalDistance)) \(metadata.distanceUnit)
            Average Speed: \(String(format: "%.1f", metadata.avgSpeed)) \(metadata.speedUnit)
            Elevation: +\(Int(metadata.elevation))\(metadata.elevationUnit)
            """,
            recommendation: stoppedMinutes > 10 ?
            "Consider routes with fewer stops for better training continuity." :
                "Good route flow with minimal stops."
        ))
        
        // 2. POWER ANALYSIS (using moving time)
        let avgWattsPerKg = avgPower / ftp * 100
        let npWattsPerKg = normalizedPower / ftp * 100
        
        insights.append(RideInsight(
            id: UUID(),
            priority: avgWattsPerKg < 65 ? .medium : .low,
            category: .power,
            title: "⚡ Power Metrics",
            description: """
            Average Power: \(Int(avgPower))W (\(Int(avgWattsPerKg))% FTP)
            Normalized Power: \(Int(normalizedPower))W (\(Int(npWattsPerKg))% FTP)
            Intensity Factor: \(String(format: "%.2f", intensityFactor))
            """,
            recommendation: interpretIntensityFactor(intensityFactor, duration: metadata.movingTime)
        ))
        
        // 3. TERRAIN BREAKDOWN with LOCATION
        let climbs = terrainSegments.filter { $0.type == .climb }
        
        let climbTime = climbs.reduce(0.0) { $0 + $1.duration }
        let climbDist = climbs.reduce(0.0) { $0 + $1.distance }
        
        if !climbs.isEmpty {
            let avgClimbPower = climbs.reduce(0.0) { $0 + $1.averagePower * $1.duration } / climbTime
            let climbPowerPct = (avgClimbPower / ftp) * 100
            
            insights.append(RideInsight(
                id: UUID(),
                priority: climbPowerPct < 85 ? .high : .low,
                category: .pacing,
                title: "⛰️ Climbing Analysis",
                description: """
                Time Climbing: \(Int(climbTime/60))min (\(Int(climbTime/metadata.movingTime*100))% of ride)
                Distance: \(String(format: "%.1f", climbDist/1609.34)) miles
                Average Power: \(Int(avgClimbPower))W (\(Int(climbPowerPct))% FTP)
                """,
                recommendation: interpretClimbPower(climbPowerPct, distance: climbDist)
            ))
        }
        
        // Power allocation insight
        if powerAllocation.allocationEfficiency < 90 {
            let timeSaved = Int(powerAllocation.estimatedTimeSaved)
            let climbPercent = Int((powerAllocation.wattsUsedOnClimbs / powerAllocation.totalWatts) * 100)
            
            var explanation: String
            if climbPercent < 50 {
                explanation = "You only used \(climbPercent)% of your energy on climbs. That's the #1 place to push harder for faster times."
            } else if climbPercent > 75 {
                explanation = "You used \(climbPercent)% of energy climbing. While climbs are important, you may have overcooked them and fatigued yourself."
            } else {
                explanation = "Small power adjustments on key segments could improve your time."
            }
            
            insights.append(RideInsight(
                id: UUID(),
                priority: .high,
                category: .efficiency,
                title: "💡 Power Distribution Opportunity",
                description: """
                You could have finished ~\(timeSaved)s faster with better power distribution.
                \(explanation)
                """,
                recommendation: "On climbs, every watt matters - physics is on your side. On flats, aero position and steady power beat surges. Descents are for recovery."
            ))
        }
        
        // 5. PACING QUALITY
        if fatigueDetected, let onset = fatigueOnset {
            let onsetPct = (onset / metadata.movingTime) * 100
            let onsetMiles = (onset / metadata.movingTime) * totalDistance
            
            insights.append(RideInsight(
                id: UUID(),
                priority: onsetPct < 50 ? .high : .medium,
                category: .fatigue,
                title: "📉 Fatigue Detected",
                description: """
                Power declined at \(String(format: "%.1f", onsetMiles)) miles (\(Int(onset/60))min into ride)
                This occurred \(Int(onsetPct))% through your ride
                """,
                recommendation: onsetPct < 50 ?
                "Start 10-15% easier. The first 20% should feel uncomfortably easy." :
                    "Consider nutrition strategy - aim for 60-90g carbs/hour."
            ))
        }
        
        // 6. SEGMENT PERFORMANCE with LOCATION
        let inefficientSegments = segmentLocations.filter {
            $0.segment.powerEfficiency < 75 && $0.segment.duration > 30
        }
        
        if !inefficientSegments.isEmpty {
            let worstSegment = inefficientSegments.min(by: {
                $0.segment.powerEfficiency < $1.segment.powerEfficiency
            })!
            
            let segment = worstSegment.segment
            let locationMiles = worstSegment.distanceKm / 1.60934
            let durationMins = Int(segment.duration / 60)
            let durationSecs = Int(segment.duration.truncatingRemainder(dividingBy: 60))
            
            insights.append(RideInsight(
                id: UUID(),
                priority: .medium,
                category: .pacing,
                title: "\(segment.type.emoji) Segment Opportunity",
                description: """
                Location: Mile \(String(format: "%.1f", locationMiles))
                \(segment.type.rawValue): \(Int(segment.distance/1609.34 * 5280))ft at \(String(format: "%.1f", segment.gradient*100))%
                Duration: \(durationMins):\(String(format: "%02d", durationSecs))
                You averaged: \(Int(segment.averagePower))W
                Optimal would be: \(Int(segment.optimalPowerForTime))W
                Power efficiency: \(Int(segment.powerEfficiency))%
                """,
                recommendation: segment.type == .climb ?
                "Don't leave watts in the tank on climbs - you can't make up time elsewhere. Push \(Int(segment.optimalPowerForTime - segment.averagePower))W harder." :
                    "On flats, focus on aero position and steady power rather than surges."
            ))
        }
        
        return insights.sorted { $0.priority.rawValue < $1.priority.rawValue }
    }
    
    // MARK: - Helper Functions
    
    private func interpretIntensityFactor(_ if: Double, duration: TimeInterval) -> String {
        let hours = duration / 3600.0
        
        switch `if` {
        case 1.05...:
            return hours > 2 ? "Race-level intensity sustained for \(String(format: "%.1f", hours))h is exceptional. Take 48-72h recovery." : "Race intensity - very high quality session."
        case 0.95..<1.05:
            return "Solid threshold work. You're building FTP. Allow 24-36h recovery."
        case 0.85..<0.95:
            return "Good tempo training. Sustainable and effective for building endurance."
        case 0.75..<0.85:
            return "Endurance pace. Perfect for base building and recovery rides."
        default:
            return "Easy recovery pace. Important for long-term development."
        }
    }
    
    private func interpretClimbPower(_ pct: Double, distance: Double) -> String {
        let km = distance / 1000.0
        
        if pct < 85 {
            return "Climbing too conservatively. For \(String(format: "%.1f", km))km of climbing, aim for 95-105% FTP."
        } else if pct > 110 {
            return "Very aggressive climbing. Sustainable for short efforts but may cause fatigue."
        } else {
            return "Excellent climb pacing. This is where you maximize time savings."
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes)min"
    }
    
    private func smoothAltitudeData(_ altitudes: [Double], windowSize: Int) -> [Double] {
        guard altitudes.count > windowSize else { return altitudes }
        
        var smoothed: [Double] = []
        let halfWindow = windowSize / 2
        
        for i in 0..<altitudes.count {
            let start = max(0, i - halfWindow)
            let end = min(altitudes.count - 1, i + halfWindow)
            let window = altitudes[start...end]
            smoothed.append(window.reduce(0, +) / Double(window.count))
        }
        
        return smoothed
    }

    private func calculateGradient(dataPoints: [FITDataPoint], endIndex: Int, windowSize: Int) -> Double {
        let startIndex = max(0, endIndex - windowSize)
        
        guard let startAlt = dataPoints[startIndex].altitude,
              let endAlt = dataPoints[endIndex].altitude,
              let startDist = dataPoints[startIndex].distance,
              let endDist = dataPoints[endIndex].distance else {
            return 0
        }
        
        let elevationChange = endAlt - startAlt
        let horizontalDistance = endDist - startDist
        
        return horizontalDistance > 0 ? (elevationChange / horizontalDistance) * 100 : 0
    }
    
    private func classifyTerrain(gradient: Double) -> TerrainSegment.TerrainType {
        switch abs(gradient) {
        case 0..<1.5:
            return .flat
        case 1.5..<3:
            return .rolling
        case 3...:
            return gradient > 0 ? .climb : .descent
        default:
            return .flat
        }
    }
    
    private func createTerrainSegment(
        dataPoints: [FITDataPoint],
        startIndex: Int,
        endIndex: Int,
        type: TerrainSegment.TerrainType,
        ftp: Double,
        weight: Double
    ) -> TerrainSegment? {
        
        let segmentPoints = Array(dataPoints[startIndex...endIndex])
        let powers = segmentPoints.compactMap { $0.power }
        
        guard !powers.isEmpty else { return nil }
        
        let avgPower = powers.reduce(0, +) / Double(powers.count)
        let normalizedPower = calculateNormalizedPower(powers: powers)
        
        let startAlt = segmentPoints.first?.altitude ?? 0
        let endAlt = segmentPoints.last?.altitude ?? 0
        let elevationChange = endAlt - startAlt
        
        let startDist = segmentPoints.first?.distance ?? 0
        let endDist = segmentPoints.last?.distance ?? 0
        let distance = endDist - startDist
        
        let gradient = distance > 0 ? (elevationChange / distance) * 100 : 0
        let duration = Double(endIndex - startIndex) // Assuming 1Hz data
        
        // Calculate optimal power for this terrain to minimize time
        let optimalPower = calculateOptimalPower(
            terrain: type,
            gradient: gradient,
            distance: distance,
            ftp: ftp,
            weight: weight,
            duration: duration
        )
        
        let powerEfficiency = optimalPower > 0 ? (avgPower / optimalPower) * 100 : 100
        
        return TerrainSegment(
            startIndex: startIndex,
            endIndex: endIndex,
            type: type,
            distance: distance,
            elevationGain: max(0, elevationChange),
            gradient: gradient,
            duration: duration,
            averagePower: avgPower,
            normalizedPower: normalizedPower,
            optimalPowerForTime: optimalPower,
            powerEfficiency: powerEfficiency
        )
    }
    
    private func calculateOptimalPower(
        terrain: TerrainSegment.TerrainType,
        gradient: Double,
        distance: Double,
        ftp: Double,
        weight: Double,
        duration: TimeInterval
    ) -> Double {
        // Physics-based optimal power calculation
        // For climbs: More power = faster time (up to sustainable limits)
        // For flats: Power follows aero drag curve (cubic relationship)
        // For descents: Minimal power needed
        
        switch terrain {
        case .climb:
            // On climbs, ROI is nearly linear until you hit anaerobic threshold
            // Optimal is around 105-110% FTP for climbs under 20 minutes
            if duration < 300 { // Under 5 minutes
                return ftp * 1.20 // Short climbs, can go harder
            } else if duration < 1200 { // 5-20 minutes
                return ftp * 1.05 // Near threshold
            } else {
                return ftp * 0.95 // Longer climbs, slightly sub-threshold
            }
            
        case .flat:
            // On flats, aero drag dominates
            // 80-85% FTP is typically most efficient for sustained efforts
            return ftp * 0.82
            
        case .rolling:
            // Variable terrain, balance between climb and flat power
            if gradient > 0 {
                return ftp * 0.95
            } else {
                return ftp * 0.80
            }
            
        case .descent:
            // Descents: minimal power, focus on aero position
            return ftp * 0.50
        }
    }
    
    private func analyzePowerAllocation(
        terrainSegments: [TerrainSegment],
        ftp: Double,
        movingTime: TimeInterval
    ) -> PowerAllocationAnalysis {
        
        var totalWatts: Double = 0
        var wattsOnClimbs: Double = 0
        var wattsOnFlats: Double = 0
        var wattsOnDescents: Double = 0
        var optimalClimbWatts: Double = 0
        
        var recommendations: [PowerAllocationRecommendation] = []
        
        for segment in terrainSegments {
            let segmentEnergy = segment.averagePower * segment.duration
            totalWatts += segmentEnergy
            
            switch segment.type {
            case .climb:
                wattsOnClimbs += segmentEnergy
                optimalClimbWatts += segment.optimalPowerForTime * segment.duration
                
                // Analyze if they should have gone harder
                if segment.powerEfficiency < 85 {
                    let optimalPower = segment.optimalPowerForTime
                    let timeLost = estimateTimeLost(
                        actualPower: segment.averagePower,
                        optimalPower: optimalPower,
                        distance: segment.distance,
                        gradient: segment.gradient
                    )
                    
                    recommendations.append(PowerAllocationRecommendation(
                        segment: segment,
                        actualPower: segment.averagePower,
                        optimalPower: optimalPower,
                        timeLost: timeLost,
                        description: "Climb at \(String(format: "%.1f%%", segment.gradient)) grade: pushed \(Int(segment.averagePower))W when \(Int(optimalPower))W would have been faster"
                    ))
                }
                
            case .flat:
                wattsOnFlats += segmentEnergy
                
            case .descent:
                wattsOnDescents += segmentEnergy
                
            case .rolling:
                wattsOnFlats += segmentEnergy
            }
        }
        
        let climbPercentage = totalWatts > 0 ? (wattsOnClimbs / totalWatts) * 100 : 0
        let optimalClimbPercentage = totalWatts > 0 ? (optimalClimbWatts / totalWatts) * 100 : 0
        
        let allocationEfficiency = optimalClimbPercentage > 0 ?
        (climbPercentage / optimalClimbPercentage) * 100 : 100
        
        let totalTimeSaved = recommendations.reduce(0) { $0 + $1.timeLost }
        
        return PowerAllocationAnalysis(
            totalWatts: totalWatts,
            wattsUsedOnClimbs: wattsOnClimbs,
            wattsUsedOnFlats: wattsOnFlats,
            wattsUsedOnDescents: wattsOnDescents,
            optimalClimbAllocation: optimalClimbWatts,
            allocationEfficiency: allocationEfficiency,
            estimatedTimeSaved: totalTimeSaved,
            recommendations: recommendations
        )
    }
    
    private func estimateTimeLost(
        actualPower: Double,
        optimalPower: Double,
        distance: Double,
        gradient: Double
    ) -> TimeInterval {
        // Simplified physics model
        // On climbs, power is roughly linear with speed
        // Time = Distance / Speed, Speed ∝ Power
        
        guard actualPower > 0 && optimalPower > 0 else { return 0 }
        
        let powerRatio = optimalPower / actualPower
        let speedRatio = pow(powerRatio, 0.33) // Rough approximation
        
        // Estimate current speed from power (very rough)
        let estimatedSpeed = actualPower / 10.0 // m/s (rough estimate)
        let actualTime = distance / estimatedSpeed
        let optimalTime = distance / (estimatedSpeed * speedRatio)
        
        return max(0, actualTime - optimalTime)
    }
    
    private func calculateTerrainAwarePacingScore(terrainSegments: [TerrainSegment]) -> Double {
        // Score based on whether power was appropriate for terrain
        var totalScore: Double = 0
        var totalWeight: Double = 0
        
        for segment in terrainSegments {
            let weight = segment.duration
            totalScore += segment.powerEfficiency * weight
            totalWeight += weight
        }
        
        return totalWeight > 0 ? totalScore / totalWeight : 0
    }
    
    private func detectTerrainAwarePacingErrors(
        terrainSegments: [TerrainSegment],
        targetPower: Double
    ) -> (surgeCount: Int, errors: [PacingError]) {
        
        var errors: [PacingError] = []
        var surgeCount = 0
        
        for segment in terrainSegments {
            // Errors depend on terrain type
            switch segment.type {
            case .flat, .rolling:
                // On flats, consistency matters
                if segment.powerEfficiency < 70 {
                    errors.append(PacingError(
                        id: UUID(),
                        timestamp: Double(segment.startIndex),
                        type: .tooEasy,
                        magnitude: segment.optimalPowerForTime - segment.averagePower,
                        description: "Too easy on flat section - lost time"
                    ))
                } else if segment.powerEfficiency > 130 {
                    errors.append(PacingError(
                        id: UUID(),
                        timestamp: Double(segment.startIndex),
                        type: .surge,
                        magnitude: segment.averagePower - segment.optimalPowerForTime,
                        description: "Wasted energy on flat - diminishing aero returns"
                    ))
                    surgeCount += 1
                }
                
            case .climb:
                // On climbs, under-powering is the bigger mistake
                if segment.powerEfficiency < 75 {
                    errors.append(PacingError(
                        id: UUID(),
                        timestamp: Double(segment.startIndex),
                        type: .tooEasy,
                        magnitude: segment.optimalPowerForTime - segment.averagePower,
                        description: "Climbed too conservatively - significant time lost"
                    ))
                }
                
            case .descent:
                // On descents, excess power is wasted
                if segment.averagePower > targetPower * 0.7 {
                    errors.append(PacingError(
                        id: UUID(),
                        timestamp: Double(segment.startIndex),
                        type: .prolongedHigh,
                        magnitude: segment.averagePower - (targetPower * 0.5),
                        description: "Pedaling hard on descent - wasted energy"
                    ))
                }
            }
        }
        
        return (surgeCount, errors)
    }
    
    private func calculateTerrainAwarePerformanceScore(
        powerAllocation: PowerAllocationAnalysis,
        consistency: Double,
        variability: Double,
        fatigueDetected: Bool,
        terrainSegments: [TerrainSegment]
    ) -> Double {
        
        var score: Double = 100
        
        // Power allocation is most important (50% of score)
        score -= (100 - powerAllocation.allocationEfficiency) * 0.5
        
        // Terrain-appropriate pacing (30% of score)
        score -= (100 - consistency) * 0.3
        
        // Fatigue management (20% of score)
        if fatigueDetected {
            score -= 20
        }
        
        return max(0, min(100, score))
    }
    
    //______________________________________________
    
    // UPDATED: Better moving time detection
    // Smarter moving detection
    private func identifyMovingSegments(dataPoints: [FITDataPoint]) -> [FITDataPoint] {
        guard dataPoints.count > 1 else { return dataPoints }
        
        var movingPoints: [FITDataPoint] = []
        
        // Two-pass algorithm:
        // Pass 1: Identify definitely stopped periods (long zeros with no distance change)
        // Pass 2: Include brief coasting/soft-pedaling periods
        
        for i in 0..<dataPoints.count {
            let point = dataPoints[i]
            let power = point.power ?? 0
            let speed = point.speed ?? 0
            
            // Check if this is part of a stopped segment
            let isStopped = isPointInStoppedSegment(
                dataPoints: dataPoints,
                index: i,
                lookAheadWindow: 10  // Look 10 seconds ahead
            )
            
            if !isStopped {
                movingPoints.append(point)
            }
        }
        
        return movingPoints
    }
    
    // Helper: Determine if a point is part of a stopped segment
    private func isPointInStoppedSegment(
        dataPoints: [FITDataPoint],
        index: Int,
        lookAheadWindow: Int
    ) -> Bool {
        let endIndex = min(index + lookAheadWindow, dataPoints.count - 1)
        
        // Check the window around this point
        var zeroCount = 0
        var totalDistanceChange = 0.0
        var lowSpeedCount = 0
        
        for i in index...endIndex {
            let power = dataPoints[i].power ?? 0
            let speed = dataPoints[i].speed ?? 0
            
            if power == 0 {
                zeroCount += 1
            }
            
            if speed < 0.5 { // Less than 0.5 m/s (very slow)
                lowSpeedCount += 1
            }
            
            // Track distance change
            if i > index,
               let currentDist = dataPoints[i].distance,
               let prevDist = dataPoints[i-1].distance {
                totalDistanceChange += (currentDist - prevDist)
            }
        }
        
        let windowSize = endIndex - index + 1
        
        // Consider stopped if:
        // - Most points (>80%) have zero power, AND
        // - Most points (>80%) have very low speed, AND
        // - Very little distance covered (< 5 meters in the window)
        let mostlyZeroPower = Double(zeroCount) / Double(windowSize) > 0.8
        let mostlyNotMoving = Double(lowSpeedCount) / Double(windowSize) > 0.8
        let littleDistance = totalDistanceChange < 5.0
        
        return mostlyZeroPower && mostlyNotMoving && littleDistance
    }
        
    enum RideType: String {
        case steady = "Steady Endurance"
        case intervals = "High-Intensity/Intervals"
        case urban = "Urban/Stop-and-Go"
        case mixed = "Mixed Terrain"
    }
    
/*    struct RideCharacteristics {
        let rideType: RideType
        let highPowerPercentage: Double
        let accelerationCount: Int
        let averageToNormalizedRatio: Double
        let stoppedTime: TimeInterval
    }*/
    
    // MARK: - Power Calculations
    
    private func calculateAveragePower(powers: [Double]) -> Double {
        guard !powers.isEmpty else { return 0 }
        return powers.reduce(0, +) / Double(powers.count)
    }
    
    private func calculateNormalizedPower(powers: [Double]) -> Double {
        // NP calculation: 30-second rolling average raised to 4th power, then 4th root
        guard powers.count >= 30 else { return calculateAveragePower(powers: powers) }
        
        var rollingAverages: [Double] = []
        for i in 0..<(powers.count - 29) {
            let window = Array(powers[i..<(i + 30)])
            let avg = window.reduce(0, +) / 30.0
            rollingAverages.append(avg)
        }
        
        let fourthPowers = rollingAverages.map { pow($0, 4) }
        let avgFourthPower = fourthPowers.reduce(0, +) / Double(fourthPowers.count)
        return pow(avgFourthPower, 0.25)
    }
    
    private func calculateTSS(normalizedPower: Double, duration: TimeInterval, ftp: Double) -> Double {
        let hours = duration / 3600.0
        let intensityFactor = normalizedPower / ftp
        return hours * pow(intensityFactor, 2) * 100
    }
    
    private func calculatePeakPowers(dataPoints: [FITDataPoint]) -> (peak5s: Double, peak1min: Double, peak5min: Double, peak20min: Double) {
        let powers = dataPoints.compactMap { $0.power }
        
        let peak5s = findMaxAveragePower(powers: powers, windowSize: 5)
        let peak1min = findMaxAveragePower(powers: powers, windowSize: 60)
        let peak5min = findMaxAveragePower(powers: powers, windowSize: 300)
        let peak20min = findMaxAveragePower(powers: powers, windowSize: 1200)
        
        return (peak5s, peak1min, peak5min, peak20min)
    }
    
    private func findMaxAveragePower(powers: [Double], windowSize: Int) -> Double {
        guard powers.count >= windowSize else {
            return powers.isEmpty ? 0 : powers.reduce(0, +) / Double(powers.count)
        }
        
        var maxAvg: Double = 0
        for i in 0...(powers.count - windowSize) {
            let window = Array(powers[i..<(i + windowSize)])
            let avg = window.reduce(0, +) / Double(windowSize)
            maxAvg = max(maxAvg, avg)
        }
        return maxAvg
    }
    
    // MARK: - Pacing Analysis
    
    private func calculateCoefficientOfVariation(powers: [Double]) -> Double {
        let mean = calculateAveragePower(powers: powers)
        let variance = powers.map { pow($0 - mean, 2) }.reduce(0, +) / Double(powers.count)
        let stdDev = sqrt(variance)
        return (stdDev / mean) * 100
    }
    
    private func determinePacingRating(consistency: Double, variability: Double) -> PacingRating {
        if consistency >= 85 && variability < 15 { return .excellent }
        if consistency >= 70 && variability < 25 { return .good }
        if consistency >= 50 && variability < 35 { return .fair }
        return .poor
    }
    
    // MARK: - Fatigue Detection
    
    private func detectFatigue(dataPoints: [FITDataPoint]) -> (detected: Bool, onset: TimeInterval?, declineRate: Double?) {
        let powers = dataPoints.compactMap { $0.power }
        guard powers.count > 300 else { return (false, nil, nil) } // Need at least 5 minutes
        
        // Split ride into 5-minute segments
        let segmentSize = 300
        var segmentAverages: [(time: TimeInterval, power: Double)] = []
        
        for i in stride(from: 0, to: powers.count - segmentSize, by: segmentSize) {
            let segment = Array(powers[i..<min(i + segmentSize, powers.count)])
            let avg = segment.reduce(0, +) / Double(segment.count)
            segmentAverages.append((TimeInterval(i), avg))
        }
        
        guard segmentAverages.count >= 3 else { return (false, nil, nil) }
        
        // Look for sustained power decline (20%+ drop maintained)
        let baseline = segmentAverages.prefix(2).map { $0.power }.reduce(0, +) / 2.0
        
        for (i, segment) in segmentAverages.enumerated() {
            if i < 2 { continue }
            
            let decline = (baseline - segment.power) / baseline
            if decline > 0.20 {
                // Check if decline is sustained
                let remainingSegments = Array(segmentAverages[i...])
                let avgRemaining = remainingSegments.map { $0.power }.reduce(0, +) / Double(remainingSegments.count)
                let sustainedDecline = (baseline - avgRemaining) / baseline
                
                if sustainedDecline > 0.15 {
                    let declineRate = (baseline - avgRemaining) * (3600.0 / segment.time)
                    return (true, segment.time, declineRate)
                }
            }
        }
        
        return (false, nil, nil)
    }
    
    // MARK: - Segment Comparison
    
    private func compareSegments(dataPoints: [FITDataPoint], plan: PacingPlan, ftp: Double) -> [SegmentComparison] {
        var comparisons: [SegmentComparison] = []
        
        // Get all data points that have a distance value
        let validDataPoints = dataPoints.filter { $0.distance != nil }
        guard !validDataPoints.isEmpty else { return [] }
        
        for (segmentIndex, segment) in plan.segments.enumerated() {
            // Get the immutable distance boundaries from the *plan*
            let startDistance = segment.originalSegment.startPoint.distance
            let endDistance = segment.originalSegment.endPoint.distance
            
            // Find all *actual ride* data points that fall within this exact distance range
            let segmentPoints = validDataPoints.filter {
                let dist = $0.distance! // We know this is non-nil from the filter above
                return dist >= startDistance && dist <= endDistance
            }
            
            guard !segmentPoints.isEmpty, let firstPoint = segmentPoints.first, let lastPoint = segmentPoints.last else {
                continue
            }
            
            // Now, analyze the *actual* performance for this *exact* segment of road
            let actualPowers = segmentPoints.compactMap { $0.power }
            let actualAvgPower = actualPowers.isEmpty ? 0 : actualPowers.reduce(0, +) / Double(actualPowers.count)
            
            // Calculate actual time spent in this distance segment
            let actualTime = lastPoint.timestamp.timeIntervalSince(firstPoint.timestamp)
            
            let plannedPower = segment.targetPower
            let plannedTime = segment.estimatedTime // This is in seconds
            
            let deviation = ((actualAvgPower - plannedPower) / plannedPower) * 100
            let timeDiff = actualTime - plannedTime // Negative = faster than plan
            
            // Use the segment name from the plan for a clear title
            let segmentName = "Segment \(segmentIndex + 1): \(segment.strategy)"
            
            comparisons.append(SegmentComparison(
                id: UUID(),
                segmentName: segmentName,
                plannedPower: plannedPower,
                actualPower: actualAvgPower,
                deviation: deviation,
                plannedTime: plannedTime,
                actualTime: actualTime,
                timeDifference: timeDiff
            ))
        }
        
        return comparisons
    }
    
    
    private func calculateOverallDeviation(comparisons: [SegmentComparison]) -> Double {
        guard !comparisons.isEmpty else { return 0 }
        let totalDeviation = comparisons.map { abs($0.deviation) }.reduce(0, +)
        return totalDeviation / Double(comparisons.count)
    }

    // MARK: - Power Zones
    
    private func calculatePowerZoneDistribution(dataPoints: [FITDataPoint], ftp: Double) -> PowerZoneDistribution {
        var z1: TimeInterval = 0, z2: TimeInterval = 0, z3: TimeInterval = 0, z4: TimeInterval = 0
        var z5: TimeInterval = 0, z6: TimeInterval = 0, z7: TimeInterval = 0
        
        for point in dataPoints {
            guard let power = point.power else { continue }
            let percentage = (power / ftp) * 100
            
            switch percentage {
            case ..<55: z1 += 1
            case 55..<75: z2 += 1
            case 75..<88: z3 += 1
            case 88..<94: z4 += 1
            case 94..<105: z5 += 1
            case 105..<120: z6 += 1
            default: z7 += 1
            }
        }
        
        return PowerZoneDistribution(zone1Time: z1, zone2Time: z2, zone3Time: z3, zone4Time: z4,
                                     zone5Time: z5, zone6Time: z6, zone7Time: z7)
    }
    
    // MARK: - Helper Functions
    
    private func calculateDuration(dataPoints: [FITDataPoint]) -> TimeInterval {
        guard let first = dataPoints.first, let last = dataPoints.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }
    
    private func calculateDistance(dataPoints: [FITDataPoint]) -> Double {
        return dataPoints.compactMap { $0.distance }.last ?? 0
    }
    
    private func createEmptyAnalysis() -> RideAnalysis {
        return RideAnalysis(
            date: Date(),
            rideName: "Empty Ride",
            duration: 0,
            distance: 0,
            metadata: RideMetadata(
                routeName: "Empty",
                totalTime: 0,
                movingTime: 0,
                stoppedTime: 0,
                date: Date(),
                elevationGain: 0,
                elevationLoss: 0,
                avgGradient: 0,
                maxGradient: 0,
                totalDistance: 0,
                distanceUnit: "mi",
                avgSpeed: 0,
                speedUnit: "mph",
                elevation: 0,
                elevationUnit: "ft",
                startCoordinate: nil,
                endCoordinate: nil,
                routeBreadcrumbs: nil
            ),
            averagePower: 0,
            normalizedPower: 0,
            intensityFactor: 0,
            trainingStressScore: 0,
            variabilityIndex: 0,
            peakPower5s: 0,
            peakPower1min: 0,
            peakPower5min: 0,
            peakPower20min: 0,
            terrainSegments: nil,
            powerAllocation: nil,
            consistencyScore: 0,
            pacingRating: .poor,
            powerVariability: 0,
            fatigueDetected: false,
            fatigueOnsetTime: nil,
            powerDeclineRate: nil,
            plannedRideId: nil,
            segmentComparisons: [],
            overallDeviation: 0,
            surgeCount: 0,
            pacingErrors: [],
            performanceScore: 0,
            insights: [],
            powerZoneDistribution: PowerZoneDistribution(
                zone1Time: 0, zone2Time: 0, zone3Time: 0, zone4Time: 0,
                zone5Time: 0, zone6Time: 0, zone7Time: 0
            ),
            averageHeartRate: nil,
            powerGraphData: nil,
            heartRateGraphData: nil,
            elevationGraphData: nil // <-- FIX: Add the missing property
        )
    }
    
    // MARK: - Graphing Data
        
    func generateGraphData(dataPoints: [FITDataPoint], targetPoints: Int = 200) -> (power: [GraphableDataPoint]?, hr: [GraphableDataPoint]?, elevation: [GraphableDataPoint]?) {
        
        guard !dataPoints.isEmpty else {
            return (nil, nil, nil) // <-- FIX: Return 3 nils
        }
        
        let firstTimestamp = dataPoints.first!.timestamp
        var powerGraphData: [GraphableDataPoint] = []
        var hrGraphData: [GraphableDataPoint] = []
        var elevationGraphData: [GraphableDataPoint] = [] // <-- ADD THIS
        
        // If data is already small, just convert it
        guard dataPoints.count > targetPoints else {
            let powerData = dataPoints.compactMap { $0.power != nil ? GraphableDataPoint(time: $0.timestamp.timeIntervalSince(firstTimestamp), value: $0.power!) : nil }
            let hrData = dataPoints.compactMap { $0.heartRate != nil ? GraphableDataPoint(time: $0.timestamp.timeIntervalSince(firstTimestamp), value: Double($0.heartRate!)) : nil }
            let elevationData = dataPoints.compactMap { $0.altitude != nil ? GraphableDataPoint(time: $0.timestamp.timeIntervalSince(firstTimestamp), value: $0.altitude!) : nil } // <-- ADD
            return (powerData.isEmpty ? nil : powerData, hrData.isEmpty ? nil : hrData, elevationData.isEmpty ? nil : elevationData) // <-- FIX: Return 3 values
        }
        
        // Downsample by averaging into buckets
        let bucketSize = dataPoints.count / targetPoints
        
        for i in 0..<targetPoints {
            let startIndex = i * bucketSize
            let endIndex = min((i + 1) * bucketSize, dataPoints.count)
            let bucket = dataPoints[startIndex..<endIndex]
            
            guard !bucket.isEmpty else { continue }
            
            // Calculate average time for this bucket
            let avgTime = bucket.map { $0.timestamp.timeIntervalSince(firstTimestamp) }.reduce(0, +) / Double(bucket.count)
            
            // Calculate average power
            let bucketPowers = bucket.compactMap { $0.power }
            if !bucketPowers.isEmpty {
                let avgPower = bucketPowers.reduce(0, +) / Double(bucketPowers.count)
                powerGraphData.append(GraphableDataPoint(time: avgTime, value: avgPower))
            }
            
            // Calculate average HR
            let bucketHRs = bucket.compactMap { $0.heartRate }
            if !bucketHRs.isEmpty {
                let avgHR = bucketHRs.map { Double($0) }.reduce(0, +) / Double(bucketHRs.count)
                hrGraphData.append(GraphableDataPoint(time: avgTime, value: avgHR))
            }
            
            // Calculate average elevation
            let bucketElevations = bucket.compactMap { $0.altitude }
            if !bucketElevations.isEmpty {
                let avgElevation = bucketElevations.reduce(0, +) / Double(bucketElevations.count)
                elevationGraphData.append(GraphableDataPoint(time: avgTime, value: avgElevation))
            }
        }
        
        return (powerGraphData.isEmpty ? nil : powerGraphData, hrGraphData.isEmpty ? nil : hrGraphData, elevationGraphData.isEmpty ? nil : elevationGraphData) // <-- FIX: Return 3 values
    }
}


// MARK: - Extensions for Display

extension RideAnalysis {
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    
    var formattedDistance: String {
        let km = distance / 1000
        return String(format: "%.2f km", km)
    }
    
    var formattedDistanceMiles: String {
        let miles = distance / 1609.34
        return String(format: "%.2f mi", miles)
    }
    
    func exportToCSV() -> String {
        var csv = "Metric,Value\n"
        csv += "Date,\(date.formatted())\n"
        csv += "Ride Name,\(rideName)\n"
        csv += "Duration,\(formattedDuration)\n"
        csv += "Distance (km),\(String(format: "%.2f", distance/1000))\n"
        csv += "Average Power,\(Int(averagePower))\n"
        csv += "Normalized Power,\(Int(normalizedPower))\n"
        csv += "Intensity Factor,\(String(format: "%.2f", intensityFactor))\n"
        csv += "TSS,\(Int(trainingStressScore))\n"
        csv += "Variability Index,\(String(format: "%.2f", variabilityIndex))\n"
        csv += "Peak 5s,\(Int(peakPower5s))\n"
        csv += "Peak 1min,\(Int(peakPower1min))\n"
        csv += "Peak 5min,\(Int(peakPower5min))\n"
        csv += "Peak 20min,\(Int(peakPower20min))\n"
        csv += "Consistency Score,\(Int(consistencyScore))\n"
        csv += "Pacing Rating,\(pacingRating.rawValue)\n"
        csv += "Power Variability,\(String(format: "%.1f", powerVariability))%\n"
        csv += "Fatigue Detected,\(fatigueDetected ? "Yes" : "No")\n"
        csv += "Surge Count,\(surgeCount)\n"
        csv += "Performance Score,\(Int(performanceScore))\n"
        
        if !segmentComparisons.isEmpty {
            csv += "\nSegment Analysis\n"
            csv += "Segment,Planned Power,Actual Power,Deviation %\n"
            for segment in segmentComparisons {
                csv += "\(segment.segmentName),\(Int(segment.plannedPower)),\(Int(segment.actualPower)),\(String(format: "%.1f", segment.deviation))\n"
            }
        }
        
        return csv
    }
    
    func exportToReport() -> String {
        var report = """
        ═══════════════════════════════════════════════
        RIDE ANALYSIS REPORT
        ═══════════════════════════════════════════════
        
        📅 Date: \(date.formatted(date: .long, time: .shortened))
        🚴 Ride: \(rideName)
        ⏱️  Duration: \(formattedDuration)
        📏 Distance: \(formattedDistance)
        
        ═══════════════════════════════════════════════
        POWER METRICS
        ═══════════════════════════════════════════════
        
        Average Power:      \(Int(averagePower))W
        Normalized Power:   \(Int(normalizedPower))W (NP)
        Intensity Factor:   \(String(format: "%.2f", intensityFactor)) (IF)
        Training Stress:    \(Int(trainingStressScore)) TSS
        Variability Index:  \(String(format: "%.2f", variabilityIndex)) (VI)
        
        Peak Powers:
        • 5 seconds:        \(Int(peakPower5s))W
        • 1 minute:         \(Int(peakPower1min))W
        • 5 minutes:        \(Int(peakPower5min))W
        • 20 minutes:       \(Int(peakPower20min))W
        
        ═══════════════════════════════════════════════
        PACING ANALYSIS
        ═══════════════════════════════════════════════
        
        Consistency Score:  \(Int(consistencyScore))/100
        Pacing Rating:      \(pacingRating.rawValue)
        Power Variability:  \(String(format: "%.1f", powerVariability))%
        Surge Count:        \(surgeCount)
        
        """
        
        if fatigueDetected, let onset = fatigueOnsetTime {
            let minutes = Int(onset / 60)
            report += """
            
            ⚠️  FATIGUE DETECTED
            Onset: \(minutes) minutes into ride
            """
            if let decline = powerDeclineRate {
                report += "\nDecline Rate: \(Int(decline))W/hour"
            }
            report += "\n"
        }
        
        if !segmentComparisons.isEmpty {
            report += """
            
            ═══════════════════════════════════════════════
            SEGMENT-BY-SEGMENT COMPARISON
            ═══════════════════════════════════════════════
            
            """
            for segment in segmentComparisons {
                let status = segment.deviationStatus == .onTarget ? "✓" :
                            segment.deviationStatus == .tooHard ? "↑" : "↓"
                report += """
                \(status) \(segment.segmentName)
                   Planned: \(Int(segment.plannedPower))W  →  Actual: \(Int(segment.actualPower))W
                   Deviation: \(segment.deviation > 0 ? "+" : "")\(String(format: "%.1f", segment.deviation))%
                
                """
            }
            report += "Overall Deviation: \(String(format: "%.1f", overallDeviation))%\n"
        }
        
        report += """
        
        ═══════════════════════════════════════════════
        PERFORMANCE SCORE: \(Int(performanceScore))/100
        ═══════════════════════════════════════════════
        
        """
        
        if !insights.isEmpty {
            report += """
            
            ═══════════════════════════════════════════════
            KEY INSIGHTS & RECOMMENDATIONS
            ═══════════════════════════════════════════════
            
            """
            for (index, insight) in insights.enumerated() {
                let priority = insight.priority == .high ? "🔴" :
                              insight.priority == .medium ? "🟡" : "🟢"
                report += """
                \(priority) \(insight.title)
                \(insight.description)
                → \(insight.recommendation)
                
                """
                if index < insights.count - 1 {
                    report += "───────────────────────────────────────────────\n"
                }
            }
        }
        
        report += """
        
        ═══════════════════════════════════════════════
        End of Report
        ═══════════════════════════════════════════════
        """
        
        return report
    }
}

// MARK: - FIT File Parser

class FITFileParser {
    
    func parseFile(at url: URL) async throws -> [FITDataPoint] {
        let data = try Data(contentsOf: url)
        
        // Import the FIT file parsing library
        let fitFile = FitFile(data: data)
        let records = fitFile.messages(forMessageType: .record)
        
        var dataPoints: [FITDataPoint] = []
        
        for msg in records {
            var power: Double?
            var heartRate: Int?
            var cadence: Int?
            var speed: Double?
            var distance: Double?
            var altitude: Double?
            var coordinate: CLLocationCoordinate2D?
            var timestamp: Date?
            
            // Use reflection to access the message fields
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
            
            // Extract power
            if let values = valuesDict {
                power = values["power"]
                heartRate = values["heart_rate"].map { Int($0) }
                cadence = values["cadence"].map { Int($0) }
                speed = values["speed"] ?? values["enhanced_speed"]
                distance = values["distance"]
                
                // Try multiple altitude keys
                for altKey in ["enhanced_altitude", "altitude", "enhanced_alt", "alt"] {
                    if let altValue = values[altKey] {
                        altitude = altValue
                        break
                    }
                }
                
                // Get coordinates
                if let lat = values["position_lat"], let lon = values["position_long"] {
                    // Convert semicircles to degrees
                    let latDegrees = lat * (180.0 / pow(2, 31))
                    let lonDegrees = lon * (180.0 / pow(2, 31))
                    coordinate = CLLocationCoordinate2D(latitude: latDegrees, longitude: lonDegrees)
                }
            }
            
            // Get timestamp
            if let dates = datesDict {
                timestamp = dates["timestamp"]
            }
            
            // Only add if we have a timestamp
            if let ts = timestamp {
                dataPoints.append(FITDataPoint(
                    timestamp: ts,
                    power: power,
                    heartRate: heartRate,
                    cadence: cadence,
                    speed: speed,
                    distance: distance,
                    altitude: altitude,
                    position: coordinate
                ))
            }
        }
        
        // Validate we got some data
        guard !dataPoints.isEmpty else {
            throw FITParserError.noDataFound
        }
        
        return dataPoints
    }
    
    enum FITParserError: LocalizedError {
        case invalidFile
        case noDataFound
        case corruptedData
        
        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "The selected file is not a valid FIT file"
            case .noDataFound:
                return "No ride data found in FIT file"
            case .corruptedData:
                return "FIT file data is corrupted or incomplete"
            }
        }
    }
}

// MARK: - Analysis Storage Manager

class AnalysisStorageManager {
    private let userDefaults = UserDefaults.standard
    private let storageKey = "savedRideAnalyses"
    
    func saveAnalysis(_ analysis: RideAnalysis) {
        var analyses = loadAllAnalyses()
        analyses.append(analysis)
        
        // Keep only last 50 analyses
        if analyses.count > 50 {
            analyses = Array(analyses.suffix(50))
        }
        
        if let encoded = try? JSONEncoder().encode(analyses) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
    
    func loadAllAnalyses() -> [RideAnalysis] {
        guard let data = userDefaults.data(forKey: storageKey),
              let analyses = try? JSONDecoder().decode([RideAnalysis].self, from: data) else {
            return []
        }
        return analyses.sorted { $0.date > $1.date }
    }
    
    func deleteAnalysis(_ analysis: RideAnalysis) {
        var analyses = loadAllAnalyses()
        analyses.removeAll { $0.id == analysis.id }
        
        if let encoded = try? JSONEncoder().encode(analyses) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
    
/*    func getAnalysisTrend(limit: Int = 10) -> [TrendDataPoint] {
        let analyses = loadAllAnalyses().prefix(limit)
        return analyses.map { analysis in
            TrendDataPoint(
                date: analysis.date,
                performanceScore: analysis.performanceScore,
                tss: analysis.trainingStressScore,
                consistency: analysis.consistencyScore
            )
        }.reversed()
    }*/
    
/*    func exportAllToCSV() -> String {
        let analyses = loadAllAnalyses()
        var csv = "Date,Ride Name,Duration,Distance(km),Avg Power,NP,IF,TSS,VI,Consistency,Performance Score\n"
        
        for analysis in analyses {
            csv += "\(analysis.date.formatted()),"
            csv += "\(analysis.rideName),"
            csv += "\(analysis.formattedDuration),"
            csv += "\(String(format: "%.2f", analysis.distance/1000)),"
            csv += "\(Int(analysis.averagePower)),"
            csv += "\(Int(analysis.normalizedPower)),"
            csv += "\(String(format: "%.2f", analysis.intensityFactor)),"
            csv += "\(Int(analysis.trainingStressScore)),"
            csv += "\(String(format: "%.2f", analysis.variabilityIndex)),"
            csv += "\(Int(analysis.consistencyScore)),"
            csv += "\(Int(analysis.performanceScore))\n"
        }
        
        return csv
    }*/
}

/*struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let performanceScore: Double
    let tss: Double
    let consistency: Double
}*/

// MARK: - Terrain-Aware Analysis Models

struct TerrainSegment: Identifiable {
    let id = UUID()
    let startIndex: Int
    let endIndex: Int
    let type: TerrainType
    let distance: Double
    let elevationGain: Double
    let gradient: Double
    let duration: TimeInterval
    let averagePower: Double
    let normalizedPower: Double
    let optimalPowerForTime: Double // What power would minimize time
    let powerEfficiency: Double // How close they got to optimal
    
    enum TerrainType: String {
        case climb = "Climb"
        case descent = "Descent"
        case flat = "Flat"
        case rolling = "Rolling"
        
        var emoji: String {
            switch self {
            case .climb: return "⛰️"
            case .descent: return "⬇️"
            case .flat: return "➡️"
            case .rolling: return "〰️"
            }
        }
    }
}

struct PowerAllocationAnalysis {
    let totalWatts: Double // Total energy available
    let wattsUsedOnClimbs: Double
    let wattsUsedOnFlats: Double
    let wattsUsedOnDescents: Double
    let optimalClimbAllocation: Double // Watts that should have gone to climbs
    let allocationEfficiency: Double // 0-100 score
    let estimatedTimeSaved: TimeInterval // If power allocated optimally
    let recommendations: [PowerAllocationRecommendation]
}

struct PowerAllocationRecommendation {
    let segment: TerrainSegment
    let actualPower: Double
    let optimalPower: Double
    let timeLost: TimeInterval
    let description: String
}

struct RideMetadata: Codable {
    let routeName: String
    let totalTime: TimeInterval // Elapsed time
    let movingTime: TimeInterval
    let stoppedTime: TimeInterval
    let date: Date
    let elevationGain: Double // Still stored in meters for calculations
    let elevationLoss: Double
    let avgGradient: Double
    let maxGradient: Double
    
    // User-friendly display values
    let totalDistance: Double    // In user's preferred unit
    let distanceUnit: String     // "km" or "mi"
    let avgSpeed: Double         // In user's preferred unit
    let speedUnit: String        // "km/h" or "mph"
    let elevation: Double        // In user's preferred unit
    let elevationUnit: String    // "m" or "ft"
    
    // GPS coordinates for route matching
    let startCoordinate: CLLocationCoordinate2D?
    let endCoordinate: CLLocationCoordinate2D?
    // GPS breadcrumbs for accurate route matching
    let routeBreadcrumbs: [CLLocationCoordinate2D]?
}

// MARK: - CLLocationCoordinate2D Codable Extension

extension CLLocationCoordinate2D: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}
