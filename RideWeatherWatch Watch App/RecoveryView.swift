//
//  RecoveryView.swift
//  RideWeatherWatch Watch App
//

import SwiftUI

struct RecoveryView: View {
    let recovery: RecoveryStatus
    let wellness: DailyWellnessMetrics
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // RECOVERY PERCENTAGE WITH CONTEXT
                VStack(spacing: 4) {
                    Text("RECOVERY STATUS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(recovery.recoveryPercent)")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundStyle(.cyan)
                        
                        Text("%")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.cyan.opacity(0.7))
                    }
                    
                    Text("RECOVERED")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    
                    Text("\(recovery.hoursSinceRide)h since last ride")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                
                // RECOVERY RINGS
                HStack(spacing: 12) {
                    RecoveryRing(
                        progress: min((wellness.totalSleep ?? 0) / 28800, 1.0),
                        valueText: String(format: "%.1fh", (wellness.totalSleep ?? 0) / 3600),
                        icon: "bed.double.fill",
                        color: .blue
                    )

                    RecoveryRing(
                        progress: min(Double(recovery.currentHRV) / 100, 1.0),
                        valueText: "\(recovery.currentHRV)",
                        icon: "heart.fill",
                        color: .purple
                    )

                    RecoveryRing(
                        progress: min((100 - Double(wellness.restingHeartRate ?? 60)) / 100, 1.0),
                        valueText: "\(wellness.restingHeartRate ?? 60)",
                        icon: "waveform.path.ecg",
                        color: .red
                    )
                }
                
                Divider()
                
                // DETAILED METRICS
                VStack(spacing: 6) {
                    RecoveryMetric(
                        icon: "moon.stars.fill",
                        label: "Sleep Efficiency",
                        value: "\(Int(wellness.computedSleepEfficiency ?? 0))%",
                        trend: nil,
                        status: (wellness.computedSleepEfficiency ?? 0) >= 85 ? .good : .warning
                    )
                    
                    RecoveryMetric(
                        icon: "heart.fill",
                        label: "HRV Trend",
                        value: "\(recovery.currentHRV)",
                        trend: recovery.hrvTrend,
                        status: recovery.hrvTrend == .up ? .good : .warning
                    )
                    
                    RecoveryMetric(
                        icon: "waveform.path.ecg",
                        label: "Resting HR",
                        value: "\(wellness.restingHeartRate ?? 0) bpm",
                        trend: recovery.restingHRTrend,
                        status: recovery.restingHRTrend == .down ? .good : .warning
                    )
                    
                    if let sleepDebt = recovery.sleepDebt, sleepDebt < -1 {
                        RecoveryMetric(
                            icon: "exclamationmark.triangle.fill",
                            label: "Sleep Debt",
                            value: "\(abs(Int(sleepDebt)))h behind",
                            trend: nil,
                            status: .warning
                        )
                    }
                }
            }
            .padding()
        }
        .containerBackground(.black.gradient, for: .tabView)
    }
}

// MARK: - Recovery Ring

struct RecoveryRing: View {
    let progress: Double
    let valueText: String
    let icon: String
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(valueText)
                    .font(.system(size: 10).bold())
            }
        }
        .frame(width: 55, height: 55)
    }
}

// MARK: - Recovery Metric

struct RecoveryMetric: View {
    let icon: String
    let label: String
    let value: String
    let trend: TrendDirection?
    let status: MetricStatus
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(status.color)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            if let trend = trend {
                Image(systemName: trend.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(trend.color)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
        )
    }
}

enum MetricStatus {
    case good, warning, bad
    
    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        }
    }
}

// MARK: - Recovery Status Model

struct RecoveryStatus {
    let recoveryPercent: Int
    let hoursSinceRide: Int
    let currentHRV: Int
    let hrvTrend: TrendDirection
    let restingHRTrend: TrendDirection
    let sleepDebt: Double?
    
    static func calculate(
        lastRideDate: Date?,
        currentHRV: Double,
        baselineHRV: Double,
        currentRestingHR: Double,
        baselineRestingHR: Double,
        wellness: DailyWellnessMetrics,
        weekHistory: [DailyWellnessMetrics]
    ) -> RecoveryStatus {
        // Hours since last ride
        let hoursSinceRide: Int
        if let lastRide = lastRideDate {
            hoursSinceRide = Int(Date().timeIntervalSince(lastRide) / 3600)
        } else {
            hoursSinceRide = 48 // Default to "recovered" if no recent ride
        }
        
        // Recovery Percentage (0-100)
        // Based on: time elapsed, HRV recovery, HR recovery, sleep quality
        var recoveryScore = 0.0
        
        // Time component (0-40 points): Full recovery at 48h
        let timeScore = min(40.0, (Double(hoursSinceRide) / 48.0) * 40.0)
        recoveryScore += timeScore
        
        // HRV component (0-30 points): At or above baseline = 30
        let hrvRecovery = (currentHRV / baselineHRV)
        let hrvScore = min(30.0, hrvRecovery * 30.0)
        recoveryScore += hrvScore
        
        // HR component (0-20 points): At or below baseline = 20
        let hrRecovery = (baselineRestingHR / currentRestingHR)
        let hrScore = min(20.0, hrRecovery * 20.0)
        recoveryScore += hrScore
        
        // Sleep component (0-10 points): 8h+ good sleep = 10
        if let sleepHours = wellness.totalSleep {
            let sleepScore = min(10.0, (sleepHours / 28800) * 10.0)
            recoveryScore += sleepScore
        }
        
        let finalRecovery = Int(min(100, recoveryScore))
        
        // HRV Trend (compare to 7-day average)
        let recentHRVs = weekHistory.prefix(7).compactMap { $0.restingHeartRate }.map { Double($0) }
        let avgRecentHRV = recentHRVs.isEmpty ? baselineHRV : recentHRVs.reduce(0, +) / Double(recentHRVs.count)
        let hrvTrend: TrendDirection = currentHRV > avgRecentHRV + 2 ? .up : (currentHRV < avgRecentHRV - 2 ? .down : .stable)
        
        // Resting HR Trend
        let recentHRs = weekHistory.prefix(7).compactMap { $0.restingHeartRate }.map { Double($0) }
        let avgRecentHR = recentHRs.isEmpty ? baselineRestingHR : recentHRs.reduce(0, +) / Double(recentHRs.count)
        let restingHRTrend: TrendDirection = currentRestingHR < avgRecentHR - 2 ? .down : (currentRestingHR > avgRecentHR + 2 ? .up : .stable)
        
        // Sleep Debt (last 7 days)
        let totalSleep = weekHistory.prefix(7).compactMap { $0.totalSleep }.reduce(0, +)
        let targetSleep = 8.0 * 3600 * 7 // 8 hours per night
        let sleepDebt = (totalSleep - targetSleep) / 3600
        
        return RecoveryStatus(
            recoveryPercent: finalRecovery,
            hoursSinceRide: hoursSinceRide,
            currentHRV: Int(currentHRV),
            hrvTrend: hrvTrend,
            restingHRTrend: restingHRTrend,
            sleepDebt: sleepDebt < -1 ? sleepDebt : nil
        )
    }
}
