//
//  SmartPlanMatcher.swift
//  RideWeather Pro
//

import Foundation

class SmartPlanMatcher {
    
    func findMatchingPlans(
        for analysis: RideAnalysis,
        from plans: [StoredPacingPlan],
        minimumScore: Double = 0.6
    ) -> [ComparisonSelectionViewModel.MatchedPlan] {
        
        guard !plans.isEmpty else { return [] }
        
        // Extract ride characteristics
        let rideDistance = analysis.distance // meters
        let rideElevation = analysis.metadata?.elevationGain ?? 0 // meters
        let rideDuration = analysis.duration // seconds
        
        print("🔍 Matching against ride:")
        print("   Distance: \(String(format: "%.1f", rideDistance/1000))km")
        print("   Elevation: \(Int(rideElevation))m")
        print("   Duration: \(Int(rideDuration/60))min")
        
        var matches: [ComparisonSelectionViewModel.MatchedPlan] = []
        
        for plan in plans {
            let score = calculateMatchScore(
                rideDistance: rideDistance,
                rideElevation: rideElevation,
                rideDuration: rideDuration,
                plan: plan
            )
            
            print("   Plan '\(plan.routeName)': \(Int(score * 100))% match")
            
            // Only include if above minimum threshold
            if score >= minimumScore {
                matches.append(ComparisonSelectionViewModel.MatchedPlan(
                    plan: plan,
                    score: score
                ))
            }
        }
        
        return matches
    }
    
    private func calculateMatchScore(
        rideDistance: Double,
        rideElevation: Double,
        rideDuration: TimeInterval,
        plan: StoredPacingPlan
    ) -> Double {
        
        let planDistance = plan.plan.totalDistance * 1000 // Convert km to meters
        let planElevation = plan.plan.summary.totalElevation
        let planDuration = plan.plan.totalTimeMinutes * 60 // Convert to seconds
        
        // 1. Distance Match (40% weight) - Most important
        let distanceDiff = abs(planDistance - rideDistance)
        let distanceDeviation = distanceDiff / rideDistance
        let distanceScore = max(0, 1.0 - (distanceDeviation / 0.15)) // Allow 15% variance
        
        // 2. Elevation Match (35% weight) - Critical for route similarity
        let elevationScore: Double
        if rideElevation > 0 && planElevation > 0 {
            let elevationDiff = abs(planElevation - rideElevation)
            let elevationDeviation = elevationDiff / rideElevation
            elevationScore = max(0, 1.0 - (elevationDeviation / 0.25)) // Allow 25% variance
        } else if rideElevation == 0 && planElevation == 0 {
            elevationScore = 1.0 // Both flat
        } else {
            elevationScore = 0.3 // One flat, one hilly - poor match
        }
        
        // 3. Duration Match (25% weight) - Less important as it varies with effort
        let durationDiff = abs(planDuration - rideDuration)
        let durationDeviation = durationDiff / rideDuration
        let durationScore = max(0, 1.0 - (durationDeviation / 0.30)) // Allow 30% variance
        
        // Weighted total
        let totalScore = (distanceScore * 0.40) + 
                        (elevationScore * 0.35) + 
                        (durationScore * 0.25)
        
        // Bonus points for exact distance/elevation matches
        var bonusScore = totalScore
        if distanceDeviation < 0.05 { // Within 5%
            bonusScore += 0.05
        }
        if rideElevation > 0 && abs(planElevation - rideElevation) / rideElevation < 0.10 { // Within 10%
            bonusScore += 0.05
        }
        
        return min(1.0, bonusScore)
    }
    
    /// Find the single best match (used elsewhere)
    func findBestMatch(
        for analysis: RideAnalysis,
        from plans: [StoredPacingPlan]
    ) -> StoredPacingPlan? {
        
        let matches = findMatchingPlans(for: analysis, from: plans, minimumScore: 0.7)
        return matches.first?.plan
    }
}
