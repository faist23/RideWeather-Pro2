//
//  SmartPlanMatcher.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation
import Combine

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
        
        // 🔥 Extract route breadcrumbs
        let rideBreadcrumbs = analysis.metadata?.routeBreadcrumbs ?? []
        
        print("🔍 Matching against ride:")
        print("   Distance: \(String(format: "%.1f", rideDistance/1000))km")
        print("   Elevation: \(Int(rideElevation))m")
        print("   Duration: \(Int(rideDuration/60))min")
        print("   Route breadcrumbs: \(rideBreadcrumbs.count) points")
        
        var matches: [ComparisonSelectionViewModel.MatchedPlan] = []
        
        for plan in plans {
            let score = calculateMatchScore(
                rideDistance: rideDistance,
                rideElevation: rideElevation,
                rideDuration: rideDuration,
                rideBreadcrumbs: rideBreadcrumbs,
                plan: plan
            )
            
            print("   Plan '\(plan.routeName)': \(Int(score * 100))% match")
            
            if score >= minimumScore {
                matches.append(ComparisonSelectionViewModel.MatchedPlan(
                    plan: plan,
                    score: score
                ))
            }
        }
        
        return matches
    }
    
    // 🔥 Extract breadcrumbs from pacing plan
    private func extractPlanBreadcrumbs(from plan: StoredPacingPlan) -> [CLLocationCoordinate2D] {
        guard !plan.plan.segments.isEmpty else { return [] }
        
        var breadcrumbs: [CLLocationCoordinate2D] = []
        var cumulativeDistance: Double = 0
        let intervalMeters: Double = 500 // Same interval as ride analysis
        var lastBreadcrumbDistance: Double = 0
        
        for segment in plan.plan.segments {
            let segmentDistanceMeters = segment.originalSegment.distanceMeters
            
            // Add start point of first segment
            if breadcrumbs.isEmpty {
                breadcrumbs.append(segment.originalSegment.startPoint.coordinate)
                lastBreadcrumbDistance = 0
            }
            
            // Check if we need a breadcrumb in this segment
            while cumulativeDistance + segmentDistanceMeters > lastBreadcrumbDistance + intervalMeters {
                let nextBreadcrumbDistance = lastBreadcrumbDistance + intervalMeters
                let distanceIntoSegment = nextBreadcrumbDistance - cumulativeDistance
                let fraction = distanceIntoSegment / segmentDistanceMeters
                
                // Interpolate position along segment
                let coord = interpolateCoordinate(
                    start: segment.originalSegment.startPoint.coordinate,
                    end: segment.originalSegment.endPoint.coordinate,
                    fraction: fraction
                )
                breadcrumbs.append(coord)
                lastBreadcrumbDistance = nextBreadcrumbDistance
            }
            
            cumulativeDistance += segmentDistanceMeters
        }
        
        // Add final point
        if let lastSegment = plan.plan.segments.last {
            breadcrumbs.append(lastSegment.originalSegment.endPoint.coordinate)
        }
        
        return breadcrumbs
    }
    
    // 🔥 Interpolate coordinate between two points
    private func interpolateCoordinate(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        let lat = start.latitude + (end.latitude - start.latitude) * fraction
        let lon = start.longitude + (end.longitude - start.longitude) * fraction
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    private func calculateMatchScore(
        rideDistance: Double,
        rideElevation: Double,
        rideDuration: TimeInterval,
        rideBreadcrumbs: [CLLocationCoordinate2D],
        plan: StoredPacingPlan
    ) -> Double {
        
        let planDistance = plan.plan.totalDistance * 1000
        let planElevation = plan.plan.summary.totalElevation
        let planDuration = plan.plan.totalTimeMinutes * 60
        
        // Get plan breadcrumbs
        let planBreadcrumbs = extractPlanBreadcrumbs(from: plan)
        
        // 1. Distance Match (25% weight)
        let distanceDiff = abs(planDistance - rideDistance)
        let distanceDeviation = distanceDiff / rideDistance
        let distanceScore = max(0, 1.0 - (distanceDeviation / 0.15))
        
        // 2. Elevation Match (20% weight)
        let elevationScore: Double
        if rideElevation > 0 && planElevation > 0 {
            let elevationDiff = abs(planElevation - rideElevation)
            let elevationDeviation = elevationDiff / rideElevation
            elevationScore = max(0, 1.0 - (elevationDeviation / 0.25))
        } else if rideElevation == 0 && planElevation == 0 {
            elevationScore = 1.0
        } else {
            elevationScore = 0.3
        }
        
        // 3. Duration Match (10% weight)
        let durationDiff = abs(planDuration - rideDuration)
        let durationDeviation = durationDiff / rideDuration
        let durationScore = max(0, 1.0 - (durationDeviation / 0.30))
        
        // 🔥 4. Route Shape Match (45% weight) - MOST IMPORTANT
        let routeShapeScore = calculateRouteShapeScore(
            rideBreadcrumbs: rideBreadcrumbs,
            planBreadcrumbs: planBreadcrumbs
        )
        
        // Weighted total
        let totalScore = (distanceScore * 0.25) +
                        (elevationScore * 0.20) +
                        (durationScore * 0.10) +
                        (routeShapeScore * 0.45)
        
        // Bonus for very close matches
        var bonusScore = totalScore
        if distanceDeviation < 0.05 && routeShapeScore > 0.9 {
            bonusScore += 0.05
        }
        
        return min(1.0, bonusScore)
    }
    
    // 🔥 Calculate how similar the route shapes are
    private func calculateRouteShapeScore(
        rideBreadcrumbs: [CLLocationCoordinate2D],
        planBreadcrumbs: [CLLocationCoordinate2D]
    ) -> Double {
        
        guard !rideBreadcrumbs.isEmpty && !planBreadcrumbs.isEmpty else {
            print("      ⚠️ No breadcrumbs available for route matching")
            return 0.5 // Neutral score
        }
        
        // Need at least 3 points to determine route shape
        guard rideBreadcrumbs.count >= 3 && planBreadcrumbs.count >= 3 else {
            print("      ⚠️ Not enough breadcrumbs - using simple start/end match")
            return calculateSimpleProximityScore(rideBreadcrumbs, planBreadcrumbs)
        }
        
        // 🔥 Calculate route similarity using modified Hausdorff distance
        let similarity = calculateRouteSimilarity(rideBreadcrumbs, planBreadcrumbs)
        
        print("      Route shape similarity: \(Int(similarity * 100))% (avg deviation: \(String(format: "%.0f", (1.0 - similarity) * 1000))m)")
        
        return similarity
    }
    
    // 🔥 Calculate similarity between two routes
    private func calculateRouteSimilarity(
        _ route1: [CLLocationCoordinate2D],
        _ route2: [CLLocationCoordinate2D]
    ) -> Double {
        
        // Calculate bidirectional similarity
        let forward = calculateDirectionalSimilarity(from: route1, to: route2)
        let backward = calculateDirectionalSimilarity(from: route2, to: route1)
        
        // Use the worse of the two (stricter matching)
        return min(forward, backward)
    }
    
    // 🔥 Calculate directional similarity (average distance to nearest point)
    private func calculateDirectionalSimilarity(
        from route1: [CLLocationCoordinate2D],
        to route2: [CLLocationCoordinate2D]
    ) -> Double {
        
        var totalDeviation: Double = 0
        
        for point1 in route1 {
            // Find minimum distance to any point in route2
            let minDistance = route2.map { point1.distance(from: $0) }.min() ?? Double.infinity
            totalDeviation += minDistance
        }
        
        let avgDeviation = totalDeviation / Double(route1.count)
        
        // Convert average deviation to a 0-1 score
        // < 100m average = 1.0 (perfect)
        // 100-250m = 0.9 (excellent)
        // 250-500m = 0.75 (good)
        // 500-1000m = 0.5 (fair)
        // 1000-2000m = 0.25 (poor)
        // > 2000m = 0.0 (no match)
        switch avgDeviation {
        case 0..<100:
            return 1.0
        case 100..<250:
            return 0.9
        case 250..<500:
            return 0.75
        case 500..<1000:
            return 0.5
        case 1000..<2000:
            return 0.25
        default:
            return 0.0
        }
    }
    
    // 🔥 Simple start/end proximity when we don't have enough breadcrumbs
    private func calculateSimpleProximityScore(
        _ route1: [CLLocationCoordinate2D],
        _ route2: [CLLocationCoordinate2D]
    ) -> Double {
        
        guard let start1 = route1.first, let end1 = route1.last,
              let start2 = route2.first, let end2 = route2.last else {
            return 0.5
        }
        
        let startDist = start1.distance(from: start2)
        let endDist = end1.distance(from: end2)
        
        let startScore = calculateProximityScore(distance: startDist)
        let endScore = calculateProximityScore(distance: endDist)
        
        // Both need to be close
        return (startScore + endScore) / 2.0
    }
    
    // 🔥 Score proximity with tolerances for GPS accuracy
    private func calculateProximityScore(distance: Double) -> Double {
        switch distance {
        case 0..<50:
            return 1.0
        case 50..<100:
            return 0.95
        case 100..<200:
            return 0.85
        case 200..<500:
            return 0.70
        case 500..<1000:
            return 0.50
        case 1000..<2000:
            return 0.30
        default:
            return 0.0
        }
    }
    
    /// Find the single best match
    func findBestMatch(
        for analysis: RideAnalysis,
        from plans: [StoredPacingPlan]
    ) -> StoredPacingPlan? {
        
        let matches = findMatchingPlans(for: analysis, from: plans, minimumScore: 0.7)
        return matches.first?.plan
    }
}
