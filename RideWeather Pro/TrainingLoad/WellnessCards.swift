//
//  WellnessCards.swift
//  RideWeather Pro
//
//  UI components for displaying wellness metrics
//

import SwiftUI

// MARK: - Daily Wellness Card

struct DailyWellnessCard: View {
    let metrics: DailyWellnessMetrics
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Daily Wellness")
                    .font(.headline)
                
                Spacer()
                
                if let score = overallWellnessScore {
                    Text("\(score)%")
                        .font(.title2.weight(.bold))
                        .foregroundColor(scoreColor(score))
                }
            }
            
            // Quick Stats Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                
                WellnessMetricCell(
                    icon: "figure.walk",
                    title: "Steps",
                    value: metrics.steps.map { "\(formatNumber($0))" } ?? "—",
                    color: .blue
                )
                
                WellnessMetricCell(
                    icon: "bed.double.fill",
                    title: "Sleep",
                    value: metrics.totalSleep.map { formatDuration($0) } ?? "—",
                    color: .purple
                )
                
                WellnessMetricCell(
                    icon: "flame.fill",
                    title: "Active kcal",
                    value: metrics.activeEnergyBurned.map { "\(Int($0))" } ?? "—",
                    color: .orange
                )
            }
            
            // Expandable Details
            if isExpanded {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(spacing: 12) {
                    // Sleep Quality
                    if let deep = metrics.sleepDeep, let rem = metrics.sleepREM {
                        SleepQualitySection(
                            deep: deep,
                            rem: rem,
                            core: metrics.sleepCore,
                            efficiency: metrics.computedSleepEfficiency
                        )
                    }
                    
                    // Activity Rings
                    if metrics.steps != nil || metrics.exerciseMinutes != nil {
                        ActivityRingsSection(
                            steps: metrics.steps,
                            exerciseMinutes: metrics.exerciseMinutes,
                            standHours: metrics.standHours
                        )
                    }
                    
                    // Body Metrics
                    if metrics.bodyMass != nil || metrics.bodyFatPercentage != nil {
                        BodyMetricsSection(
                            mass: metrics.bodyMass,
                            bodyFat: metrics.bodyFatPercentage,
                            leanMass: metrics.leanBodyMass
                        )
                    }
                }
            }
            
            // Expand/Collapse Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Show Less" : "Show Details")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var overallWellnessScore: Int? {
        var components: [Int] = []
        
        if let activityScore = metrics.activityScore {
            components.append(activityScore)
        }
        if let sleepScore = metrics.sleepQualityScore {
            components.append(sleepScore)
        }
        
        guard !components.isEmpty else { return nil }
        return components.reduce(0, +) / components.count
    }
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 85...: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 10000 {
            return String(format: "%.1fk", Double(num) / 1000)
        }
        return "\(num)"
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Wellness Metric Cell

struct WellnessMetricCell: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Sleep Quality Section

struct SleepQualitySection: View {
    let deep: TimeInterval
    let rem: TimeInterval
    let core: TimeInterval?
    let efficiency: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundColor(.purple)
                Text("Sleep Quality")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let efficiency = efficiency {
                    Text("\(Int(efficiency))% efficient")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 16) {
                SleepStageBar(
                    label: "Deep",
                    duration: deep,
                    color: .indigo
                )
                
                SleepStageBar(
                    label: "REM",
                    duration: rem,
                    color: .purple
                )
                
                if let core = core {
                    SleepStageBar(
                        label: "Core",
                        duration: core,
                        color: .blue
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(12)
    }
}

struct SleepStageBar: View {
    let label: String
    let duration: TimeInterval
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(formatTime(duration))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Activity Rings Section

struct ActivityRingsSection: View {
    let steps: Int?
    let exerciseMinutes: Int?
    let standHours: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.mixed.cardio")
                    .foregroundColor(.green)
                Text("Activity")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            HStack(spacing: 20) {
                if let steps = steps {
                    ActivityRing(
                        value: Double(steps),
                        goal: 8000,
                        label: "Steps",
                        color: .cyan
                    )
                }
                
                if let exercise = exerciseMinutes {
                    ActivityRing(
                        value: Double(exercise),
                        goal: 30,
                        label: "Exercise",
                        color: .green
                    )
                }
                
                if let stand = standHours {
                    ActivityRing(
                        value: Double(stand),
                        goal: 12,
                        label: "Stand",
                        color: .pink
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(12)
    }
}

struct ActivityRing: View {
    let value: Double
    let goal: Double
    let label: String
    let color: Color
    
    var progress: Double {
        min(value / goal, 1.0)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(value))")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Body Metrics Section

struct BodyMetricsSection: View {
    let mass: Double?
    let bodyFat: Double?
    let leanMass: Double?
    
    @EnvironmentObject var viewModel: WeatherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.stand")
                    .foregroundColor(.blue)
                Text("Body Composition")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            HStack(spacing: 16) {
                if let mass = mass {
                    BodyMetricItem(
                        label: "Weight",
                        value: formatWeight(mass), // Use unit-aware formatter
                        color: .blue
                    )
                }
                
                if let bodyFat = bodyFat {
                    BodyMetricItem(
                        label: "Body Fat",
                        value: String(format: "%.1f%%", bodyFat * 100),
                        color: .orange
                    )
                }
                
                if let leanMass = leanMass {
                    BodyMetricItem(
                        label: "Lean Mass",
                        value: formatWeight(leanMass), // Use unit-aware formatter
                        color: .green
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(12)
    }
    // Helper to format weight based on settings
    private func formatWeight(_ kg: Double) -> String {
        let units = viewModel.settings.units
        let val = units == .metric ? kg : kg * 2.20462
        return String(format: "%.1f %@", val, units.weightSymbol)
    }
}

struct BodyMetricItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Wellness Summary Card

struct WellnessSummaryCard: View {
    let summary: WellnessSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wellness Trends")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                
                TrendMetricCard(
                    title: "Avg Steps",
                    value: summary.averageSteps.map { "\(Int($0))" } ?? "—",
                    trend: summary.activityTrend,
                    color: .blue
                )
                
                TrendMetricCard(
                    title: "Avg Sleep",
                    value: summary.averageSleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                    trend: nil,
                    color: .purple
                )
                
                TrendMetricCard(
                    title: "Sleep Efficiency",
                    value: summary.averageSleepEfficiency.map { "\(Int($0))%" } ?? "—",
                    trend: nil,
                    color: .indigo
                )
                
                TrendMetricCard(
                    title: "Activity Score",
                    value: summary.averageActivityScore.map { "\(Int($0))" } ?? "—",
                    trend: summary.activityTrend,
                    color: .green
                )
            }
            
            // Sleep Debt Warning
            if let debt = summary.sleepDebt, debt < -2 {
                HStack(spacing: 8) {
                    Image(systemName: debt < -5 ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundColor(debt < -5 ? .red : .orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Debt: \(abs(Int(debt))) hours")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("Prioritize rest to support recovery")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct TrendMetricCard: View {
    let title: String
    let value: String
    let trend: Double?
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                if let trend = trend {
                    Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption)
                        .foregroundColor(trend > 0 ? .green : .red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Combined Insight Card

struct CombinedInsightCard: View {
    let insight: CombinedInsight
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: insight.icon)
                    .font(.title3)
                    .foregroundColor(insight.priority.color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(insight.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text("Recommendation")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    Text(insight.recommendation)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        DailyWellnessCard(metrics: DailyWellnessMetrics(
            date: Date(),
            steps: 8547,
            activeEnergyBurned: 456,
            basalEnergyBurned: 1680,
            standHours: 11,
            exerciseMinutes: 45,
            sleepDeep: 1.5 * 3600,
            sleepREM: 1.8 * 3600,
            sleepCore: 3.2 * 3600,
            sleepAwake: 0.3 * 3600,
            bodyMass: 75.2,
            bodyFatPercentage: 0.145,
            leanBodyMass: 64.3
        ))
        .environmentObject(WeatherViewModel()) // Inject mock VM for preview
        
        CombinedInsightCard(insight: CombinedInsight(
            title: "Inactive Recovery Detected",
            message: "TSB shows you're recovered (+8), but you're averaging only 4,200 steps/day",
            recommendation: "Add 20-30min easy walks daily. Active recovery improves circulation and speeds healing.",
            priority: .medium,
            icon: "figure.walk"
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
