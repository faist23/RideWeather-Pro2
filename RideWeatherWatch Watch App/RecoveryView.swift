//
//  RecoveryView.swift
//  RideWeatherWatch Watch App
//
//  UPDATED: Now uses synced RecoveryStatus from iPhone instead of calculating locally
//

import SwiftUI

struct RecoveryView: View {
    let recovery: RecoveryStatus
    let wellness: DailyWellnessMetrics
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                WatchSyncIndicator()
                    .padding(.bottom, 1)

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
                    
                    Text("\(recovery.hoursSinceWorkout)h since last workout")
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
                        status: (wellness.computedSleepEfficiency ?? 0) >= 85 ? .good : .warning
                    )
                    
                    RecoveryMetric(
                        icon: "heart.fill",
                        label: "HRV Status",
                        value: recovery.hrvStatus,
                        status: recovery.hrvStatus == "Good" ? .good : (recovery.hrvStatus == "Low" ? .bad : .warning)
                    )
                    
                    RecoveryMetric(
                        icon: "waveform.path.ecg",
                        label: "Resting HR",
                        value: "\(wellness.restingHeartRate ?? 0) bpm",
                        status: .good
                    )
                    
                    if let sleepDebt = recovery.sleepDebt, sleepDebt < -1 {
                        RecoveryMetric(
                            icon: "exclamationmark.triangle.fill",
                            label: "Sleep Debt",
                            value: "\(abs(Int(sleepDebt)))h behind",
                            status: .warning
                        )
                    }
                }
                
                // RECOMMENDATION
                Text(recovery.recommendation)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
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

// MARK: - Recovery Metric (Simplified - no trend icons)

struct RecoveryMetric: View {
    let icon: String
    let label: String
    let value: String
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

// REMOVED: RecoveryStatus struct - now using the shared Codable version from iPhone
// The recovery parameter passed to this view comes from WatchSessionManager.shared.recoveryStatus
