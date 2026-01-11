//
//  WellnessRingView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 1/10/26.
//


import SwiftUI

struct WellnessRingView: View {
    let summary: WellnessSummary
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // HEADER
                HStack {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(.pink)
                    Text("Recovery")
                        .font(.headline)
                }
                
                // RINGS ROW
                HStack(spacing: 15) {
                    // 1. SLEEP RING
                    // Target: 8 hours (28800 seconds)
                    let sleepHours = summary.averageSleepHours ?? 0
                    let sleepProgress = min(sleepHours / 8.0, 1.0)
                    
                    RecoveryRing(
                        progress: sleepProgress,
                        valueText: String(format: "%.1fh", sleepHours),
                        icon: "bed.double.fill",
                        color: .blue
                    )
                    
                    // 2. ACTIVITY RING
                    // Target: 100 Activity Score
                    let activityScore = summary.averageActivityScore ?? 0
                    let activityProgress = min(activityScore / 100.0, 1.0)
                    
                    RecoveryRing(
                        progress: activityProgress,
                        valueText: "\(Int(activityScore))",
                        icon: "figure.walk",
                        color: .green
                    )
                }
                .padding(.vertical, 5)
                
                Divider()
                
                // INSIGHTS
                VStack(alignment: .leading, spacing: 8) {
                    // Sleep Debt Insight
                    if let debt = summary.sleepDebt {
                        HStack {
                            Image(systemName: debt < -2 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(debt < -2 ? .red : .green)
                            
                            if debt < -1 {
                                Text("\(abs(Int(debt)))h Sleep Debt")
                            } else {
                                Text("Sleep on Track")
                            }
                        }
                        .font(.caption)
                    }
                    
                    // Sleep Efficiency Insight
                    if let efficiency = summary.averageSleepEfficiency {
                        HStack {
                            Image(systemName: "moon.stars.fill")
                                .foregroundStyle(.yellow)
                            Text("Efficiency: \(Int(efficiency))%")
                        }
                        .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
}

// Helper View for the Rings
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