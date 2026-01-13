//
//  PhysiologicalReadiness.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 11/9/25.
//


import Foundation

/// A snapshot of physiological metrics from HealthKit.
struct PhysiologicalReadiness: Equatable, Codable {
    var latestHRV: Double?
    var averageHRV: Double?
    var latestRHR: Double?
    var averageRHR: Double?
    var sleepDuration: TimeInterval?
    var averageSleepDuration: TimeInterval? 
    
    /// A simple readiness score from 0-100 based on metrics vs. their average.
    var readinessScore: Int {
        var score = 100.0
        let sevenHours = 7 * 3600.0 // A reasonable minimum
        
        // HRV: 40% weight
        if let hrv = latestHRV, let avgHRV = averageHRV, avgHRV > 0 {
            let hrvPenalty = max(0, (avgHRV - hrv) / avgHRV * 100.0)
            score -= hrvPenalty * 0.4
        }
        
        // RHR: 40% weight
        if let rhr = latestRHR, let avgRHR = averageRHR, avgRHR > 0 {
            let rhrPenalty = max(0, (rhr - avgRHR) / avgRHR * 100.0)
            score -= rhrPenalty * 0.4
        }
        
        // Sleep: 20% weight
        if let sleep = sleepDuration {
            // **FIX**: Use 7-day average as the goal, or fall back to 7 hours if no avg exists
            let sleepGoal = averageSleepDuration ?? sevenHours
            
            if sleep < (sleepGoal * 0.8) { // < 80% of goal/avg
                score -= 20
            } else if sleep < (sleepGoal * 0.9) { // < 90% of goal/avg
                score -= 10
            }
        }
        
        return Int(max(0, min(100, score)))
    }
}
