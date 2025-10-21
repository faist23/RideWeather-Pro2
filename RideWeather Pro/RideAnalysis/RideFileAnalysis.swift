//
//  RideFileAnalysis.swift
//  RideWeather Pro
//

import Foundation
import SwiftUI
import CoreLocation
import Combine
import UniformTypeIdentifiers
import FitFileParser

// MARK: - FIT File Parser Models

struct FITRecord {
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let power: Int?
    let heartRate: Int?
    let cadence: Int?
    let speed: Double? // m/s
    let temperature: Double?
    let distance: Double? // meters
}

struct ParsedRideFile {
    let fileName: String
    let startTime: Date
    let endTime: Date
    let totalDuration: TimeInterval
    let movingTime: TimeInterval
    let totalDistance: Double // meters
    let records: [FITRecord]
    let hasPowerData: Bool
    let hasHeartRateData: Bool
    let hasGPSData: Bool
    
    var averageSpeed: Double {
        movingTime > 0 ? totalDistance / movingTime : 0
    }
    
    var averagePower: Double? {
        guard hasPowerData else { return nil }
        let powers = records.compactMap { $0.power }
        guard !powers.isEmpty else { return nil }
        return Double(powers.reduce(0, +)) / Double(powers.count)
    }
    
    var averageHeartRate: Double? {
        guard hasHeartRateData else { return nil }
        let hrs = records.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return nil }
        return Double(hrs.reduce(0, +)) / Double(hrs.count)
    }
    
    var route: [CLLocationCoordinate2D] {
        records.compactMap { record in
            guard let lat = record.latitude, let lon = record.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
}

// MARK: - Ride Analysis Models

struct RideAnalysis {
    let parsedFile: ParsedRideFile
    let powerMetrics: PowerMetrics?
    let paceAnalysis: PaceAnalysis
    let segmentAnalysis: [SegmentComparison]
    let deviations: [PaceDeviation]
    let insights: [RideInsight]
    let weatherComparison: WeatherComparison?
    
    var performanceScore: Double {
        calculatePerformanceScore()
    }
    
    private func calculatePerformanceScore() -> Double {
        var score: Double = 50.0
        score += (100 - paceAnalysis.variabilityIndex) * 0.2
        
        if let metrics = powerMetrics {
            let efficiencyRatio = metrics.normalizedPower / metrics.averagePower
            if efficiencyRatio < 1.05 {
                score += 15
            } else if efficiencyRatio < 1.10 {
                score += 10
            } else if efficiencyRatio < 1.15 {
                score += 5
            }
        }
        
        let majorDeviations = deviations.filter { $0.severity == .major }.count
        score -= Double(majorDeviations) * 5
        
        return min(100, max(0, score))
    }
}

struct PowerMetrics {
    let averagePower: Double
    let normalizedPower: Double
    let intensityFactor: Double
    let tss: Double
    let variabilityIndex: Double
    let peakPowers: [Duration: Int]
    let powerDistribution: [PowerZoneTime]
    
    struct PowerZoneTime {
        let zone: PowerZone
        let seconds: TimeInterval
        let percentage: Double
    }
}

struct PaceAnalysis {
    let segments: [PaceSegment]
    let overallConsistency: Double
    let variabilityIndex: Double
    let fatigueDetected: Bool
    let fatiguePoint: TimeInterval?
    
    struct PaceSegment {
        let startTime: TimeInterval
        let duration: TimeInterval
        let avgPower: Double?
        let avgSpeed: Double
        let trend: Trend
        
        enum Trend {
            case steady
            case increasing
            case decreasing
        }
    }
}

struct SegmentComparison {
    let segmentIndex: Int
    let segmentName: String
    let planned: PlannedSegment
    let actual: ActualSegment
    let deviation: Deviation
    let analysis: String
    
    struct PlannedSegment {
        let targetPower: Double
        let targetTime: TimeInterval
        let strategy: String
    }
    
    struct ActualSegment {
        let actualPower: Double?
        let actualTime: TimeInterval
        let actualSpeed: Double
    }
    
    struct Deviation {
        let powerDelta: Double?
        let timeDelta: TimeInterval
        let severity: DeviationSeverity
    }
}

enum DeviationSeverity {
    case none
    case minor
    case moderate
    case major
    
    var color: Color {
        switch self {
        case .none: return .green
        case .minor: return .yellow
        case .moderate: return .orange
        case .major: return .red
        }
    }
    
    var description: String {
        switch self {
        case .none: return "On Target"
        case .minor: return "Slight Deviation"
        case .moderate: return "Notable Deviation"
        case .major: return "Major Deviation"
        }
    }
}

struct PaceDeviation {
    let timeStamp: TimeInterval
    let location: CLLocationCoordinate2D?
    let type: DeviationType
    let severity: DeviationSeverity
    let description: String
    let impact: String
    
    enum DeviationType {
        case powerTooHigh
        case powerTooLow
        case tooFast
        case tooSlow
        case inconsistent
        case surge
    }
}

struct RideInsight: Identifiable {
    let id = UUID()
    let category: Category
    let title: String
    let description: String
    let recommendation: String
    let priority: Priority
    
    enum Category {
        case pacing
        case power
        case nutrition
        case strategy
        case equipment
        case conditions
    }
    
    enum Priority {
        case high
        case medium
        case low
        
        var color: Color {
            switch self {
            case .high: return .red
            case .medium: return .orange
            case .low: return .blue
            }
        }
    }
}

struct WeatherComparison {
    let plannedConditions: PlannedConditions
    let actualConditions: ActualConditions?
    let impact: WeatherImpact
    
    struct PlannedConditions {
        let temperature: Double
        let windSpeed: Double
        let windDirection: Double
    }
    
    struct ActualConditions {
        let temperature: Double
        let windSpeed: Double?
        let windDirection: Double?
    }
    
    struct WeatherImpact {
        let temperatureDelta: Double
        let windImpact: String
        let overallEffect: String
    }
}

// MARK: - Ride File Analyzer

@MainActor
final class RideFileAnalyzer: ObservableObject {
    @Published var analysis: RideAnalysis?
    @Published var isAnalyzing = false
    @Published var error: String?
    
    private let originalPlan: PacingPlan
    private let settings: AppSettings
    
    enum ParseError: LocalizedError {
        case noActivityData
        
        var errorDescription: String? {
            "No activity data found in FIT file"
        }
    }
    
    init(originalPlan: PacingPlan, settings: AppSettings) {
        self.originalPlan = originalPlan
        self.settings = settings
    }
    
    func analyzeRideFile(_ fileURL: URL) async {
        isAnalyzing = true
        error = nil
        
        do {
            print("🔍 Starting ride file analysis...")
            
            // Parse the FIT file
            let parsedFile = try await parseFITFile(fileURL)
            
            print("📊 File parsed, starting analysis...")
            
            // Analyze power metrics
            let powerMetrics = parsedFile.hasPowerData
                ? calculatePowerMetrics(from: parsedFile)
                : nil
            
            // Analyze pacing
            let paceAnalysis = analyzePacing(from: parsedFile)
            
            // Compare to planned segments
            let segmentComparison = compareSegments(
                planned: originalPlan.segments,
                actual: parsedFile
            )
            
            // Identify deviations
            let deviations = identifyDeviations(
                planned: originalPlan,
                actual: parsedFile
            )
            
            // Generate insights
            let insights = generateInsights(
                parsedFile: parsedFile,
                powerMetrics: powerMetrics,
                paceAnalysis: paceAnalysis,
                deviations: deviations
            )
            
            // Weather comparison (if available)
            let weatherComparison = compareWeatherConditions(parsedFile)
            
            analysis = RideAnalysis(
                parsedFile: parsedFile,
                powerMetrics: powerMetrics,
                paceAnalysis: paceAnalysis,
                segmentAnalysis: segmentComparison,
                deviations: deviations,
                insights: insights,
                weatherComparison: weatherComparison
            )
            
            print("✅ Ride analysis complete!")
            
        } catch {
            self.error = error.localizedDescription
            print("❌ Analysis failed: \(error.localizedDescription)")
        }
        
        isAnalyzing = false
    }
    
    // MARK: - FIT File Parsing
    
    private func parseFITFile(_ fileURL: URL) async throws -> ParsedRideFile {
        print("📂 Starting FIT file parse: \(fileURL.lastPathComponent)")
        
        let data = try Data(contentsOf: fileURL)
        print("   File size: \(data.count) bytes")
        
        // Use the FitFileParser library
        let fitFile = FitFile(data: data)
        
        // Get all record messages
        let records = fitFile.messages(forMessageType: .record)
        print("   Found \(records.count) record messages")
        
        var fitRecords: [FITRecord] = []
        var startTime: Date?
        var endTime: Date?
        
        for (index, msg) in records.enumerated() {
            // Use reflection to access the message data
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
            
            guard let values = valuesDict else { continue }
            
            // Extract timestamp
            var timestamp: Date?
            if let dates = datesDict {
                timestamp = dates["timestamp"]
            }
            
            if startTime == nil, let ts = timestamp {
                startTime = ts
            }
            if let ts = timestamp {
                endTime = ts
            }
            
            // Extract GPS coordinates (in semicircles, need to convert)
            var latitude: Double?
            var longitude: Double?
            if let lat = values["position_lat"], let lon = values["position_long"] {
                latitude = lat * (180.0 / pow(2.0, 31.0))
                longitude = lon * (180.0 / pow(2.0, 31.0))
            }
            
            // Extract altitude
            var altitude: Double?
            let altitudeKeys = ["enhanced_altitude", "altitude", "enhanced_alt", "alt"]
            for key in altitudeKeys {
                if let alt = values[key] {
                    altitude = alt
                    break
                }
            }
            
            // Extract power
            var power: Int?
            if let powerValue = values["power"] {
                power = Int(powerValue)
            }
            
            // Extract heart rate
            var heartRate: Int?
            if let hrValue = values["heart_rate"] {
                heartRate = Int(hrValue)
            }
            
            // Extract cadence
            var cadence: Int?
            if let cadenceValue = values["cadence"] {
                cadence = Int(cadenceValue)
            }
            
            // Extract speed (m/s)
            var speed: Double?
            let speedKeys = ["enhanced_speed", "speed"]
            for key in speedKeys {
                if let speedValue = values[key] {
                    speed = speedValue
                    break
                }
            }
            
            // Extract temperature
            var temperature: Double?
            if let tempValue = values["temperature"] {
                temperature = tempValue
            }
            
            // Extract distance (cumulative, in meters)
            var distance: Double?
            if let distValue = values["distance"] {
                distance = distValue
            }
            
            // Debug first few records
            if index < 3 {
                print("   Record \(index + 1):")
                print("      Power: \(power ?? -1)W")
                print("      HR: \(heartRate ?? -1)bpm")
                print("      Speed: \(String(format: "%.1f", (speed ?? 0) * 3.6))km/h")
                print("      Distance: \(String(format: "%.1f", (distance ?? 0) / 1000))km")
            }
            
            let record = FITRecord(
                timestamp: timestamp ?? Date(),
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                power: power,
                heartRate: heartRate,
                cadence: cadence,
                speed: speed,
                temperature: temperature,
                distance: distance
            )
            
            fitRecords.append(record)
        }
        
        guard !fitRecords.isEmpty else {
            throw ParseError.noActivityData
        }
        
        // Calculate metrics
        let actualStartTime = startTime ?? Date()
        let actualEndTime = endTime ?? Date()
        let totalDuration = actualEndTime.timeIntervalSince(actualStartTime)
        
        // Calculate moving time
        var movingTime: TimeInterval = 0
        for i in 1..<fitRecords.count {
            let timeDiff = fitRecords[i].timestamp.timeIntervalSince(fitRecords[i - 1].timestamp)
            if let speed = fitRecords[i].speed, speed > 1.0 {
                movingTime += timeDiff
            }
        }
        
        // Total distance from last record
        let totalDistance = fitRecords.last?.distance ?? 0
        
        // Check what data we have
        let hasPower = fitRecords.contains { $0.power != nil }
        let hasHR = fitRecords.contains { $0.heartRate != nil }
        let hasGPS = fitRecords.contains { $0.latitude != nil && $0.longitude != nil }
        
        // Calculate average metrics for verification
        let powerValues = fitRecords.compactMap { $0.power }
        let hrValues = fitRecords.compactMap { $0.heartRate }
        
        if !powerValues.isEmpty {
            let avgPower = Double(powerValues.reduce(0, +)) / Double(powerValues.count)
            print("   ✅ Average Power: \(Int(avgPower))W")
        }
        
        if !hrValues.isEmpty {
            let avgHR = Double(hrValues.reduce(0, +)) / Double(hrValues.count)
            print("   ✅ Average HR: \(Int(avgHR))bpm")
        }
        
        print("✅ FIT file parsed successfully:")
        print("   Duration: \(formatDuration(totalDuration))")
        print("   Moving Time: \(formatDuration(movingTime))")
        print("   Distance: \(String(format: "%.2f km", totalDistance / 1000))")
        print("   Records: \(fitRecords.count)")
        print("   Has Power: \(hasPower)")
        print("   Has HR: \(hasHR)")
        print("   Has GPS: \(hasGPS)")
        
        return ParsedRideFile(
            fileName: fileURL.lastPathComponent,
            startTime: actualStartTime,
            endTime: actualEndTime,
            totalDuration: totalDuration,
            movingTime: movingTime,
            totalDistance: totalDistance,
            records: fitRecords,
            hasPowerData: hasPower,
            hasHeartRateData: hasHR,
            hasGPSData: hasGPS
        )
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    // MARK: - Analysis Methods
    
    private func calculatePowerMetrics(from file: ParsedRideFile) -> PowerMetrics {
        let powers = file.records.compactMap { $0.power }
        guard !powers.isEmpty else {
            return PowerMetrics(
                averagePower: 0,
                normalizedPower: 0,
                intensityFactor: 0,
                tss: 0,
                variabilityIndex: 0,
                peakPowers: [:],
                powerDistribution: []
            )
        }
        
        print("📊 Calculating power metrics from \(powers.count) power samples")
        
        // Average Power
        let avgPower = Double(powers.reduce(0, +)) / Double(powers.count)
        
        // Normalized Power
        let np = calculateNormalizedPower(powers)
        
        print("   Average Power: \(Int(avgPower))W")
        print("   Normalized Power: \(Int(np))W")
        
        // Intensity Factor
        let ftp = Double(settings.functionalThresholdPower)
        let intensityFactor = ftp > 0 ? np / ftp : 0
        
        // TSS
        let durationHours = file.movingTime / 3600.0
        let tss = durationHours * pow(intensityFactor, 2) * 100
        
        print("   IF: \(String(format: "%.2f", intensityFactor)), TSS: \(Int(tss))")
        
        // Variability Index
        let vi = avgPower > 0 ? np / avgPower : 1.0
        
        // Peak Powers
        let peakPowers = calculatePeakPowers(powers)
        
        // Power Distribution
        let distribution = calculatePowerDistribution(powers, ftp: ftp, duration: file.movingTime)
        
        return PowerMetrics(
            averagePower: avgPower,
            normalizedPower: np,
            intensityFactor: intensityFactor,
            tss: tss,
            variabilityIndex: vi,
            peakPowers: peakPowers,
            powerDistribution: distribution
        )
    }
    
    private func calculateNormalizedPower(_ powers: [Int]) -> Double {
        guard !powers.isEmpty else { return 0.0 }
        
        let windowSize = 30
        var rollingAverages: [Double] = []
        var windowSum: Double = 0
        var queue: [Int] = []
        
        for power in powers {
            queue.append(power)
            windowSum += Double(power)
            
            if queue.count > windowSize {
                windowSum -= Double(queue.removeFirst())
            }
            
            let count = queue.count
            if count > 0 {
                rollingAverages.append(windowSum / Double(count))
            }
        }
        
        guard !rollingAverages.isEmpty else { return 0.0 }
        
        let fourths = rollingAverages.map { pow($0, 4) }
        let meanOfFourths = fourths.reduce(0, +) / Double(fourths.count)
        
        return pow(meanOfFourths, 0.25)
    }
    
    private func calculatePeakPowers(_ powers: [Int]) -> [Duration: Int] {
        var peaks: [Duration: Int] = [:]
        
        guard !powers.isEmpty else { return peaks }
        
        let durations: [Duration] = [.seconds(5), .seconds(60), .seconds(300), .seconds(1200)]
        
        for duration in durations {
            let windowSize = max(1, duration.seconds / 10)
            
            guard powers.count >= windowSize else {
                continue
            }
            
            var maxAvg = 0
            
            for i in 0...(powers.count - windowSize) {
                let window = powers[i..<(i + windowSize)]
                let sum = window.reduce(0, +)
                let avg = sum / windowSize
                maxAvg = max(maxAvg, avg)
            }
            
            peaks[duration] = maxAvg
        }
        
        return peaks
    }
    
    private func calculatePowerDistribution(
        _ powers: [Int],
        ftp: Double,
        duration: TimeInterval
    ) -> [PowerMetrics.PowerZoneTime] {
        let zones = PowerZone.zones(for: ftp)
        var distribution: [PowerMetrics.PowerZoneTime] = []
        
        for zone in zones {
            let powersInZone = powers.filter { power in
                Double(power) >= zone.minPower && Double(power) <= zone.maxPower
            }
            
            let seconds = Double(powersInZone.count) * 10
            let percentage = (seconds / duration) * 100
            
            distribution.append(PowerMetrics.PowerZoneTime(
                zone: zone,
                seconds: seconds,
                percentage: percentage
            ))
        }
        
        return distribution
    }
    
    private func analyzePacing(from file: ParsedRideFile) -> PaceAnalysis {
        let segmentDuration: TimeInterval = 600
        let segmentCount = Int(file.movingTime / segmentDuration)
        
        var segments: [PaceAnalysis.PaceSegment] = []
        
        for i in 0..<segmentCount {
            let startIdx = i * 60
            let endIdx = min(startIdx + 60, file.records.count)
            let segmentRecords = Array(file.records[startIdx..<endIdx])
            
            let avgPower = segmentRecords.compactMap { $0.power }.average
            let avgSpeed = segmentRecords.compactMap { $0.speed }.average ?? 0
            
            let trend: PaceAnalysis.PaceSegment.Trend
            if i > 0, let prevPower = segments.last?.avgPower, let currentPower = avgPower {
                let change = (currentPower - prevPower) / prevPower
                if abs(change) < 0.05 {
                    trend = .steady
                } else if change > 0 {
                    trend = .increasing
                } else {
                    trend = .decreasing
                }
            } else {
                trend = .steady
            }
            
            segments.append(PaceAnalysis.PaceSegment(
                startTime: Double(i) * segmentDuration,
                duration: segmentDuration,
                avgPower: avgPower,
                avgSpeed: avgSpeed,
                trend: trend
            ))
        }
        
        let powerCV = calculateCoeffientOfVariation(segments.compactMap { $0.avgPower })
        let consistency = max(0, 100 - (powerCV * 100))
        
        let (fatigueDetected, fatiguePoint) = detectFatigue(segments: segments)
        
        return PaceAnalysis(
            segments: segments,
            overallConsistency: consistency,
            variabilityIndex: powerCV,
            fatigueDetected: fatigueDetected,
            fatiguePoint: fatiguePoint
        )
    }
    
    private func compareSegments(
        planned: [PacedSegment],
        actual: ParsedRideFile
    ) -> [SegmentComparison] {
        var comparisons: [SegmentComparison] = []
        
        print("🔍 Comparing \(planned.count) planned segments to actual ride data")
        
        let totalActualDistance = actual.records.last?.distance ?? 0
        print("   Actual ride distance: \(String(format: "%.1f", totalActualDistance / 1000))km")
        
        var cumulativeDistance: Double = 0
        
        for (index, plannedSegment) in planned.enumerated() {
            let segmentStartDistance = cumulativeDistance
            let segmentEndDistance = segmentStartDistance + plannedSegment.distanceKm * 1000
            
            if segmentStartDistance >= totalActualDistance {
                print("   ⚠️ Stopped comparison at segment \(index + 1) - beyond actual ride distance")
                break
            }
            
            let actualRecords = actual.records.filter { record in
                guard let distance = record.distance else { return false }
                return distance >= segmentStartDistance && distance < min(segmentEndDistance, totalActualDistance)
            }
            
            guard !actualRecords.isEmpty else {
                print("   ⚠️ No data for segment \(index + 1)")
                cumulativeDistance = segmentEndDistance
                continue
            }
            
            let actualPower = actualRecords.compactMap { $0.power }.average
            let actualTime: TimeInterval
            
            if actualRecords.count > 1,
               let firstTime = actualRecords.first?.timestamp,
               let lastTime = actualRecords.last?.timestamp {
                actualTime = lastTime.timeIntervalSince(firstTime)
            } else {
                actualTime = plannedSegment.estimatedTime
            }
            
            let actualSpeed = actualRecords.compactMap { $0.speed }.average ?? 0
            
            let powerDelta = actualPower.map { $0 - plannedSegment.targetPower }
            let timeDelta = actualTime - plannedSegment.estimatedTime
            
            let severity: DeviationSeverity
            if let powerDelta = powerDelta {
                let powerDeviation = abs(powerDelta / plannedSegment.targetPower)
                let timeDeviation = actualTime > 0 ? abs(timeDelta / plannedSegment.estimatedTime) : 0
                
                if powerDeviation > 0.15 || timeDeviation > 0.15 {
                    severity = .major
                } else if powerDeviation > 0.10 || timeDeviation > 0.10 {
                    severity = .moderate
                } else if powerDeviation > 0.05 || timeDeviation > 0.05 {
                    severity = .minor
                } else {
                    severity = .none
                }
            } else {
                severity = .none
            }
            
            let analysis = generateSegmentAnalysis(
                plannedPower: plannedSegment.targetPower,
                actualPower: actualPower,
                powerDelta: powerDelta,
                timeDelta: timeDelta
            )
            
            comparisons.append(SegmentComparison(
                segmentIndex: index,
                segmentName: "Segment \(index + 1)",
                planned: SegmentComparison.PlannedSegment(
                    targetPower: plannedSegment.targetPower,
                    targetTime: plannedSegment.estimatedTime,
                    strategy: plannedSegment.strategy
                ),
                actual: SegmentComparison.ActualSegment(
                    actualPower: actualPower,
                    actualTime: actualTime,
                    actualSpeed: actualSpeed
                ),
                deviation: SegmentComparison.Deviation(
                    powerDelta: powerDelta,
                    timeDelta: timeDelta,
                    severity: severity
                ),
                analysis: analysis
            ))
            
            cumulativeDistance = segmentEndDistance
        }
        
        print("   ✅ Created \(comparisons.count) segment comparisons")
        return comparisons
    }
    
    private func identifyDeviations(
        planned: PacingPlan,
        actual: ParsedRideFile
    ) -> [PaceDeviation] {
        var deviations: [PaceDeviation] = []
        
        if let powers = actual.records.compactMap({ $0.power }) as [Int]? {
            let avgPower = powers.average ?? 0
            
            for (index, record) in actual.records.enumerated() {
                guard let power = record.power else { continue }
                
                if Double(power) > avgPower * 1.3 {
                    deviations.append(PaceDeviation(
                        timeStamp: record.timestamp.timeIntervalSince(actual.startTime),
                        location: CLLocationCoordinate2D(
                            latitude: record.latitude ?? 0,
                            longitude: record.longitude ?? 0
                        ),
                        type: .surge,
                        severity: .moderate,
                        description: "Power surge to \(power)W",
                        impact: "Unnecessary energy expenditure"
                    ))
                }
            }
        }
        
        return deviations
    }
    
    private func generateInsights(
        parsedFile: ParsedRideFile,
        powerMetrics: PowerMetrics?,
        paceAnalysis: PaceAnalysis,
        deviations: [PaceDeviation]
    ) -> [RideInsight] {
        var insights: [RideInsight] = []
        
        if paceAnalysis.overallConsistency > 85 {
            insights.append(RideInsight(
                category: .pacing,
                title: "Excellent Pacing",
                description: "You maintained very consistent power throughout the ride (\(Int(paceAnalysis.overallConsistency))% consistency)",
                recommendation: "This pacing strategy worked well. Consider using it for similar rides.",
                priority: .low
            ))
        } else if paceAnalysis.overallConsistency < 70 {
            insights.append(RideInsight(
                category: .pacing,
                title: "Inconsistent Pacing",
                description: "Power varied significantly throughout the ride (\(Int(paceAnalysis.overallConsistency))% consistency)",
                recommendation: "Focus on maintaining steadier power output. Use a power target display on your bike computer.",
                priority: .high
            ))
        }
        
        if let metrics = powerMetrics {
            if metrics.variabilityIndex > 1.10 {
                insights.append(RideInsight(
                    category: .power,
                    title: "High Power Variability",
                    description: "Variability Index of \(String(format: "%.2f", metrics.variabilityIndex)) suggests inefficient power distribution",
                    recommendation: "Reduce power surges and maintain steadier output. This will improve endurance.",
                    priority: .high
                ))
            }
        }
        
        // Fatigue insight
        if paceAnalysis.fatigueDetected, let fatiguePoint = paceAnalysis.fatiguePoint {
            let fatigueMinutes = Int(fatiguePoint / 60)
            insights.append(RideInsight(
                category: .strategy,
                title: "Early Fatigue Detected",
                description: "Power output declined significantly after \(fatigueMinutes) minutes",
                recommendation: "Consider a more conservative early pace or increase endurance training.",
                priority: .high
            ))
        }
        
        // Surge insight
        let surgeCount = deviations.filter { $0.type == .surge }.count
        if surgeCount > 5 {
            insights.append(RideInsight(
                category: .pacing,
                title: "Frequent Power Surges",
                description: "Detected \(surgeCount) significant power spikes during the ride",
                recommendation: "Avoid unnecessary surges. They waste energy without proportional speed gains.",
                priority: .medium
            ))
        }
        
        return insights
    }
    
    private func compareWeatherConditions(_ file: ParsedRideFile) -> WeatherComparison? {
        // This would integrate with actual weather data
        // For now, return nil
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func detectFatigue(segments: [PaceAnalysis.PaceSegment]) -> (detected: Bool, point: TimeInterval?) {
        guard segments.count >= 3 else { return (false, nil) }
        
        let firstThirdAvg = segments.prefix(segments.count / 3).compactMap { $0.avgPower }.average ?? 0
        let lastThirdAvg = segments.suffix(segments.count / 3).compactMap { $0.avgPower }.average ?? 0
        
        let decline = (firstThirdAvg - lastThirdAvg) / firstThirdAvg
        
        if decline > 0.15 {
            // Find where decline started
            for (index, segment) in segments.enumerated() {
                if let power = segment.avgPower, power < firstThirdAvg * 0.90 {
                    return (true, segment.startTime)
                }
            }
        }
        
        return (false, nil)
    }
    
    private func calculateCoeffientOfVariation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        let stdDev = sqrt(variance)
        return mean > 0 ? stdDev / mean : 0
    }
    
    private func generateSegmentAnalysis(
        plannedPower: Double,
        actualPower: Double?,
        powerDelta: Double?,
        timeDelta: TimeInterval
    ) -> String {
        guard let actualPower = actualPower, let powerDelta = powerDelta else {
            return "No power data available for this segment"
        }
        
        var analysis = ""
        
        if abs(powerDelta) < plannedPower * 0.05 {
            analysis = "Excellent execution - power was within 5% of target"
        } else if powerDelta > 0 {
            let percentage = (powerDelta / plannedPower) * 100
            analysis = "Pushed \(Int(percentage))% harder than planned (\(Int(powerDelta))W over)"
            
            if timeDelta < 0 {
                analysis += " which resulted in finishing \(Int(abs(timeDelta)))s faster"
            } else {
                analysis += " but still finished \(Int(timeDelta))s slower - likely due to fatigue"
            }
        } else {
            let percentage = abs((powerDelta / plannedPower) * 100)
            analysis = "Rode \(Int(percentage))% easier than planned (\(Int(abs(powerDelta)))W under)"
            
            if timeDelta > 0 {
                analysis += " which resulted in finishing \(Int(timeDelta))s slower"
            }
        }
        
        return analysis
    }
}

// MARK: - Duration Helper

enum Duration: Hashable, Codable {
    case seconds(Int)
    
    var seconds: Int {
        switch self {
        case .seconds(let s): return s
        }
    }
    
    var displayString: String {
        let s = seconds
        if s < 60 {
            return "\(s)s"
        } else if s < 3600 {
            return "\(s / 60)min"
        } else {
            return "\(s / 3600)h"
        }
    }
}

// MARK: - Array Extensions

extension Array where Element == Int {
    var average: Double? {
        guard !isEmpty else { return nil }
        return Double(reduce(0, +)) / Double(count)
    }
}

extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

// MARK: - UI Views

struct RideFileAnalysisView: View {
    @StateObject private var analyzer: RideFileAnalyzer
    @State private var showingFilePicker = false
    @Environment(\.dismiss) private var dismiss
    
    let originalPlan: PacingPlan
    let settings: AppSettings
    
    init(originalPlan: PacingPlan, settings: AppSettings) {
        self.originalPlan = originalPlan
        self.settings = settings
        _analyzer = StateObject(wrappedValue: RideFileAnalyzer(
            originalPlan: originalPlan,
            settings: settings
        ))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if analyzer.isAnalyzing {
                    analyzingView
                } else if let analysis = analyzer.analysis {
                    analysisResultsView(analysis)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Ride File Analysis")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                
                if analyzer.analysis != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Analysis") {
                            showingFilePicker = true
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("Analyze Your Ride")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Import a .fit or .gpx file to compare your actual performance against your plan")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button(action: { showingFilePicker = true }) {
                Label("Import Ride File", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Supported Formats:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                ForEach([
                    ("FIT files from Garmin, Wahoo, and other devices", "bicycle"),
                    ("GPX files with power data", "map"),
                    ("TCX files from Strava exports", "arrow.down.doc")
                ], id: \.0) { item in
                    HStack {
                        Image(systemName: item.1)
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        Text(item.0)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)
        }
        .padding()
    }
    
    private var analyzingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Analyzing Ride File...")
                .font(.headline)
            
            Text("Comparing actual performance to your plan")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func analysisResultsView(_ analysis: RideAnalysis) -> some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Performance Score Card
                PerformanceScoreCard(analysis: analysis)
                
                // Key Metrics Overview
                RideMetricsCard(analysis: analysis)
                
                // Power Analysis (if available)
                if let powerMetrics = analysis.powerMetrics {
                    PowerAnalysisCard(metrics: powerMetrics, settings: settings)
                }
                
                // Pacing Analysis
                PacingAnalysisCard(paceAnalysis: analysis.paceAnalysis)
                
                // Segment Comparison
                if !analysis.segmentAnalysis.isEmpty {
                    SegmentComparisonCard(segments: analysis.segmentAnalysis)
                }
                
                // Insights & Recommendations
                if !analysis.insights.isEmpty {
                    InsightsCard(insights: analysis.insights)
                }
                
                // Deviations (if any)
                if !analysis.deviations.isEmpty {
                    DeviationsCard(deviations: analysis.deviations)
                }
            }
            .padding()
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            Task {
                await analyzer.analyzeRideFile(fileURL)
            }
        case .failure(let error):
            analyzer.error = error.localizedDescription
        }
    }
}

// MARK: - Performance Score Card

struct PerformanceScoreCard: View {
    let analysis: RideAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Performance Score")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(scoreRating)
                        .font(.subheadline)
                        .foregroundStyle(scoreColor)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: analysis.performanceScore / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(analysis.performanceScore))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor)
                }
            }
            
            Text(scoreDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var scoreColor: Color {
        switch analysis.performanceScore {
        case 85...100: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
    
    private var scoreRating: String {
        switch analysis.performanceScore {
        case 85...100: return "Excellent"
        case 70..<85: return "Good"
        case 50..<70: return "Fair"
        default: return "Needs Improvement"
        }
    }
    
    private var scoreDescription: String {
        switch analysis.performanceScore {
        case 85...100:
            return "You executed your plan very well with consistent pacing and minimal deviations"
        case 70..<85:
            return "Solid execution with some minor deviations from the plan"
        case 50..<70:
            return "Several areas for improvement in pacing and power distribution"
        default:
            return "Significant deviations from plan - review insights for improvement areas"
        }
    }
}

// MARK: - Ride Metrics Card

struct RideMetricsCard: View {
    let analysis: RideAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ride Summary")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                MetricItem(
                    title: "Duration",
                    value: formatDuration(analysis.parsedFile.totalDuration),
                    icon: "clock"
                )
                
                MetricItem(
                    title: "Distance",
                    value: String(format: "%.1f km", analysis.parsedFile.totalDistance / 1000),
                    icon: "road.lanes"
                )
                
                MetricItem(
                    title: "Avg Speed",
                    value: String(format: "%.1f km/h", analysis.parsedFile.averageSpeed * 3.6),
                    icon: "speedometer"
                )
                
                if let avgPower = analysis.parsedFile.averagePower {
                    MetricItem(
                        title: "Avg Power",
                        value: "\(Int(avgPower))W",
                        icon: "bolt"
                    )
                }
                
                if let avgHR = analysis.parsedFile.averageHeartRate {
                    MetricItem(
                        title: "Avg HR",
                        value: "\(Int(avgHR)) bpm",
                        icon: "heart"
                    )
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct MetricItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Power Analysis Card

struct PowerAnalysisCard: View {
    let metrics: PowerMetrics
    let settings: AppSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Power Analysis", systemImage: "bolt.fill")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
            
            // Key Power Metrics
            HStack(spacing: 20) {
                PowerMetricBox(
                    title: "Normalized Power",
                    value: "\(Int(metrics.normalizedPower))W",
                    subtitle: "IF \(String(format: "%.2f", metrics.intensityFactor))"
                )
                
                PowerMetricBox(
                    title: "Average Power",
                    value: "\(Int(metrics.averagePower))W",
                    subtitle: "VI \(String(format: "%.2f", metrics.variabilityIndex))"
                )
                
                PowerMetricBox(
                    title: "Training Load",
                    value: "\(Int(metrics.tss))",
                    subtitle: "TSS"
                )
            }
            
            Divider()
            
            // Peak Powers
            VStack(alignment: .leading, spacing: 8) {
                Text("Peak Powers")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(Array(metrics.peakPowers.sorted(by: { $0.key.seconds < $1.key.seconds })), id: \.key) { duration, power in
                    HStack {
                        Text(duration.displayString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        
                        ProgressView(value: Double(power), total: Double(settings.functionalThresholdPower) * 1.5)
                            .tint(.orange)
                        
                        Text("\(power)W")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            
            Divider()
            
            // Power Distribution
            VStack(alignment: .leading, spacing: 8) {
                Text("Time in Zones")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(metrics.powerDistribution.filter { $0.seconds > 0 }, id: \.zone.number) { zoneTime in
                    HStack {
                        Circle()
                            .fill(Color(hex: zoneTime.zone.color))
                            .frame(width: 8, height: 8)
                        
                        Text(zoneTime.zone.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        
                        ProgressView(value: zoneTime.percentage, total: 100)
                            .tint(Color(hex: zoneTime.zone.color))
                        
                        Text(String(format: "%.0f%%", zoneTime.percentage))
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PowerMetricBox: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pacing Analysis Card

struct PacingAnalysisCard: View {
    let paceAnalysis: PaceAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Pacing Analysis", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Consistency Score
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pacing Consistency")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("\(Int(paceAnalysis.overallConsistency))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(consistencyColor)
                }
                
                Spacer()
                
                if paceAnalysis.fatigueDetected {
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Fatigue Detected")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Divider()
            
            // Segment Trends
            VStack(alignment: .leading, spacing: 8) {
                Text("Power Trends")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(Array(paceAnalysis.segments.enumerated()), id: \.offset) { index, segment in
                    HStack {
                        Text("Segment \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        
                        TrendIndicator(trend: segment.trend)
                        
                        if let power = segment.avgPower {
                            Text("\(Int(power))W")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var consistencyColor: Color {
        switch paceAnalysis.overallConsistency {
        case 85...100: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
}

struct TrendIndicator: View {
    let trend: PaceAnalysis.PaceSegment.Trend
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(color)
        }
    }
    
    private var icon: String {
        switch trend {
        case .steady: return "arrow.right"
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        }
    }
    
    private var color: Color {
        switch trend {
        case .steady: return .green
        case .increasing: return .blue
        case .decreasing: return .orange
        }
    }
    
    private var label: String {
        switch trend {
        case .steady: return "Steady"
        case .increasing: return "Rising"
        case .decreasing: return "Fading"
        }
    }
}

// MARK: - Segment Comparison Card

struct SegmentComparisonCard: View {
    let segments: [SegmentComparison]
    @State private var expandedSegments: Set<Int> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Planned vs Actual", systemImage: "chart.bar.xaxis")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVStack(spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    SegmentComparisonRow(
                        segment: segment,
                        isExpanded: expandedSegments.contains(index)
                    ) {
                        withAnimation {
                            if expandedSegments.contains(index) {
                                expandedSegments.remove(index)
                            } else {
                                expandedSegments.insert(index)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SegmentComparisonRow: View {
    let segment: SegmentComparison
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(segment.segmentName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(segment.deviation.severity.description)
                            .font(.caption)
                            .foregroundStyle(segment.deviation.severity.color)
                    }
                    
                    Spacer()
                    
                    if let powerDelta = segment.deviation.powerDelta {
                        Text("\(powerDelta > 0 ? "+" : "")\(Int(powerDelta))W")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(powerDelta > 0 ? .orange : .blue)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(segment.deviation.severity.color.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    // Comparison metrics
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                        ComparisonMetric(
                            label: "Target Power",
                            value: "\(Int(segment.planned.targetPower))W"
                        )
                        
                        if let actualPower = segment.actual.actualPower {
                            ComparisonMetric(
                                label: "Actual Power",
                                value: "\(Int(actualPower))W"
                            )
                        }
                        
                        ComparisonMetric(
                            label: "Target Time",
                            value: formatTime(segment.planned.targetTime)
                        )
                        
                        ComparisonMetric(
                            label: "Actual Time",
                            value: formatTime(segment.actual.actualTime)
                        )
                    }
                    
                    // Analysis text
                    Text(segment.analysis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(12)
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

struct ComparisonMetric: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Insights Card

struct InsightsCard: View {
    let insights: [RideInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Insights & Recommendations", systemImage: "lightbulb.fill")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.yellow)
            
            ForEach(insights) { insight in
                InsightRow(insight: insight)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct InsightRow: View {
    let insight: RideInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: categoryIcon)
                    .foregroundStyle(insight.priority.color)
                
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(insight.priority == .high ? "HIGH" : insight.priority == .medium ? "MED" : "LOW")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(insight.priority.color.opacity(0.2))
                    .foregroundStyle(insight.priority.color)
                    .clipShape(Capsule())
            }
            
            Text(insight.description)
                .font(.caption)
                .foregroundStyle(.primary)
            
            HStack {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                
                Text(insight.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(insight.priority.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var categoryIcon: String {
        switch insight.category {
        case .pacing: return "gauge"
        case .power: return "bolt.fill"
        case .nutrition: return "fork.knife"
        case .strategy: return "map"
        case .equipment: return "bicycle"
        case .conditions: return "cloud.sun"
        }
    }
}

// MARK: - Deviations Card

struct DeviationsCard: View {
    let deviations: [PaceDeviation]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Notable Deviations", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
            
            Text("\(deviations.count) significant deviation\(deviations.count == 1 ? "" : "s") detected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ForEach(Array(deviations.prefix(5).enumerated()), id: \.offset) { index, deviation in
                DeviationRow(deviation: deviation)
            }
            
            if deviations.count > 5 {
                Text("+ \(deviations.count - 5) more deviations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DeviationRow: View {
    let deviation: PaceDeviation
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: deviationIcon)
                .foregroundStyle(deviation.severity.color)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatTime(deviation.timeStamp))
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(deviation.severity.description)
                        .font(.caption2)
                        .foregroundStyle(deviation.severity.color)
                }
                
                Text(deviation.description)
                    .font(.caption)
                    .foregroundStyle(.primary)
                
                Text(deviation.impact)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(deviation.severity.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
    
    private var deviationIcon: String {
        switch deviation.type {
        case .powerTooHigh, .tooFast, .surge: return "arrow.up.circle.fill"
        case .powerTooLow, .tooSlow: return "arrow.down.circle.fill"
        case .inconsistent: return "waveform.path"
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}
