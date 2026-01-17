//
//  RecoveryStatusCard.swift
//  RideWeather Pro
//

import SwiftUI

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

