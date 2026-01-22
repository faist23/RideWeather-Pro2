//
//  PhysiologicalReadiness.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 11/9/25.
//

import Foundation

/// A snapshot of physiological metrics.
/// Uses pure duration (no sleep stages) to ensure compatibility with all trackers.
struct PhysiologicalReadiness: Equatable, Codable {
    // MARK: - Core Metrics
    var latestHRV: Double?
    var averageHRV: Double?
    
    var latestRHR: Double?
    var averageRHR: Double?
    
    var sleepDuration: TimeInterval?
    var averageSleepDuration: TimeInterval?
    
    // MARK: - Context Metrics (Injected)
    var sleepDebt: TimeInterval?       // From WellnessManager
    var trainingStressBalance: Double? // From TrainingLoadManager
    
    /// Advanced readiness score (0-100)
    var readinessScore: Int {
        var score = 100.0
        
        // 1. SLEEP DURATION (40% Weight)
        // We blend "Personal Norm" with "Absolute Need" to avoid the "False 100%"
        if let sleep = sleepDuration {
            let baseline = averageSleepDuration ?? (7.5 * 3600)
            let absoluteNeed: TimeInterval = 8.0 * 3600
            
            // A: Did you hit your average?
            let baselineRatio = sleep / baseline
            
            // B: Did you hit 8 hours?
            let absoluteRatio = sleep / absoluteNeed
            
            // Blend: 40% credit for hitting average, 60% for hitting 8h
            // Example: 6h sleep (Avg 6h) -> (1.0 * 0.4) + (0.75 * 0.6) = 0.85 (15% deficit)
            var sleepFactor = (baselineRatio * 0.4) + (absoluteRatio * 0.6)
            sleepFactor = min(1.0, sleepFactor)
            
            // Quadratic penalty: Small deficits hurt a little; big ones hurt a lot.
            let penalty = 40.0 * (1.0 - pow(sleepFactor, 2))
            score -= penalty
        } else {
            score -= 10.0 // Missing data penalty
        }
        
        // 2. SLEEP DEBT (Wellness Context)
        // If you are carrying heavy debt from previous days, knock points off.
        if let debt = sleepDebt, debt < -2 { // More than 2 hours behind
            if debt < -5 {
                score -= 10 // Severe debt
            } else {
                score -= 5  // Moderate debt
            }
        }
        
        // 3. HRV DEVIATION (40% Weight)
        if let hrv = latestHRV, let avgHRV = averageHRV, avgHRV > 0 {
            let deviation = (hrv - avgHRV) / avgHRV
            
            if deviation < -0.15 {
                // >15% drop is a major warning
                score -= 25.0
            } else if deviation < -0.05 {
                // 5-15% drop is linear scaling
                let magnitude = (abs(deviation) - 0.05) * 100
                score -= (5.0 + magnitude)
            }
        }
        
        // 4. RHR DEVIATION (20% Weight)
        if let rhr = latestRHR, let avgRHR = averageRHR, avgRHR > 0 {
            let diff = rhr - avgRHR
            if diff > 5 { score -= 15 }       // High stress
            else if diff > 2 { score -= 5 }   // Mild stress
        }
        
        // 5. TRAINING LOAD CAP (TSB)
        // Ensure score reflects physical exhaustion
        if let tsb = trainingStressBalance {
            if tsb < -30 {
                score = min(score, 60.0) // Hard Cap: "Strained"
                score -= 5
            } else if tsb < -20 {
                score = min(score, 75.0) // Hard Cap: "Fatigued"
            }
        }
        
        return Int(max(0, min(100, score)))
    }
}
