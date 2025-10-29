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
            HStack {
                Text("Time Opportunities")
                    .font(.headline)
                
                Spacer()
                
                if comparison.totalPotentialTimeSavings > 0 {
                    Text("↑ \(formatTime(comparison.totalPotentialTimeSavings))")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
            }
            
            if comparison.segmentResults.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Nearly perfect execution!")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                Text("Biggest opportunities ranked by time impact:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(comparison.segmentResults.prefix(10)) { result in
                    TimeOpportunityRow(result: result)
                }
                
                if comparison.segmentResults.count > 10 {
                    Text("+ \(comparison.segmentResults.count - 10) more opportunities")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    struct TimeOpportunityRow: View {
        let result: PacingPlanComparison.SegmentResult
        @State private var isExpanded = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Circle()
                            .fill(Color(hex: result.grade.color))
                            .frame(width: 8, height: 8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.segmentName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 8) {
                                if result.timeLost > 0 {
                                    Text("↑ \(formatTime(result.timeLost)) slower")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                } else {
                                    Text("↓ \(formatTime(abs(result.timeLost))) faster")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                
                                // 🔥 Show context issues
                                if !result.contextIssues.isEmpty {
                                    Text("• \(result.contextIssues.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                        
                        // Power comparison
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your Power")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(Int(result.actualPower))W")
                                    .font(.headline)
                            }
                            
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Planned Power")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(Int(result.plannedPower))W")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Difference")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(result.deviation > 0 ? "+" : "")\(Int(result.deviation))%")
                                    .font(.headline)
                                    .foregroundColor(result.deviation > 5 ? .red : result.deviation < -5 ? .green : .primary)
                            }
                        }
                        
                        // 🔥 Show context reason if available
                        if let reason = result.contextReason {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                
                                Text(reason)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        
                        // Actionable recommendation
                        if abs(result.deviation) > 5 && result.contextIssues.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                
                                Text(getRecommendation(for: result))
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        
        private func getRecommendation(for result: PacingPlanComparison.SegmentResult) -> String {
            let powerDiff = abs(Int(result.plannedPower - result.actualPower))
            
            if result.segmentName.contains("Climb") {
                if result.deviation < 0 {
                    return "On climbs, push \(powerDiff)W harder. Watts translate almost linearly to speed uphill - this is where you buy time."
                } else {
                    return "Good climb execution! You pushed close to the planned power."
                }
            } else if result.segmentName.contains("Flat") {
                if result.deviation > 10 {
                    return "You over-cooked this flat section. Save \(powerDiff)W for the climbs where it matters more."
                } else if result.deviation < -10 {
                    return "Maintain \(powerDiff)W more on flats to keep momentum. Small power increases = big speed gains on flat terrain."
                }
            } else { // Descent or rolling
                return "Focus on aero position and steady power around \(Int(result.plannedPower))W."
            }
            
            return "Stay within ±5% of target power for optimal pacing."
        }
        
        private func formatTime(_ seconds: TimeInterval) -> String {
            let absSeconds = abs(seconds)
            if absSeconds >= 60 {
                let mins = Int(absSeconds / 60)
                let secs = Int(absSeconds.truncatingRemainder(dividingBy: 60))
                return "\(mins):\(String(format: "%02d", secs))"
            }
            return "\(Int(absSeconds))s"
        }
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
