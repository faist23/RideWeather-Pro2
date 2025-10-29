//
//  PacingPlanComparisonEngine.swift
//  RideWeather Pro
//

import Foundation

class PacingPlanComparisonEngine {
    
    func comparePlanToActual(
        pacingPlan: PacingPlan,
        actualRide: RideAnalysis,
        ftp: Double
    ) -> PacingPlanComparison {
        
        // Match planned segments to actual terrain segments
        let opportunities = identifyTimeOpportunities(
            plannedSegments: pacingPlan.segments,
            actualSegments: actualRide.terrainSegments ?? [],
            ftp: ftp
        )
        
        // Calculate overall metrics
        let totalTimeSavings = opportunities.reduce(0) { $0 + $1.timeLost }
        let powerEfficiency = calculateOverallPowerEfficiency(opportunities: opportunities)
        
        // Determine grade based on execution
        let grade = determinePerformanceGrade(
            opportunities: opportunities,
            powerEfficiency: powerEfficiency
        )
        
        // Generate actionable insights
        let (strengths, improvements) = generateActionableInsights(
            opportunities: opportunities,
            actualRide: actualRide
        )
        
        return PacingPlanComparison(
            routeName: actualRide.rideName,
            plannedTime: pacingPlan.totalTimeMinutes * 60,
            actualTime: actualRide.duration,
            plannedPower: pacingPlan.averagePower,
            actualPower: actualRide.averagePower,
            segmentResults: opportunities,
            powerEfficiency: powerEfficiency,
            performanceGrade: grade,
            totalPotentialTimeSavings: totalTimeSavings,
            strengths: strengths,
            improvements: improvements
        )
    }
    
    // MARK: - Opportunity Identification
    
/*    private func identifyTimeOpportunities(
        plannedSegments: [PacedSegment],
        actualSegments: [TerrainSegment],
        ftp: Double
    ) -> [PacingPlanComparison.SegmentResult] {
        
        var opportunities: [PacingPlanComparison.SegmentResult] = []
        
        // Match planned to actual segments by distance/position
        var cumulativeDistance: Double = 0
        
        for (index, actualSegment) in actualSegments.enumerated() {
            // Find corresponding planned segment
            let plannedSegment = findMatchingPlannedSegment(
                at: cumulativeDistance,
                in: plannedSegments
            )
            
            guard let planned = plannedSegment else {
                cumulativeDistance += actualSegment.distance
                continue
            }
            
            // Calculate what the rider actually did vs what was planned
            let actualPower = actualSegment.averagePower
            let plannedPower = planned.targetPower
            let deviation = ((actualPower - plannedPower) / plannedPower) * 100
            
            // Estimate time lost/gained
            let timeLost = estimateTimeDifference(
                actualPower: actualPower,
                plannedPower: plannedPower,
                distance: actualSegment.distance,
                gradient: actualSegment.gradient,
                duration: actualSegment.duration
            )
            
            // Only add if it's a meaningful opportunity (>3 seconds)
            if abs(timeLost) > 3 {
                let grade = gradeSegmentExecution(
                    deviation: deviation,
                    terrainType: actualSegment.type,
                    timeLost: timeLost
                )
                
                let segmentName = formatSegmentName(
                    type: actualSegment.type,
                    distance: actualSegment.distance,
                    gradient: actualSegment.gradient,
                    locationMiles: locationMiles,
                    locationKm: locationKm,
                    duration: actualSegment.duration,
                    context: context
                )
                
                opportunities.append(PacingPlanComparison.SegmentResult(
                    segmentIndex: index,
                    segmentName: segmentName,
                    plannedPower: plannedPower,
                    actualPower: actualPower,
                    deviation: deviation,
                    timeLost: timeLost,
                    grade: grade
                ))
            }
            
            cumulativeDistance += actualSegment.distance
        }
        
        // Sort by time impact (biggest opportunities first)
        return opportunities.sorted { abs($0.timeLost) > abs($1.timeLost) }
    }*/
    
    private func findMatchingPlannedSegment(
        at distance: Double,
        in plannedSegments: [PacedSegment]
    ) -> PacedSegment? {
        var cumulative: Double = 0
        
        for segment in plannedSegments {
            let segmentDistance = segment.originalSegment.distanceMeters
            if distance >= cumulative && distance < cumulative + segmentDistance {
                return segment
            }
            cumulative += segmentDistance
        }
        
        return plannedSegments.last
    }
    
    private func estimateTimeDifference(
        actualPower: Double,
        plannedPower: Double,
        distance: Double,
        gradient: Double,
        duration: TimeInterval
    ) -> TimeInterval {
        
        guard actualPower > 0 && plannedPower > 0 else { return 0 }
        
        // Different calculation based on terrain
        if gradient > 0.03 { // Climb
            // On climbs, power is roughly linear with speed
            let powerRatio = plannedPower / actualPower
            let speedImprovement = pow(powerRatio, 0.33) // Physics approximation
            
            let actualSpeed = distance / duration
            let plannedSpeed = actualSpeed * speedImprovement
            let plannedTime = distance / plannedSpeed
            
            return duration - plannedTime // Positive = time lost
            
        } else if gradient < -0.03 { // Descent
            // On descents, power matters less - mostly aero
            // Small time difference
            return duration * 0.02 * (actualPower - plannedPower) / plannedPower
            
        } else { // Flat
            // On flats, power follows aero curve
            let powerRatio = plannedPower / actualPower
            let speedImprovement = pow(powerRatio, 0.4) // Aero dominates
            
            let actualSpeed = distance / duration
            let plannedSpeed = actualSpeed * speedImprovement
            let plannedTime = distance / plannedSpeed
            
            return duration - plannedTime
        }
    }
    
    private func gradeSegmentExecution(
        deviation: Double,
        terrainType: TerrainSegment.TerrainType,
        timeLost: TimeInterval
    ) -> PacingPlanComparison.SegmentGrade {
        
        // On climbs, under-powering is worse
        if terrainType == .climb {
            if deviation > -5 && abs(timeLost) < 5 { return .excellent }
            if deviation > -10 && abs(timeLost) < 10 { return .good }
            if deviation > -20 { return .acceptable }
            if deviation > -30 { return .needsWork }
            return .poor
        }
        
        // On flats/descents, consistency matters
        if abs(deviation) < 5 { return .excellent }
        if abs(deviation) < 10 { return .good }
        if abs(deviation) < 15 { return .acceptable }
        if abs(deviation) < 25 { return .needsWork }
        return .poor
    }
    
    private func formatSegmentName(
        type: TerrainSegment.TerrainType,
        distance: Double,
        gradient: Double,
        locationMiles: Double,
        locationKm: Double,
        duration: TimeInterval,
        context: SegmentContext
    ) -> String {
        // Format distance
        let distanceStr = distance > 1000 ?
            String(format: "%.1fkm", distance / 1000) :
            "\(Int(distance))m"
        
        // Format gradient
        let gradeStr = String(format: "%.1f%%", abs(gradient) * 100)
        
        // Format duration
        let durationMins = Int(duration / 60)
        let durationSecs = Int(duration.truncatingRemainder(dividingBy: 60))
        let durationStr = durationMins > 0 ?
            "\(durationMins):\(String(format: "%02d", durationSecs))" :
            "\(durationSecs)s"
        
        // Build location string
        let location = "Mile \(String(format: "%.1f", locationMiles))"
        
        // Add context flag if there's an issue
        let contextFlag = context.issues.isEmpty ? "" : " ⚠️"
        
        return "\(location) • \(type.emoji) \(type.rawValue) • \(distanceStr) at \(gradeStr) • \(durationStr)\(contextFlag)"
    }
    
    
    private func identifyTimeOpportunities(
        plannedSegments: [PacedSegment],
        actualSegments: [TerrainSegment],
        ftp: Double
    ) -> [PacingPlanComparison.SegmentResult] {
        
        var opportunities: [PacingPlanComparison.SegmentResult] = []
        
        // Track cumulative distance for location context
        var cumulativeDistanceMeters: Double = 0
        var cumulativeDistanceMiles: Double = 0
        
        for (index, actualSegment) in actualSegments.enumerated() {
            // Calculate location at START of segment
            let locationMiles = cumulativeDistanceMiles
            let locationKm = cumulativeDistanceMeters / 1000
            
            // Find corresponding planned segment
            let plannedSegment = findMatchingPlannedSegment(
                at: cumulativeDistanceMeters,
                in: plannedSegments
            )
            
            guard let planned = plannedSegment else {
                cumulativeDistanceMeters += actualSegment.distance
                cumulativeDistanceMiles += actualSegment.distance / 1609.34
                continue
            }
            
            // Calculate what the rider actually did vs what was planned
            let actualPower = actualSegment.averagePower
            let plannedPower = planned.targetPower
            let deviation = ((actualPower - plannedPower) / plannedPower) * 100
            
            // Estimate time lost/gained
            let timeLost = estimateTimeDifference(
                actualPower: actualPower,
                plannedPower: plannedPower,
                distance: actualSegment.distance,
                gradient: actualSegment.gradient,
                duration: actualSegment.duration
            )
            
            // 🔥 Detect potential issues (stops, misclassified terrain, etc.)
            let context = analyzeSegmentContext(
                actualSegment: actualSegment,
                plannedPower: plannedPower,
                actualPower: actualPower,
                ftp: ftp
            )
            
            // Only add if it's a meaningful opportunity (>3 seconds)
            if abs(timeLost) > 3 {
                let grade = gradeSegmentExecution(
                    deviation: deviation,
                    terrainType: actualSegment.type,
                    timeLost: timeLost/*,
                    context: context*/
                )
                
                let segmentName = formatSegmentName(
                    index: index,
                    type: actualSegment.type,
                    distance: actualSegment.distance,
                    gradient: actualSegment.gradient,
                    locationMiles: locationMiles,
                    locationKm: locationKm,
                    duration: actualSegment.duration,
                    context: context
                )
                
                opportunities.append(PacingPlanComparison.SegmentResult(
                    segmentIndex: index,
                    segmentName: segmentName,
                    plannedPower: plannedPower,
                    actualPower: actualPower,
                    deviation: deviation,
                    timeLost: timeLost,
                    grade: grade,
                    locationMiles: locationMiles,  // 🔥 ADD THIS
                    locationKm: locationKm,        // 🔥 ADD THIS
                    context: context               // 🔥 ADD THIS
                ))
            }
            
            cumulativeDistanceMeters += actualSegment.distance
            cumulativeDistanceMiles += actualSegment.distance / 1609.34
        }
        
        // Sort by time impact (biggest opportunities first)
        return opportunities.sorted { abs($0.timeLost) > abs($1.timeLost) }
    }

    // 🔥 NEW: Analyze segment context to detect anomalies
    private func analyzeSegmentContext(
        actualSegment: TerrainSegment,
        plannedPower: Double,
        actualPower: Double,
        ftp: Double
    ) -> SegmentContext {
        
        var issues: [String] = []
        var likelyReason: String?
        
        // Detect very low power (possible stop/slow down)
        if actualPower < plannedPower * 0.5 && actualSegment.duration > 20 {
            issues.append("Very low power")
            likelyReason = "Possible traffic stop, intersection, or mechanical issue"
        }
        
        // Detect misclassified flat (high power on "flat")
        if actualSegment.type == .flat && actualPower > ftp * 0.95 && actualSegment.duration > 30 {
            issues.append("High power on flat")
            likelyReason = "This may actually be a climb - check the route profile"
        }
        
        // Detect coasting on descent (very low power)
        if actualSegment.type == .descent && actualPower < 50 {
            issues.append("Coasting")
            likelyReason = "Normal for descents - focus on aero position"
        }
        
        // Detect unsustainable power (way above threshold)
        if actualPower > ftp * 1.20 && actualSegment.duration > 60 {
            issues.append("Unsustainable effort")
            likelyReason = "This hard effort will cause fatigue later"
        }
        
        // Detect terrain mismatch
        let expectedPowerForTerrain = estimateExpectedPower(
            terrainType: actualSegment.type,
            gradient: actualSegment.gradient,
            ftp: ftp
        )
        
        let powerDiscrepancy = abs(actualPower - expectedPowerForTerrain) / expectedPowerForTerrain
        if powerDiscrepancy > 0.4 && actualSegment.duration > 30 {
            issues.append("Unexpected power for terrain")
            if actualPower > expectedPowerForTerrain {
                likelyReason = "Terrain may be steeper than classified"
            } else {
                likelyReason = "Check for traffic, stops, or route obstacles"
            }
        }
        
        return SegmentContext(
            issues: issues,
            likelyReason: likelyReason,
            durationSeconds: actualSegment.duration
        )
    }

    private func estimateExpectedPower(
        terrainType: TerrainSegment.TerrainType,
        gradient: Double,
        ftp: Double
    ) -> Double {
        switch terrainType {
        case .climb:
            if gradient > 0.08 { return ftp * 0.95 }
            if gradient > 0.05 { return ftp * 0.85 }
            return ftp * 0.80
        case .flat, .rolling:
            return ftp * 0.75
        case .descent:
            return ftp * 0.40
        }
    }

    private func formatSegmentName(
        index: Int,
        type: TerrainSegment.TerrainType,
        distance: Double,
        gradient: Double,
        locationMiles: Double,
        locationKm: Double,
        duration: TimeInterval,
        context: SegmentContext
    ) -> String {
        // Format distance
        let distanceStr = distance > 1000 ?
            String(format: "%.1fkm", distance / 1000) :
            "\(Int(distance))m"
        
        // Format gradient
        let gradeStr = String(format: "%.1f%%", abs(gradient) * 100)
        
        // Format duration
        let durationMins = Int(duration / 60)
        let durationSecs = Int(duration.truncatingRemainder(dividingBy: 60))
        let durationStr = durationMins > 0 ?
            "\(durationMins):\(String(format: "%02d", durationSecs)) min" :
            "\(durationSecs)s"
        
        // 🔥 Build location string
        let location = "Mile \(String(format: "%.1f", locationMiles))"
        
        // 🔥 Add context flag if there's an issue
        let contextFlag = context.issues.isEmpty ? "" : " ⚠️"
        
        return "\(location) • \(type.emoji) \(type.rawValue) • \(distanceStr) at \(gradeStr) • \(durationStr)\(contextFlag)"
    }

/*    // Define context structure
    struct SegmentContext {
        let issues: [String]
        let likelyReason: String?
        let durationSeconds: TimeInterval
        
        var hasIssues: Bool {
            return !issues.isEmpty
        }
    }*/

    // MARK: - Metrics Calculation
    
    private func calculateOverallPowerEfficiency(
        opportunities: [PacingPlanComparison.SegmentResult]
    ) -> Double {
        guard !opportunities.isEmpty else { return 100 }
        
        let totalPlannedPowerTime = opportunities.reduce(0.0) { result, opp in
            // Weight by impact
            return result + (opp.plannedPower * abs(opp.timeLost))
        }
        
        let totalActualPowerTime = opportunities.reduce(0.0) { result, opp in
            return result + (opp.actualPower * abs(opp.timeLost))
        }
        
        guard totalPlannedPowerTime > 0 else { return 100 }
        
        return (totalActualPowerTime / totalPlannedPowerTime) * 100
    }
    
    private func determinePerformanceGrade(
        opportunities: [PacingPlanComparison.SegmentResult],
        powerEfficiency: Double
    ) -> PacingPlanComparison.PerformanceGrade {
        
        let excellentCount = opportunities.filter { $0.grade == .excellent }.count
        let poorCount = opportunities.filter { $0.grade == .poor || $0.grade == .needsWork }.count
        let totalOpportunities = opportunities.count
        
        guard totalOpportunities > 0 else { return .a }
        
        let excellentRatio = Double(excellentCount) / Double(totalOpportunities)
        let poorRatio = Double(poorCount) / Double(totalOpportunities)
        
        // Grade based on execution quality
        if excellentRatio > 0.8 && poorRatio < 0.1 { return .aPlusPlus }
        if excellentRatio > 0.7 && poorRatio < 0.15 { return .aPlus }
        if excellentRatio > 0.6 && poorRatio < 0.2 { return .a }
        if excellentRatio > 0.5 { return .aMinus }
        if excellentRatio > 0.4 { return .bPlus }
        if excellentRatio > 0.3 { return .b }
        if poorRatio < 0.5 { return .bMinus }
        if poorRatio < 0.6 { return .cPlus }
        if poorRatio < 0.7 { return .c }
        if poorRatio < 0.8 { return .cMinus }
        if poorRatio < 0.9 { return .d }
        return .f
    }
    
    // MARK: - Insights Generation
    
    private func generateActionableInsights(
        opportunities: [PacingPlanComparison.SegmentResult],
        actualRide: RideAnalysis
    ) -> (strengths: [String], improvements: [String]) {
        
        var strengths: [String] = []
        var improvements: [String] = []
        
        // Identify strengths (well-executed segments)
        let wellExecuted = opportunities.filter { $0.grade == .excellent || $0.grade == .good }
        if !wellExecuted.isEmpty {
            let totalTimeWell = wellExecuted.reduce(0.0) { $0 + abs($1.timeLost) }
            strengths.append("Executed \(wellExecuted.count) segments within 5% of target power")
            
            // Call out specific good segments
            if let best = wellExecuted.first {
                strengths.append("Best segment: \(best.segmentName) - only \(String(format: "%.1f%%", abs(best.deviation))) off target")
            }
        }
        
        // Identify biggest improvement opportunities
        let biggestOpportunities = opportunities.filter { $0.timeLost > 5 }.prefix(5)
        
        if biggestOpportunities.isEmpty {
            strengths.append("Nearly perfect execution - minimal time left on the table!")
        } else {
            for opportunity in biggestOpportunities {
                let timeSavedStr = formatTimeSavings(opportunity.timeLost)
                let powerDiff = Int(opportunity.plannedPower - opportunity.actualPower)
                
                if opportunity.timeLost > 0 {
                    // They were too slow (usually under-powered on climbs)
                    improvements.append("""
                    \(opportunity.segmentName): Push \(abs(powerDiff))W harder to save \(timeSavedStr)
                    """)
                } else {
                    // They went too hard (wasted energy)
                    improvements.append("""
                    \(opportunity.segmentName): Ease off by \(abs(powerDiff))W - you wasted energy here
                    """)
                }
            }
            
            // Summary
            let totalSavings = opportunities.reduce(0.0) { $0 + max(0, $1.timeLost) }
            if totalSavings > 10 {
                improvements.append("Total potential time savings: \(formatTimeSavings(totalSavings))")
            }
        }
        
        return (strengths, improvements)
    }
    
    private func formatTimeSavings(_ seconds: TimeInterval) -> String {
        let absSeconds = abs(seconds)
        if absSeconds >= 60 {
            let mins = Int(absSeconds / 60)
            let secs = Int(absSeconds.truncatingRemainder(dividingBy: 60))
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "\(Int(absSeconds))s"
    }
}
