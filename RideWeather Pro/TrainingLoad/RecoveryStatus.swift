//
//  RecoveryStatus.swift
//  RideWeather Pro
//
//  IMPORTANT: This file MUST be added to BOTH targets:
//  - RideWeather Pro (iPhone)
//  - RideWeatherWatch Watch App (Watch)
//
//  This file contains ONLY the shared data model (no UI code)
//

import Foundation
import SwiftUI

// MARK: - Recovery Status Model (Shared between iPhone and Watch)

struct RecoveryStatus: Codable {
    let recoveryPercent: Int
    let hoursSinceWorkout: Int
    let timeSinceWorkout: String
    let hrvStatus: String
    let sleepStatus: String
    let recommendation: String
    let currentHRV: Int
    let sleepDebt: Double?
    
    static func calculate(
        lastWorkoutDate: Date?,
        currentHRV: Double,
        baselineHRV: Double,
        currentRestingHR: Double,
        baselineRestingHR: Double,
        wellness: DailyWellnessMetrics,
        weekHistory: [DailyWellnessMetrics]
    ) -> RecoveryStatus {
        // Hours since last workout
        let hoursSinceWorkout: Int
        let timeSinceWorkoutText: String
        if let lastWorkout = lastWorkoutDate {
            hoursSinceWorkout = Int(Date().timeIntervalSince(lastWorkout) / 3600)
            if hoursSinceWorkout < 24 {
                timeSinceWorkoutText = "\(hoursSinceWorkout)h"
            } else {
                let days = hoursSinceWorkout / 24
                timeSinceWorkoutText = "\(days)d"
            }
        } else {
            hoursSinceWorkout = 48
            timeSinceWorkoutText = "48h+"
        }
        
        // Recovery Percentage (0-100)
        var recoveryScore = 0.0
        
        // Time component (0-40 points): Full recovery at 48h
        let timeScore = min(40.0, (Double(hoursSinceWorkout) / 48.0) * 40.0)
        recoveryScore += timeScore
        
        // HRV component (0-30 points)
        let hrvRecovery = (currentHRV / baselineHRV)
        let hrvScore = min(30.0, hrvRecovery * 30.0)
        recoveryScore += hrvScore
        
        // HR component (0-20 points)
        let hrRecovery = (baselineRestingHR / currentRestingHR)
        let hrScore = min(20.0, hrRecovery * 20.0)
        recoveryScore += hrScore
        
        // Sleep component (0-10 points)
        if let sleepHours = wellness.totalSleep {
            let sleepScore = min(10.0, (sleepHours / 28800) * 10.0)
            recoveryScore += sleepScore
        }
        
        let finalRecovery = Int(min(100, recoveryScore))
        
        // HRV Status
        let hrvDiff = currentHRV - baselineHRV
        let hrvStatus: String
        if hrvDiff > 5 {
            hrvStatus = "Good"
        } else if hrvDiff > -5 {
            hrvStatus = "Normal"
        } else {
            hrvStatus = "Low"
        }
        
        // Sleep Status
        let sleepStatus: String
        if let sleep = wellness.totalSleep {
            let hours = sleep / 3600
            if hours >= 7.5 {
                sleepStatus = "Good"
            } else if hours >= 6 {
                sleepStatus = "Fair"
            } else {
                sleepStatus = "Poor"
            }
        } else {
            sleepStatus = "Unknown"
        }
        
        // Recommendation
        let recommendation: String
        if finalRecovery >= 85 {
            recommendation = "Fully recovered. Ready for high-intensity training."
        } else if finalRecovery >= 70 {
            recommendation = "Good recovery. Can handle moderate to hard efforts."
        } else if finalRecovery >= 50 {
            recommendation = "Partial recovery. Keep intensity low to moderate."
        } else {
            recommendation = "Still recovering. Prioritize rest or very easy activity."
        }
        
        // Sleep Debt
        let totalSleep = weekHistory.prefix(7).compactMap { $0.totalSleep }.reduce(0, +)
        let targetSleep = 8.0 * 3600 * 7
        let sleepDebt = (totalSleep - targetSleep) / 3600
        
        return RecoveryStatus(
            recoveryPercent: finalRecovery,
            hoursSinceWorkout: hoursSinceWorkout,
            timeSinceWorkout: timeSinceWorkoutText,
            hrvStatus: hrvStatus,
            sleepStatus: sleepStatus,
            recommendation: recommendation,
            currentHRV: Int(currentHRV),
            sleepDebt: sleepDebt < -1 ? sleepDebt : nil
        )
    }
}

// MARK: - Trend Direction (for display only)

enum TrendDirection {
    case up, down, stable
    
    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .stable: return .secondary
        }
    }
}
