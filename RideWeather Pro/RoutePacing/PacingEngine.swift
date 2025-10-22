//
//  PacingEngine.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation

// MARK: - Pacing Strategy Types

enum PacingStrategy: CaseIterable {
    case balanced
    case conservative
    case aggressive
    case negativeSplit
    case evenEffort
    
    var description: String {
        switch self {
        case .balanced: return "Balanced"
        case .conservative: return "Conservative"
        case .aggressive: return "Aggressive"
        case .negativeSplit: return "Negative Split"
        case .evenEffort: return "Even Effort"
        }
    }
}

struct PacedSegment {
    let originalSegment: PowerRouteSegment
    var targetPower: Double
    var estimatedTime: Double
    var powerZone: PowerZone
    let cumulativeStress: Double
    let strategy: String
    let paceAdjustment: Double // multiplier from base power
    
    var distanceKm: Double { originalSegment.distanceMeters / 1000.0 }
    var estimatedTimeMinutes: Double { estimatedTime / 60.0 }
}

struct PowerZone {
    let number: Int
    let name: String
    let minPower: Double
    let maxPower: Double
    let color: String // hex color for UI
    
    static func zones(for ftp: Double) -> [PowerZone] {
        return [
            PowerZone(number: 1, name: "Recovery", minPower: 0, maxPower: ftp * 0.55, color: "#9E9E9E"),
            PowerZone(number: 2, name: "Endurance", minPower: ftp * 0.55, maxPower: ftp * 0.75, color: "#2196F3"),
            PowerZone(number: 3, name: "Tempo", minPower: ftp * 0.75, maxPower: ftp * 0.87, color: "#4CAF50"),
            PowerZone(number: 4, name: "Sweet Spot", minPower: ftp * 0.87, maxPower: ftp * 0.94, color: "#FFFF00"),
            PowerZone(number: 5, name: "Threshold", minPower: ftp * 0.94, maxPower: ftp * 1.05, color: "#FF9800"),
            PowerZone(number: 6, name: "VO2 Max", minPower: ftp * 1.05, maxPower: ftp * 1.20, color: "#F44336"),
            PowerZone(number: 7, name: "Anaerobic", minPower: ftp * 1.20, maxPower: ftp * 1.50, color: "#9C27B0")
        ]
    }
}

struct PacingPlan {
    var segments: [PacedSegment]
    let strategy: PacingStrategy
    var totalTimeMinutes: Double
    let totalDistance: Double
    var averagePower: Double
    var normalizedPower: Double
    var estimatedTSS: Double
    var intensityFactor: Double
    var difficulty: DifficultyRating
    let startTime: Date
    var estimatedArrival: Date
    let summary: PacingSummary
    let ftp: Double

    mutating func recalculateMetrics() {
        guard !segments.isEmpty else {
            self.normalizedPower = 0
            self.intensityFactor = 0
            self.averagePower = 0
            self.estimatedTSS = 0
            return
        }

        // Expand segments into 1-second power samples for accuracy
        var samples: [Double] = []
        for segment in segments {
            let seconds = max(1, Int(segment.estimatedTime.rounded()))
            samples.append(contentsOf: Array(repeating: segment.targetPower, count: seconds))
        }

        // --- Recalculate Average Power ---
        self.averagePower = samples.reduce(0, +) / Double(samples.count)

        // --- Recalculate Normalized Power ---
        let windowSize = 30
        var rollingAverages: [Double] = []
        var windowSum: Double = 0
        var queue: [Double] = []

        for powerSample in samples {
            queue.append(powerSample)
            windowSum += powerSample
            if queue.count > windowSize {
                windowSum -= queue.removeFirst()
            }
            rollingAverages.append(windowSum / Double(queue.count))
        }

        let fourths = rollingAverages.map { pow($0, 4) }
        let meanOfFourths = fourths.reduce(0, +) / Double(fourths.count)
        let np = pow(meanOfFourths, 0.25)
        self.normalizedPower = np

        // --- Recalculate IF and TSS ---
        if self.ftp > 0 {
            self.intensityFactor = np / self.ftp
            let totalTimeHours = Double(samples.count) / 3600.0
            self.estimatedTSS = totalTimeHours * pow(self.intensityFactor, 2) * 100
        } else {
            self.intensityFactor = 0
            self.estimatedTSS = 0
        }
    }
    
    func applying(intensityAdjustment percentage: Double) -> PacingPlan {
        var newPlan = self
        
        if percentage == 0 {
            return newPlan
        }

        let multiplier = 1.0 + (percentage / 100.0)
        let powerZones = PowerZone.zones(for: newPlan.ftp)

        for i in 0..<newPlan.segments.count {
            let powerBeforeTweak = newPlan.segments[i].targetPower
            let timeBeforeTweak = newPlan.segments[i].estimatedTime

            let newTargetPower = powerBeforeTweak * multiplier
            newPlan.segments[i].targetPower = newTargetPower

            let powerRatio = newTargetPower / powerBeforeTweak
            if powerRatio > 0.1 {
                let timeAdjustment = pow(powerRatio, -1.0/3.0) // Physics approximation
                newPlan.segments[i].estimatedTime = timeBeforeTweak * timeAdjustment
            }
            
            newPlan.segments[i].powerZone = powerZones.first {
                newTargetPower <= $0.maxPower
            } ?? powerZones.last!
        }

        newPlan.recalculateMetrics()
        
        let totalTimeSeconds = newPlan.segments.reduce(0.0) { $0 + $1.estimatedTime }
        newPlan.totalTimeMinutes = totalTimeSeconds / 60.0
        newPlan.estimatedArrival = newPlan.startTime.addingTimeInterval(totalTimeSeconds)

        return newPlan
    }
}

struct PacingSummary {
    let totalElevation: Double
    let timeInZones: [Int: Double] // zone number -> minutes
    let keySegments: [KeySegment]
    let warnings: [String]
    let settings: AppSettings
}

struct KeySegment {
    let segmentIndex: Int
    let type: KeySegmentType
    let description: String
    let recommendation: String
}

enum KeySegmentType {
    case majorClimb
    case highIntensity
    case fuelOpportunity
    case technicalSection
    case recovery
}

enum DifficultyRating: String, CaseIterable {
    case recovery = "Recovery"
    case easy = "Easy"
    case moderate = "Moderate"
    case hard = "Hard"
    case veryHard = "Very Hard"
    
    var color: String {
        switch self {
        case .recovery: return "#9E9E9E"
        case .easy: return "#4CAF50"
        case .moderate: return "#FF9800"
        case .hard: return "#F44336"
        case .veryHard: return "#9C27B0"
        }
    }
}

// MARK: - Pacing Engine

final class PacingEngine {
    private let settings: AppSettings
    private let powerZones: [PowerZone]
    
    init(settings: AppSettings) {
        self.settings = settings
        self.powerZones = PowerZone.zones(for: Double(settings.functionalThresholdPower))
    }
    
    // MARK: - Public API
    
    func generatePacingPlan(
        from powerAnalysis: PowerRouteAnalysisResult,
        strategy: PacingStrategy = .balanced,
        startTime: Date = Date()
    ) -> PacingPlan {
        
        let segments = createPacedSegments(
            from: powerAnalysis.segments,
            strategy: strategy,
            totalDistance: powerAnalysis.segments.reduce(0) { $0 + $1.distanceMeters }
        )
        
        let totalTime = segments.reduce(0.0) { $0 + $1.estimatedTime }
        let totalDistance = segments.reduce(0.0) { $0 + $1.distanceKm }
        
        let avgPower = calculateAveragePower(segments: segments)
        let normalizedPower = calculateNormalizedPower(segments: segments)
        
        let tss = calculateTotalTSS(segments: segments, useNormalizedPower: true)
        let intensityFactor = normalizedPower > 0 ? normalizedPower / Double(settings.functionalThresholdPower) : 0
        let difficulty = assessDifficulty(tss: tss, intensityFactor: intensityFactor)
        let estimatedArrival = startTime.addingTimeInterval(totalTime)
        
        let summary = generateSummary(
            segments: segments,
            powerAnalysis: powerAnalysis
        )
        
        return PacingPlan(
            segments: segments,
            strategy: strategy,
            totalTimeMinutes: totalTime / 60.0,
            totalDistance: totalDistance,
            averagePower: avgPower,
            normalizedPower: normalizedPower,
            estimatedTSS: tss,
            intensityFactor: intensityFactor,
            difficulty: difficulty,
            startTime: startTime,
            estimatedArrival: estimatedArrival,
            summary: summary,
            ftp: Double(settings.functionalThresholdPower)
        )
    }
    
    // MARK: - Private Implementation
    
    private func createPacedSegments(
        from segments: [PowerRouteSegment],
        strategy: PacingStrategy,
        totalDistance: Double
    ) -> [PacedSegment] {
        
        print("🚴‍♂️ Creating paced segments for \(segments.count) segments")
        print("📏 Total distance: \(String(format: "%.1f", totalDistance/1000))km")
        
        let estimatedTotalTime = segments.reduce(0.0) { $0 + $1.timeSeconds }
        let totalDurationHours = estimatedTotalTime / 3600.0
        
        print("⏱️ Estimated total time: \(String(format: "%.1f", totalDurationHours))h")
        
        var cumulativeStress: Double = 0
        var pacedSegments: [PacedSegment] = []
        let ftp = Double(settings.functionalThresholdPower)
        
        print("💪 FTP: \(Int(ftp))W")
        
        for (index, segment) in segments.enumerated() {
            let rideProgress = Double(index) / Double(segments.count)
            
            print("\n🎯 Segment \(index + 1)/\(segments.count) (Progress: \(Int(rideProgress*100))%)")
            
            let strategyPower = applyPacingStrategy(
                basePower: segment.powerRequired,
                strategy: strategy,
                segment: segment,
                rideProgress: rideProgress,
                cumulativeStress: cumulativeStress,
                totalRideDurationHours: totalDurationHours
            )

            let fatigueFactor = calculateFatigueFactor(cumulativeStress: cumulativeStress)
            let adjustedPower = strategyPower * fatigueFactor
            let finalPower = constrainPower(adjustedPower, ftp: ftp, grade: segment.elevationGrade)
            let estimatedTime = estimateSegmentTime(segment: segment, targetPower: finalPower)
            
            print("DEBUG: Segment \(index + 1) | Power Input: \(Int(finalPower)) | FTP: \(Int(ftp))")
            let powerZone = getPowerZone(for: finalPower)
            print("       -> Resulting Zone: \(powerZone.name)")

            let segmentTSS = calculateSegmentTSS(power: finalPower, durationSeconds: estimatedTime, ftp: ftp)
            cumulativeStress += segmentTSS
            
            let strategyDescription = getStrategyDescription(
                segment: segment,
                strategy: strategy,
                powerZone: powerZone,
                rideProgress: rideProgress
            )
            
            let pacedSegment = PacedSegment(
                originalSegment: segment,
                targetPower: finalPower,
                estimatedTime: estimatedTime,
                powerZone: powerZone,
                cumulativeStress: cumulativeStress,
                strategy: strategyDescription,
                paceAdjustment: segment.powerRequired > 0 ? finalPower / segment.powerRequired : 0
            )
            
            pacedSegments.append(pacedSegment)
        }
        
        let avgPower = calculateAveragePower(segments: pacedSegments)
        let normalizedPower = calculateNormalizedPower(segments: pacedSegments)
        
        print("\n📊 PACING SUMMARY:")
        print("   Average Power: \(Int(avgPower))W (\(Int(avgPower/ftp*100))% FTP)")
        print("   Normalized Power: \(Int(normalizedPower))W (\(Int(normalizedPower/ftp*100))% FTP)")
        print("   Total TSS: \(Int(cumulativeStress))")
        
        return pacedSegments
    }

    private func applyPacingStrategy(
        basePower: Double,
        strategy: PacingStrategy,
        segment: PowerRouteSegment,
        rideProgress: Double,
        cumulativeStress: Double,
        totalRideDurationHours: Double
    ) -> Double {
        
        let ftp = Double(settings.functionalThresholdPower)
        let grade = segment.elevationGrade
        
        print("🔍 Segment Debug:")
        print("   Base Power (from Analytics): \(Int(basePower))W")
        print("   Grade: \(String(format: "%.2f", grade * 100))%")
        
        // Apply fatigue FIRST to establish a baseline for the rider's current state.
        let fatigueMultiplier = max(0.80, 1.0 - (pow(cumulativeStress / 350.0, 1.5)))
        var targetPower = basePower * fatigueMultiplier
        
        print("   📊 Fatigue factor: \(String(format: "%.2f", fatigueMultiplier)) (Power after fatigue: \(Int(targetPower))W)")

        // --- BASE TERRAIN LOGIC (Shared Foundation) ---
        // All strategies (except Even Effort) will start with this intelligent terrain awareness.
        var terrainPower = targetPower
        if grade > 0.035 { // Climb
            let climbBoost = 1.0 + (grade * 2.5)
            terrainPower *= min(1.18, climbBoost)
        } else if grade < -0.025 { // Descent
            terrainPower *= 0.88
        } else { // Flat/Rolling
            terrainPower *= 0.96
        }

        // Now, apply the unique character of each strategy ON TOP of the terrain-aware power.
        switch strategy {
        
        case .balanced:
            targetPower = terrainPower
            print("   ⚖️ BALANCED: Applying base terrain logic.")

        // ✅ NEW HIERARCHICAL & MULTI-PHASE AGGRESSIVE STRATEGY
        case .aggressive:
            let racePaceMultiplier: Double
            if rideProgress < 0.20 {
                // Phase 1: The Start (First 20%). Go hard.
                racePaceMultiplier = 1.10 // 10% boost over terrain power
                print("   ⚔️ AGGRESSIVE (Phase 1 - The Start): Applying initial hard push.")
            } else if rideProgress < 0.85 {
                // Phase 2: The Mid-Race (20% to 85%). Settle into a high pace.
                racePaceMultiplier = 1.06 // 6% boost over terrain power
                print("   ⚔️ AGGRESSIVE (Phase 2 - Mid-Race): Maintaining high race pace.")
            } else {
                // Phase 3: The Finish (Final 15%). Empty the tank.
                // This high multiplier fights late-game fatigue to force a hard finish.
                racePaceMultiplier = 1.12 // 12% boost over terrain power
                print("   ⚔️ AGGRESSIVE (Phase 3 - The Finish): Emptying the tank!")
            }
            targetPower = terrainPower * racePaceMultiplier
            
        case .conservative:
            targetPower = terrainPower * 0.94 // 6% easier than balanced
            print("   🛡️ CONSERVATIVE: Applying a 6% reduction to the terrain-aware plan.")
            
        case .negativeSplit:
            let negativeSplitMultiplier = 0.92 + (rideProgress * 0.14) // Ramps from 92% to 106% of the terrain plan
            targetPower = terrainPower * negativeSplitMultiplier
            print(String(format: "   📈 NEGATIVE SPLIT: Applying time-based multiplier of %.3fx to terrain power.", negativeSplitMultiplier))
            
        // ✅ CORRECTED EVEN EFFORT STRATEGY
        case .evenEffort:
            // This strategy IGNORES the standard terrain logic and works directly on the fatigued baseline.
            // It aims for constant physiological stress, meaning MORE power on climbs and LESS on descents.
            if grade > 0.06 { // Steep Climb
                targetPower *= 1.12 // Push 12% harder than fatigued state to maintain effort
            } else if grade > 0.02 { // Moderate Climb
                targetPower *= 1.06 // Push 6% harder
            } else if grade < -0.05 { // Steep Descent
                targetPower *= 0.70 // Major power reduction, coasting
            } else if grade < -0.01 { // Gentle Descent
                targetPower *= 0.88 // Ease off
            }
            // On flats, power remains close to the fatigued baseline.
            print("   🏃 EVEN EFFORT: Adjusting power to maintain constant physiological effort.")
        }
        
        print("   💪 Final Power: \(Int(targetPower))W (\(Int(targetPower/ftp*100))% FTP)")
        
        return targetPower
    }
    
    private func calculateFatigueFactor(cumulativeStress: Double) -> Double {
        let fatigueThreshold: Double = 200
        guard cumulativeStress > fatigueThreshold else { return 1.0 }
        let fatigueRate: Double = 0.001
        return max(0.70, 1.0 - (cumulativeStress - fatigueThreshold) * fatigueRate)
    }
    
    private func constrainPower(_ power: Double, ftp: Double, grade: Double) -> Double {
        let maxPower = ftp * 1.25
        let minPower: Double = (grade < -0.03) ? ftp * 0.35 : ftp * 0.55
        return max(minPower, min(power, maxPower))
    }

    private func estimateSegmentTime(segment: PowerRouteSegment, targetPower: Double) -> Double {
        guard segment.powerRequired > 0 else { return segment.timeSeconds }
        let powerRatio = targetPower / segment.powerRequired
        let timeAdjustment = 1.0 / sqrt(powerRatio)
        return segment.timeSeconds * timeAdjustment
    }
    
    private func getPowerZone(for power: Double) -> PowerZone {
        guard let firstZone = powerZones.first, firstZone.maxPower > 0 else {
            return powerZones.first ?? PowerZone(number: 1, name: "Recovery", minPower: 0, maxPower: 100, color: "#9E9E9E")
        }
        
        for zone in powerZones {
            if power >= zone.minPower && power <= zone.maxPower {
                return zone
            }
        }
        
        return powerZones.last!
    }
    
    private func calculateSegmentTSS(power: Double, durationSeconds: Double, ftp: Double) -> Double {
        guard ftp > 0 else { return 0 }
        let intensityFactor = power / ftp
        let durationHours = durationSeconds / 3600.0
        return 100.0 * durationHours * pow(intensityFactor, 2)
    }

    private func calculateTotalTSS(segments: [PacedSegment], useNormalizedPower: Bool = true) -> Double {
        let ftp = Double(settings.functionalThresholdPower)
        guard ftp > 0 else { return 0 }
        
        if useNormalizedPower {
            let np = calculateNormalizedPower(segments: segments)
            let totalTimeHours = segments.reduce(0.0) { $0 + $1.estimatedTime } / 3600.0
            let intensityFactor = np / ftp
            return 100.0 * totalTimeHours * pow(intensityFactor, 2)
        } else {
            return segments.reduce(0.0) { $0 + calculateSegmentTSS(power: $1.targetPower, durationSeconds: $1.estimatedTime, ftp: ftp) }
        }
    }

    private func calculateNormalizedPower(segments: [PacedSegment]) -> Double {
        guard !segments.isEmpty else { return 0.0 }

        var samples: [Double] = []
        for segment in segments {
            let seconds = max(1, Int(segment.estimatedTime.rounded()))
            samples.append(contentsOf: Array(repeating: segment.targetPower, count: seconds))
        }

        let windowSize = 30
        var rollingAverages: [Double] = []
        var windowSum: Double = 0
        var queue: [Double] = []

        for powerSample in samples {
            queue.append(powerSample)
            windowSum += powerSample
            if queue.count > windowSize {
                windowSum -= queue.removeFirst()
            }
            rollingAverages.append(windowSum / Double(queue.count))
        }

        let fourths = rollingAverages.map { pow($0, 4) }
        guard !fourths.isEmpty else { return 0 }
        let meanOfFourths = fourths.reduce(0, +) / Double(fourths.count)
        
        return pow(meanOfFourths, 0.25)
    }
    
    private func calculateAveragePower(segments: [PacedSegment]) -> Double {
        let totalPowerTime = segments.reduce(0.0) { $0 + ($1.targetPower * $1.estimatedTime) }
        let totalTime = segments.reduce(0.0) { $0 + $1.estimatedTime }
        return totalTime > 0 ? totalPowerTime / totalTime : 0
    }

    private func assessDifficulty(tss: Double, intensityFactor: Double) -> DifficultyRating {
        if tss > 300 || intensityFactor > 1.0 { return .veryHard }
        else if tss > 200 || intensityFactor > 0.9 { return .hard }
        else if tss > 100 || intensityFactor > 0.8 { return .moderate }
        else if tss > 50 || intensityFactor > 0.7 { return .easy }
        else { return .recovery }
    }
    
    private func getStrategyDescription(
        segment: PowerRouteSegment,
        strategy: PacingStrategy,
        powerZone: PowerZone,
        rideProgress: Double
    ) -> String {
        let grade = segment.elevationGrade
        if grade > 0.08 { return "Steep climb - steady \(powerZone.name.lowercased()) effort" }
        else if grade > 0.04 { return "Climbing - \(powerZone.name.lowercased()) pace" }
        else if grade < -0.05 { return "Descent - recovery/positioning" }
        else { return "\(powerZone.name) - \(strategy.description.lowercased()) pacing" }
    }
    
    private func generateSummary(segments: [PacedSegment], powerAnalysis: PowerRouteAnalysisResult) -> PacingSummary {
        var timeInZones: [Int: Double] = [:]
        for segment in segments {
            let zoneTime = timeInZones[segment.powerZone.number, default: 0.0]
            timeInZones[segment.powerZone.number] = zoneTime + (segment.estimatedTime / 60.0)
        }
        
        let keySegments = identifyKeySegments(segments: segments)
        let warnings = generateWarnings(segments: segments)
        
        return PacingSummary(
            totalElevation: powerAnalysis.terrainBreakdown.climbingDistanceMeters,
            timeInZones: timeInZones,
            keySegments: keySegments,
            warnings: warnings,
            settings: settings
        )
    }

    private func identifyKeySegments(segments: [PacedSegment]) -> [KeySegment] {
        var candidateSegments: [(segment: KeySegment, difficulty: Double)] = []
        let ftp = Double(settings.functionalThresholdPower)
        
        print("\n🔍 IDENTIFYING KEY SEGMENTS")
        print("   Total segments to analyze: \(segments.count)")
        print("   FTP: \(Int(ftp))W")
        
        for (index, segment) in segments.enumerated() {
            let grade = segment.originalSegment.elevationGrade
            let power = segment.targetPower
            let segmentDuration = segment.estimatedTime / 60.0
            let distance = segment.distanceKm
            
            var difficultyScore: Double = 0
            var keySegment: KeySegment?
            
            if grade > 0.04 && distance > 0.3 {
                let climbScore = abs(grade) * 1000 * distance * segmentDuration
                difficultyScore = climbScore
                let elevationGain = grade * distance * 1000
                keySegment = KeySegment(
                    segmentIndex: index, type: .majorClimb,
                    description: String(format: "%.1fkm climb at %.1f%% (+%dm)", distance, grade * 100, Int(elevationGain)),
                    recommendation: "Steady effort, avoid surging early"
                )
                print(String(format: "   🏔 Segment %d: CLIMB - Score: %.1f, %.1fkm at %.1f%%", index, climbScore, distance, grade * 100))
            }
            else if grade < -0.04 && distance > 0.4 {
                let descentScore = abs(grade) * 800 * distance * segmentDuration
                difficultyScore = descentScore
                keySegment = KeySegment(
                    segmentIndex: index, type: .technicalSection,
                    description: String(format: "%.1fkm descent at %.1f%%", distance, abs(grade) * 100),
                    recommendation: "Technical descent - stay safe, recover for next effort"
                )
                print(String(format: "   ⬇️ Segment %d: DESCENT - Score: %.1f, %.1fkm at %.1f%%", index, descentScore, distance, grade * 100))
            }
            else if power > ftp * 1.05 && segmentDuration > 1.0 {
                let intensityScore = (power / ftp - 1.0) * 500 * segmentDuration
                difficultyScore = intensityScore
                keySegment = KeySegment(
                    segmentIndex: index, type: .highIntensity,
                    description: String(format: "%dmin at %dW (%d%% FTP)", Int(segmentDuration), Int(power), Int(power/ftp*100)),
                    recommendation: "High intensity - pace carefully to avoid blowing up"
                )
                print(String(format: "   ⚡️ Segment %d: HIGH INTENSITY - Score: %.1f, %dW for %dmin", index, intensityScore, Int(power), Int(segmentDuration)))
            }
            else if segmentDuration > 10.0 && power > ftp * 0.75 {
                let sustainedScore = segmentDuration * (power / ftp) * 100
                difficultyScore = sustainedScore
                let terrainType = abs(grade) > 0.02 ? "rolling" : "flat"
                keySegment = KeySegment(
                    segmentIndex: index, type: .technicalSection,
                    description: String(format: "%dmin sustained %@ effort at %@", Int(segmentDuration), terrainType, segment.powerZone.name),
                    recommendation: "Long effort - maintain steady rhythm and nutrition"
                )
                print(String(format: "   ⏱ Segment %d: SUSTAINED - Score: %.1f, %dmin at %@", index, sustainedScore, Int(segmentDuration), segment.powerZone.name))
            }
            else if segmentDuration > 45.0 && power < ftp * 0.75 {
                let fuelScore = segmentDuration * 5
                difficultyScore = fuelScore
                keySegment = KeySegment(
                    segmentIndex: index, type: .fuelOpportunity,
                    description: String(format: "%dmin recovery at %@", Int(segmentDuration), segment.powerZone.name.lowercased()),
                    recommendation: "Good opportunity for nutrition and hydration"
                )
                print(String(format: "   🍫 Segment %d: FUEL OPP - Score: %.1f", index, fuelScore))
            }
            
            if let segment = keySegment, difficultyScore > 0 {
                candidateSegments.append((segment, difficultyScore))
            }
        }
        
        candidateSegments.sort { $0.difficulty > $1.difficulty }
        
        print("\n   📊 Total candidates found: \(candidateSegments.count)")
        print("   🏆 Top 20 difficulty scores: \(candidateSegments.prefix(20).map { String(format: "%.0f", $0.difficulty) })")
        print("   📋 Top 20 segment indices: \(candidateSegments.prefix(20).map { $0.segment.segmentIndex })")
        
        return Array(candidateSegments.prefix(20).map { $0.segment })
    }
    
    private func generateWarnings(segments: [PacedSegment]) -> [String] {
        var warnings: [String] = []
        guard let ftp = settings.functionalThresholdPower > 0 ? Double(settings.functionalThresholdPower) : nil else { return [] }
        
        let totalTSS = segments.last?.cumulativeStress ?? 0
        let normalizedPower = calculateNormalizedPower(segments: segments)
        let totalTime = segments.reduce(0.0) { $0 + $1.estimatedTime }
        let durationHours = totalTime / 3600.0
        let intensityFactor = normalizedPower / ftp
        
        let sustainableIF: Double
        if durationHours < 1.0 { sustainableIF = 0.95 }
        else if durationHours < 2.0 { sustainableIF = 0.80 }
        else if durationHours < 3.0 { sustainableIF = 0.72 }
        else { sustainableIF = 0.65 }
        
        if intensityFactor > sustainableIF {
            warnings.append("⚠️ Intensity Factor (\(String(format: "%.2f", intensityFactor))) may be unsustainable for \(String(format: "%.1f", durationHours)) hours")
        }
        if totalTSS > 300 {
            warnings.append("⚠️ Very high training load (TSS \(Int(totalTSS))) - ensure adequate recovery")
        }
        
        let highIntensityTime = segments.filter { $0.targetPower > ftp }.reduce(0.0) { $0 + $1.estimatedTime }
        if highIntensityTime > 3600 {
            warnings.append("⚠️ Extended time above FTP - monitor for early fatigue")
        }
        if totalTime > 14400 {
            warnings.append("⚠️ Long duration ride - plan nutrition and hydration carefully")
        }
        
        return warnings
    }
}
