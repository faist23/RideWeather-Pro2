//
//  RideFileAnalysis.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation
import FitFileParser

// MARK: - Ride Analysis Models

struct RideAnalysis: Codable, Identifiable {
    let id: UUID
    let date: Date
    let rideName: String
    let duration: TimeInterval
    let distance: Double // meters
    
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
    
    // Pacing Analysis
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
    
    init(id: UUID = UUID(), date: Date, rideName: String, duration: TimeInterval,
         distance: Double, averagePower: Double, normalizedPower: Double,
         intensityFactor: Double, trainingStressScore: Double, variabilityIndex: Double,
         peakPower5s: Double, peakPower1min: Double, peakPower5min: Double,
         peakPower20min: Double, consistencyScore: Double, pacingRating: PacingRating,
         powerVariability: Double, fatigueDetected: Bool, fatigueOnsetTime: TimeInterval?,
         powerDeclineRate: Double?, plannedRideId: UUID?, segmentComparisons: [SegmentComparison],
         overallDeviation: Double, surgeCount: Int, pacingErrors: [PacingError],
         performanceScore: Double, insights: [RideInsight], powerZoneDistribution: PowerZoneDistribution) {
        self.id = id
        self.date = date
        self.rideName = rideName
        self.duration = duration
        self.distance = distance
        self.averagePower = averagePower
        self.normalizedPower = normalizedPower
        self.intensityFactor = intensityFactor
        self.trainingStressScore = trainingStressScore
        self.variabilityIndex = variabilityIndex
        self.peakPower5s = peakPower5s
        self.peakPower1min = peakPower1min
        self.peakPower5min = peakPower5min
        self.peakPower20min = peakPower20min
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
    }
}

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
    let zone4Time: TimeInterval // Threshold (88-94%)
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
    
    // MARK: - Main Analysis Function
    
    func analyzeRide(
        dataPoints: [FITDataPoint],
        ftp: Double,
        weight: Double,
        plannedRide: PacingPlan? = nil
    ) -> RideAnalysis {
        
        // Only include points with valid power !< 0
        let validPoints = dataPoints.filter {
            if let power = $0.power {
                return power >= 0 // ✅ Changed > to >= to include 0 power
            }
            return false
        }
        guard !validPoints.isEmpty else {
            return createEmptyAnalysis()
        }
        
        let powers = validPoints.compactMap { $0.power }
        let duration = calculateDuration(dataPoints: validPoints)
        let distance = calculateDistance(dataPoints: validPoints)
        
        // Power Metrics
        let avgPower = calculateAveragePower(powers: powers)
        let normalizedPower = calculateNormalizedPower(powers: powers)
        let intensityFactor = normalizedPower / ftp
        let tss = calculateTSS(normalizedPower: normalizedPower, duration: duration, ftp: ftp)
        let variabilityIndex = normalizedPower / avgPower
        
        // Peak Powers
        let peaks = calculatePeakPowers(dataPoints: validPoints)
        
        // Pacing Analysis
        let consistency = calculateConsistencyScore(powers: powers, target: normalizedPower)
        let powerVariability = calculateCoefficientOfVariation(powers: powers)
        let pacingRating = determinePacingRating(consistency: consistency, variability: powerVariability)
        
        // Fatigue Detection
        let (fatigueDetected, fatigueOnset, declineRate) = detectFatigue(dataPoints: validPoints)
        
        // Segment Comparison
        var segmentComparisons: [SegmentComparison] = []
        var overallDeviation: Double = 0
        if let plan = plannedRide {
            segmentComparisons = compareSegments(dataPoints: validPoints, plan: plan, ftp: ftp)
            overallDeviation = calculateOverallDeviation(comparisons: segmentComparisons)
        }
        
        // Deviation Detection
        let (surgeCount, pacingErrors) = detectPacingErrors(dataPoints: validPoints, targetPower: normalizedPower)
        
        // Power Zone Distribution
        let powerZones = calculatePowerZoneDistribution(dataPoints: validPoints, ftp: ftp)
        
        // Performance Score
        let perfScore = calculatePerformanceScore(
            consistency: consistency,
            variability: powerVariability,
            deviation: overallDeviation,
            surgeCount: surgeCount,
            fatigueDetected: fatigueDetected
        )
        
        // Generate Insights
        let insights = generateInsights(
            consistency: consistency,
            variability: powerVariability,
            fatigueDetected: fatigueDetected,
            fatigueOnset: fatigueOnset,
            surgeCount: surgeCount,
            intensityFactor: intensityFactor,
            segmentComparisons: segmentComparisons,
            pacingErrors: pacingErrors,
            performanceScore: perfScore
        )
        
        return RideAnalysis(
            date: dataPoints.first?.timestamp ?? Date(),
            rideName: "Ride Analysis",
            duration: duration,
            distance: distance,
            averagePower: avgPower,
            normalizedPower: normalizedPower,
            intensityFactor: intensityFactor,
            trainingStressScore: tss,
            variabilityIndex: variabilityIndex,
            peakPower5s: peaks.peak5s,
            peakPower1min: peaks.peak1min,
            peakPower5min: peaks.peak5min,
            peakPower20min: peaks.peak20min,
            consistencyScore: consistency,
            pacingRating: pacingRating,
            powerVariability: powerVariability,
            fatigueDetected: fatigueDetected,
            fatigueOnsetTime: fatigueOnset,
            powerDeclineRate: declineRate,
            plannedRideId: nil, // PacingPlan doesn't have an id property
            segmentComparisons: segmentComparisons,
            overallDeviation: overallDeviation,
            surgeCount: surgeCount,
            pacingErrors: pacingErrors,
            performanceScore: perfScore,
            insights: insights,
            powerZoneDistribution: powerZones
        )
    }
    
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
    
    private func calculateConsistencyScore(powers: [Double], target: Double) -> Double {
        let deviations = powers.map { abs($0 - target) / target }
        let avgDeviation = deviations.reduce(0, +) / Double(deviations.count)
        return max(0, min(100, 100 * (1 - avgDeviation)))
    }
    
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
        var currentIndex = 0
        
        for (segmentIndex, segment) in plan.segments.enumerated() {
            let segmentDuration = segment.estimatedTime
            let segmentPoints = dataPoints[currentIndex..<min(currentIndex + Int(segmentDuration), dataPoints.count)]
            
            guard !segmentPoints.isEmpty else { continue }
            
            let actualPowers = segmentPoints.compactMap { $0.power }
            let actualAvgPower = actualPowers.isEmpty ? 0 : actualPowers.reduce(0, +) / Double(actualPowers.count)
            let plannedPower = segment.targetPower
            let deviation = ((actualAvgPower - plannedPower) / plannedPower) * 100
            let actualTime = Double(segmentPoints.count)
            let timeDiff = actualTime - segmentDuration
            let segmentName = "Segment \(segmentIndex + 1)"

            comparisons.append(SegmentComparison(
                id: UUID(),
                segmentName: segmentName,
                plannedPower: plannedPower,
                actualPower: actualAvgPower,
                deviation: deviation,
                plannedTime: segmentDuration,
                actualTime: actualTime,
                timeDifference: timeDiff
            ))
            
            currentIndex += Int(segmentDuration)
        }
        
        return comparisons
    }
    
    private func calculateOverallDeviation(comparisons: [SegmentComparison]) -> Double {
        guard !comparisons.isEmpty else { return 0 }
        let totalDeviation = comparisons.map { abs($0.deviation) }.reduce(0, +)
        return totalDeviation / Double(comparisons.count)
    }
    
    // MARK: - Deviation Detection
    
    private func detectPacingErrors(dataPoints: [FITDataPoint], targetPower: Double) -> (surgeCount: Int, errors: [PacingError]) {
        let powers = dataPoints.compactMap { $0.power }
        var surgeCount = 0
        var errors: [PacingError] = []
        
        // Detect surges (>130% target for >10 seconds)
        var surgeStart: Int?
        for (i, power) in powers.enumerated() {
            if power > targetPower * 1.3 {
                if surgeStart == nil {
                    surgeStart = i
                }
            } else {
                if let start = surgeStart, i - start >= 10 {
                    surgeCount += 1
                    let magnitude = powers[start..<i].reduce(0, +) / Double(i - start) - targetPower
                    errors.append(PacingError(
                        id: UUID(),
                        timestamp: TimeInterval(start),
                        type: .surge,
                        magnitude: magnitude,
                        description: "Power surge of \(Int(magnitude))W above target"
                    ))
                }
                surgeStart = nil
            }
        }
        
        // Detect early hard efforts (first 25% > 110% of target)
        let firstQuarter = Int(Double(powers.count) * 0.25)
        if firstQuarter > 0 {
            let earlyPowers = Array(powers[0..<firstQuarter])
            let earlyAvg = earlyPowers.reduce(0, +) / Double(earlyPowers.count)
            if earlyAvg > targetPower * 1.10 {
                errors.append(PacingError(
                    id: UUID(),
                    timestamp: 0,
                    type: .earlyHard,
                    magnitude: earlyAvg - targetPower,
                    description: "Started \(Int(((earlyAvg - targetPower) / targetPower) * 100))% too hard"
                ))
            }
        }
        
        return (surgeCount, errors)
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
    
    // MARK: - Performance Score
    
    private func calculatePerformanceScore(
        consistency: Double,
        variability: Double,
        deviation: Double,
        surgeCount: Int,
        fatigueDetected: Bool
    ) -> Double {
        var score: Double = 100
        
        // Consistency (40% weight)
        score -= (100 - consistency) * 0.4
        
        // Variability penalty (20% weight)
        if variability > 15 {
            score -= (variability - 15) * 0.5
        }
        
        // Deviation from plan (20% weight)
        score -= deviation * 0.5
        
        // Surge penalty (10% weight)
        score -= Double(surgeCount) * 2
        
        // Fatigue penalty (10% weight)
        if fatigueDetected {
            score -= 15
        }
        
        return max(0, min(100, score))
    }
    
    // MARK: - Insights Generation
    
    private func generateInsights(
        consistency: Double,
        variability: Double,
        fatigueDetected: Bool,
        fatigueOnset: TimeInterval?,
        surgeCount: Int,
        intensityFactor: Double,
        segmentComparisons: [SegmentComparison],
        pacingErrors: [PacingError],
        performanceScore: Double
    ) -> [RideInsight] {
        var insights: [RideInsight] = []
        
        // Pacing Insights
        if consistency >= 85 {
            insights.append(RideInsight(
                id: UUID(),
                priority: .low,
                category: .pacing,
                title: "Excellent Pacing",
                description: "You maintained \(Int(consistency))% pacing consistency throughout the ride.",
                recommendation: "Continue this disciplined approach in future rides."
            ))
        } else if consistency < 60 {
            insights.append(RideInsight(
                id: UUID(),
                priority: .high,
                category: .pacing,
                title: "Inconsistent Pacing Detected",
                description: "Pacing consistency was only \(Int(consistency))%, indicating frequent power fluctuations.",
                recommendation: "Focus on maintaining steady power output. Use a power target and avoid responding to every change in terrain."
            ))
        }
        
        // Power Variability
        if variability > 25 {
            insights.append(RideInsight(
                id: UUID(),
                priority: .high,
                category: .power,
                title: "High Power Variability",
                description: "Power variability of \(Int(variability))% suggests frequent surges and drops.",
                recommendation: "Reduce power spikes - they waste energy without proportional speed gains. Aim for smooth, consistent effort."
            ))
        }
        
        // Surge Detection
        if surgeCount > 10 {
            insights.append(RideInsight(
                id: UUID(),
                priority: .medium,
                category: .efficiency,
                title: "Frequent Power Spikes",
                description: "Detected \(surgeCount) power surges above target.",
                recommendation: "These spikes are metabolically costly. Practice restraint, especially on hills and into headwinds."
            ))
        }
        
        // Fatigue Insights
        if fatigueDetected, let onset = fatigueOnset {
            let minutes = Int(onset / 60)
            insights.append(RideInsight(
                id: UUID(),
                priority: .high,
                category: .fatigue,
                title: "Early Fatigue Detected",
                description: "Power output declined significantly after \(minutes) minutes.",
                recommendation: "Consider starting more conservatively. Early over-exertion leads to premature fatigue and slower overall times."
            ))
        }
        
        // Intensity Factor
        if intensityFactor > 1.05 {
            insights.append(RideInsight(
                id: UUID(),
                priority: .medium,
                category: .performance,
                title: "High Intensity Effort",
                description: "Intensity Factor of \(String(format: "%.2f", intensityFactor)) indicates a very hard effort.",
                recommendation: "This effort level is sustainable for races but may require extended recovery."
            ))
        }
        
        // Segment-specific insights
        let badSegments = segmentComparisons.filter { abs($0.deviation) > 15 }
        if !badSegments.isEmpty {
            let worstSegment = badSegments.max(by: { abs($0.deviation) < abs($1.deviation) })!
            let direction = worstSegment.deviation > 0 ? "too hard" : "too easy"
            insights.append(RideInsight(
                id: UUID(),
                priority: .medium,
                category: .pacing,
                title: "Segment Pacing Error",
                description: "\(worstSegment.segmentName) was \(Int(abs(worstSegment.deviation)))% \(direction).",
                recommendation: "Review your planned watts for this segment and practice executing at the prescribed power."
            ))
        }
        
        // Overall Performance
        if performanceScore >= 85 {
            insights.append(RideInsight(
                id: UUID(),
                priority: .low,
                category: .performance,
                title: "Outstanding Execution",
                description: "Performance score of \(Int(performanceScore))/100 indicates excellent race execution.",
                recommendation: "This is your best effort yet. Maintain this discipline in your goal event."
            ))
        }
        
        // Early pacing errors
        if let earlyError = pacingErrors.first(where: { $0.type == .earlyHard }) {
            insights.append(RideInsight(
                id: UUID(),
                priority: .high,
                category: .pacing,
                title: "Started Too Hard",
                description: earlyError.description,
                recommendation: "The first 15-20 minutes should feel too easy. This conservative start pays dividends later in the ride."
            ))
        }
        
        return insights.sorted { $0.priority.rawValue < $1.priority.rawValue }
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
            averagePower: 0,
            normalizedPower: 0,
            intensityFactor: 0,
            trainingStressScore: 0,
            variabilityIndex: 0,
            peakPower5s: 0,
            peakPower1min: 0,
            peakPower5min: 0,
            peakPower20min: 0,
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
            )
        )
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
        return String(format: "%.1f km", km)
    }
    
    var formattedDistanceMiles: String {
        let miles = distance / 1609.34
        return String(format: "%.1f mi", miles)
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
    
    func getAnalysisTrend(limit: Int = 10) -> [TrendDataPoint] {
        let analyses = loadAllAnalyses().prefix(limit)
        return analyses.map { analysis in
            TrendDataPoint(
                date: analysis.date,
                performanceScore: analysis.performanceScore,
                tss: analysis.trainingStressScore,
                consistency: analysis.consistencyScore
            )
        }.reversed()
    }
    
    func exportAllToCSV() -> String {
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
    }
}

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let performanceScore: Double
    let tss: Double
    let consistency: Double
}

//            let segmentDisplayName = "Segment \(comparisons.count + 1)"

