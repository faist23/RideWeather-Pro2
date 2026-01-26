//
//  RecoveryView.swift
//  RideWeatherWatch Watch App
//
//  Fixed: Explicit dark blue background
//

import SwiftUI

struct RecoveryView: View {
    let recovery: RecoveryStatus
    let wellness: DailyWellnessMetrics
    
    var body: some View {
        ZStack {
            // Explicit background - blue gradient to black
            LinearGradient(
                colors: [Color(red: 0, green: 0.15, blue: 0.4), Color(red: 0, green: 0.08, blue: 0.25), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 8) {
                    
                    // --- PRIMARY DASHBOARD ---
                    HStack(alignment: .center, spacing: 8) {
                        
                        // LEFT: Recovery Score
                        VStack(spacing: -2) {
                            Text("\(recovery.recoveryPercent)")
                                .font(.system(size: 56, weight: .black, design: .rounded))
                                .foregroundStyle(recoveryColor)
                                .shadow(color: recoveryColor.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Text("%")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                                .offset(y: -4)
                        }
                        .frame(maxWidth: .infinity)
                        
                        // RIGHT: Biometrics
                        VStack(alignment: .leading, spacing: 6) {
                            // Sleep
                            CompactMetricRow(
                                icon: "moon.stars.fill",
                                value: String(format: "%.1f", (wellness.totalSleep ?? 0) / 3600),
                                unit: "hrs",
                                color: .blue
                            )
                            
                            // HRV
                            CompactMetricRow(
                                icon: "heart.fill",
                                value: "\(recovery.currentHRV)",
                                unit: "HRV",
                                color: .purple
                            )
                            
                            // RHR
                            CompactMetricRow(
                                icon: "waveform.path.ecg",
                                value: "\(wellness.restingHeartRate ?? 0)",
                                unit: "bpm",
                                color: .red
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 4)
                    
                    // --- ACTION ---
                    VStack(spacing: 2) {
                        Text(recovery.hrvStatus.uppercased())
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(recoveryColor)
                        
                        Text(recovery.recommendation)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    WatchSyncIndicator()
                        .scaleEffect(0.7)
                        .opacity(0.5)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var recoveryColor: Color {
        if recovery.recoveryPercent >= 80 { return .green }
        if recovery.recoveryPercent >= 50 { return .yellow }
        return .red
    }
}

/*
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
} */

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
