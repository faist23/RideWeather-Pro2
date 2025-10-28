//
//  PacingPlanComparisonEngine.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 10/27/25.
//


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
        
        let segmentResults = compareSegments(
            plannedSegments: pacingPlan.segments,
            actualRide: actualRide,
            ftp: ftp
        )
        
        let powerEfficiency = calculatePowerEfficiency(
            plannedPower: pacingPlan.averagePower,
            actualPower: actualRide.averagePower
        )
        
        let grade = determineGrade(
            segmentResults: segmentResults,
            powerEfficiency: powerEfficiency,
            timeDifference: actualRide.duration - (pacingPlan.totalTimeMinutes * 60)
        )
        
        let timeSavings = calculatePotentialTimeSavings(segmentResults: segmentResults)
        let (strengths, improvements) = generateInsights(segmentResults: segmentResults)
        
        return PacingPlanComparison(
            routeName: actualRide.rideName,
            plannedTime: pacingPlan.totalTimeMinutes * 60,
            actualTime: actualRide.duration,
            plannedPower: pacingPlan.averagePower,
            actualPower: actualRide.averagePower,
            segmentResults: segmentResults,
            powerEfficiency: powerEfficiency,
            performanceGrade: grade,
            totalPotentialTimeSavings: timeSavings,
            strengths: strengths,
            improvements: improvements
        )
    }
    
    private func compareSegments(
        plannedSegments: [PacedSegment],
        actualRide: RideAnalysis,
        ftp: Double
    ) -> [PacingPlanComparison.SegmentResult] {
        // Implement segment comparison logic
        return []
    }
    
    private func calculatePowerEfficiency(plannedPower: Double, actualPower: Double) -> Double {
        return (actualPower / plannedPower) * 100
    }
    
    private func determineGrade(
        segmentResults: [PacingPlanComparison.SegmentResult],
        powerEfficiency: Double,
        timeDifference: TimeInterval
    ) -> PacingPlanComparison.PerformanceGrade {
        // Implement grading logic
        if powerEfficiency > 98 && timeDifference < 0 { return .aPlusPlus }
        if powerEfficiency > 95 { return .aPlus }
        if powerEfficiency > 90 { return .a }
        if powerEfficiency > 85 { return .aMinus }
        if powerEfficiency > 80 { return .bPlus }
        if powerEfficiency > 75 { return .b }
        if powerEfficiency > 70 { return .bMinus }
        if powerEfficiency > 65 { return .cPlus }
        if powerEfficiency > 60 { return .c }
        if powerEfficiency > 50 { return .cMinus }
        if powerEfficiency > 40 { return .d }
        return .f
    }
    
    private func calculatePotentialTimeSavings(
        segmentResults: [PacingPlanComparison.SegmentResult]
    ) -> TimeInterval {
        return segmentResults.reduce(0) { $0 + $1.timeLost }
    }
    
    private func generateInsights(
        segmentResults: [PacingPlanComparison.SegmentResult]
    ) -> (strengths: [String], improvements: [String]) {
        var strengths: [String] = []
        var improvements: [String] = []
        
        let excellentSegments = segmentResults.filter { $0.grade == .excellent || $0.grade == .good }
        let poorSegments = segmentResults.filter { $0.grade == .poor || $0.grade == .needsWork }
        
        if !excellentSegments.isEmpty {
            strengths.append("Strong execution on \(excellentSegments.count) segments")
        }
        
        if !poorSegments.isEmpty {
            improvements.append("Opportunity to improve on \(poorSegments.count) segments")
        }
        
        return (strengths, improvements)
    }
}