//
//  PacingComparisonView.swift
//  RideWeather Pro
//

import SwiftUI

struct PacingComparisonView: View {
    let comparison: PacingPlanComparison
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Performance grade header
                    performanceHeader
                    
                    // Quick stats
                    quickStats
                    
                    // Segment results
                    if !comparison.segmentResults.isEmpty {
                        segmentResultsSection
                    }
                    
                    // Insights
                    insightsSection
                }
                .padding()
            }
            .navigationTitle(comparison.routeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var performanceHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: comparison.performanceGrade.color))
                    .frame(width: 100, height: 100)
                
                Text(comparison.performanceGrade.rawValue)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("Performance Grade")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var quickStats: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatCard(title: "Time", value: formatTime(comparison.actualTime), subtitle: formatTimeDiff(comparison.timeDifference))
                StatCard(title: "Power", value: "\(Int(comparison.actualPower))W", subtitle: "\(Int(comparison.powerEfficiency))%")
            }
            
            if comparison.totalPotentialTimeSavings > 0 {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.orange)
                    Text("Potential time savings: \(formatTime(comparison.totalPotentialTimeSavings))")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private var segmentResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Segment Analysis")
                .font(.headline)
            
            ForEach(comparison.segmentResults) { result in
                SegmentResultRow(result: result)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !comparison.strengths.isEmpty {
                Text("Strengths")
                    .font(.headline)
                ForEach(comparison.strengths, id: \.self) { strength in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(strength)
                            .font(.subheadline)
                    }
                }
            }
            
            if !comparison.improvements.isEmpty {
                Text("Areas for Improvement")
                    .font(.headline)
                    .padding(.top, 8)
                ForEach(comparison.improvements, id: \.self) { improvement in
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.orange)
                        Text(improvement)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    private func formatTimeDiff(_ seconds: TimeInterval) -> String {
        if seconds < 0 {
            return "↓ \(formatTime(abs(seconds)))"
        } else if seconds > 0 {
            return "↑ \(formatTime(seconds))"
        }
        return "On target"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct SegmentResultRow: View {
    let result: PacingPlanComparison.SegmentResult
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: result.grade.color))
                .frame(width: 30, height: 30)
                .overlay(
                    Text(result.grade.rawValue)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.segmentName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(Int(result.actualPower))W vs \(Int(result.plannedPower))W")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(String(format: "%+.1f%%", result.deviation))
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(result.deviation > 5 ? .red : result.deviation < -5 ? .orange : .green)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

/*// Color extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}*/
