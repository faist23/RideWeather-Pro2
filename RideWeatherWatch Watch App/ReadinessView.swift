//
//  ReadinessView.swift
//  RideWeatherWatch Watch App
//

import SwiftUI

struct ReadinessView: View {
    let readiness: PhysiologicalReadiness
    let tsb: Double
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // GIANT READINESS SCORE WITH LABEL
                VStack(spacing: 8) {
                    Text("READINESS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(readiness.readinessScore)")
                            .font(.system(size: 80, weight: .black, design: .rounded))
                            .foregroundStyle(readinessColor)
                        
                        Text("/100")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(readinessStatus.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(readinessColor)
                        .tracking(1)
                    
                    // Progress Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(readinessColor.gradient)
                                .frame(width: geometry.size.width * CGFloat(readiness.readinessScore) / 100, height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                
                // RECOMMENDATION
                VStack(spacing: 4) {
                    Text("TODAY'S PLAN")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    
                    Text(recommendation)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal)
                
                // KEY METRICS PILLS
                VStack(spacing: 4) {
                    Text("KEY METRICS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    
                    HStack(spacing: 8) {
                        MetricPill(
                            label: "Form",
                            value: tsb > 0 ? "+\(Int(tsb))" : "\(Int(tsb))",
                            color: .green
                        )
                        
                        if let sleep = readiness.sleepDuration {
                            MetricPill(
                                label: "Sleep",
                                value: String(format: "%.1fh", sleep / 3600),
                                color: .blue
                            )
                        }
                        
                        if let hrv = readiness.latestHRV {
                            MetricPill(
                                label: "HRV",
                                value: "\(Int(hrv))",
                                color: .purple
                            )
                        } else if let rhr = readiness.latestRHR {
                            MetricPill(
                                label: "RHR",
                                value: "\(Int(rhr))",
                                color: .red
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding()
        }
        .containerBackground(backgroundColor.gradient, for: .tabView)
    }
    
    // MARK: - Computed Properties
    
    private var readinessColor: Color {
        switch readiness.readinessScore {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
    
    private var backgroundColor: Color {
        switch readiness.readinessScore {
        case 80...100: return Color(red: 0, green: 0.3, blue: 0)
        case 60..<80: return Color(red: 0.3, green: 0.3, blue: 0)
        case 40..<60: return Color(red: 0.3, green: 0.15, blue: 0)
        default: return Color(red: 0.3, green: 0, blue: 0)
        }
    }
    
    private var readinessStatus: String {
        switch readiness.readinessScore {
        case 85...100: return "Ready to Race"
        case 70..<85: return "Ready to Work"
        case 55..<70: return "Moderate Day"
        case 40..<55: return "Easy Day"
        default: return "Rest Day"
        }
    }
    
    private var recommendation: String {
        switch readiness.readinessScore {
        case 85...100: return "Peak form - intervals or race pace"
        case 70..<85: return "Good day for hard efforts"
        case 55..<70: return "Steady endurance or tempo"
        case 40..<55: return "Keep it light - recovery pace"
        default: return "Prioritize recovery today"
        }
    }
}

struct MetricPill: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.5), lineWidth: 1)
        )
    }
}
