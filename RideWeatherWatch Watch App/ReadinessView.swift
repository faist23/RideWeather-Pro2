//
//  ReadinessView.swift
//  RideWeatherWatch Watch App
//
//  Fixed: Explicit background colors that should actually render
//

import SwiftUI

struct ReadinessView: View {
    let readiness: PhysiologicalReadiness
    let tsb: Double
    
    // Compute background color based on readiness score
    private var backgroundGradient: LinearGradient {
        let topColor: Color
        switch readiness.readinessScore {
        case 80...100:
            topColor = Color(red: 0, green: 0.5, blue: 0) // Green
        case 60..<80:
            topColor = Color(red: 0.5, green: 0.5, blue: 0) // Yellow
        case 40..<60:
            topColor = Color(red: 0.6, green: 0.3, blue: 0) // Orange
        default:
            topColor = Color(red: 0.5, green: 0, blue: 0) // Red
        }
        // Gradient to black for readability
        return LinearGradient(
            colors: [topColor, topColor.opacity(0.3), .black],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    var body: some View {
        ZStack {
            // Explicit background layer
            backgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 8) {
                    
                    // --- SECTION 1: DASHBOARD ---
                    HStack(alignment: .center, spacing: 8) {
                        
                        // LEFT: Score
                        VStack(spacing: -2) {
                            Text("\(readiness.readinessScore)")
                                .font(.system(size: 56, weight: .black, design: .rounded))
                                .foregroundStyle(readinessColor)
                                .shadow(color: readinessColor.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Text("READINESS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }
                        .frame(maxWidth: .infinity)
                        
                        // RIGHT: Drivers
                        VStack(alignment: .leading, spacing: 6) {
                            CompactMetricRow(
                                icon: "figure.strengthtraining.traditional",
                                value: tsb > 0 ? "+\(Int(tsb))" : "\(Int(tsb))",
                                unit: "TSB",
                                color: tsb > 10 ? .green : (tsb < -20 ? .red : .yellow)
                            )
                            
                            if let sleep = readiness.sleepDuration {
                                CompactMetricRow(
                                    icon: "bed.double.fill",
                                    value: String(format: "%.1f", sleep / 3600),
                                    unit: "hrs",
                                    color: .blue
                                )
                            }
                            
                            if let hrv = readiness.latestHRV {
                                CompactMetricRow(
                                    icon: "heart.fill",
                                    value: "\(Int(hrv))",
                                    unit: "ms",
                                    color: .purple
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 4)
                    
                    // --- SECTION 2: CONTEXT ---
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(readinessColor)
                                .frame(width: 40 + (CGFloat(readiness.readinessScore) / 100.0) * 100)
                        }
                        .padding(.vertical, 4)
                    
                    VStack(spacing: 2) {
                        Text(readinessStatus.uppercased())
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(readinessColor)
                        
                        Text(recommendation)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    WatchSyncIndicator().scaleEffect(0.7).opacity(0.5)
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var readinessColor: Color {
        switch readiness.readinessScore {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
    
    private var readinessStatus: String {
        switch readiness.readinessScore {
        case 85...100: return "Prime Condition"
        case 70..<85: return "Ready to Train"
        case 55..<70: return "Moderate Fatigue"
        case 40..<55: return "High Fatigue"
        default: return "Recovery Needed"
        }
    }
    
    private var recommendation: String {
        switch readiness.readinessScore {
        case 85...100: return "Go for intervals or race efforts."
        case 70..<85: return "Good day for a standard training block."
        case 55..<70: return "Stick to Zone 2 or steady tempo."
        case 40..<55: return "Keep it strictly aerobic (Z1/Z2)."
        default: return "Rest day or very light spin."
        }
    }
}

// SHARED HELPER (Ensure text is white)
struct CompactMetricRow: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 12)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
