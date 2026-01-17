//
//  RecoveryStatus.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 1/16/26.
//


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
    
    // These can't be encoded easily, so we'll compute them on display
    // let hrvTrend: TrendDirection
    // let restingHRTrend: TrendDirection
    
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

// MARK: - Recovery Status Card for iPhone

struct RecoveryStatusCard: View {
    let recovery: RecoveryStatus
    let wellness: DailyWellnessMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeaderWithInfo(
                title: "Recovery Status",
                infoTitle: "Recovery Status",
                infoMessage: "Calculates your recovery percentage based on:\n• Time since last workout (40%)\n• HRV vs baseline (30%)\n• Resting heart rate (20%)\n• Sleep quality (10%)\n\nHelps you decide if you're ready for hard efforts or should take it easy."
            )
            
            HStack {
                Spacer()
                
                Text("\(recovery.recoveryPercent)%")
                    .font(.title2.weight(.bold))
                    .foregroundColor(recoveryColor)
            }
            
            // Recovery gauge
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                        .frame(height: 12)
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.red, .orange, .yellow, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(recovery.recoveryPercent) / 100, height: 12)
                }
            }
            .frame(height: 12)
            
            // Key metrics
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                RecoveryMetricCompact(
                    title: "Since Workout",
                    value: recovery.timeSinceWorkout,
                    icon: "clock"
                )
                
                RecoveryMetricCompact(
                    title: "HRV Status",
                    value: recovery.hrvStatus,
                    icon: "waveform.path.ecg"
                )
                
                RecoveryMetricCompact(
                    title: "Sleep Quality",
                    value: recovery.sleepStatus,
                    icon: "bed.double.fill"
                )
            }
            
            // Recommendation
            Text(recovery.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var recoveryColor: Color {
        switch recovery.recoveryPercent {
        case 85...: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
}

struct RecoveryMetricCompact: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(10)
    }
}

