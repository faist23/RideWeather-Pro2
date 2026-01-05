//
//  WellnessTrendChart.swift
//  RideWeather Pro
//
//  Multi-metric wellness trend visualization
//

import SwiftUI
import Charts

struct WellnessTrendChart: View {
    let metrics: [DailyWellnessMetrics]
    @State private var selectedMetric: WellnessMetricType = .weight
    @State private var selectedPeriod: WellnessPeriod = .twoWeeks
    
    enum WellnessPeriod: Int, CaseIterable {
        case week = 7
        case twoWeeks = 14
        case month = 30
        case threeMonths = 90
        
        var name: String {
            switch self {
            case .week: return "Week"
            case .twoWeeks: return "2 Weeks"
            case .month: return "Month"
            case .threeMonths: return "3 Months"
            }
        }
    }
    
    enum WellnessMetricType: String, CaseIterable {
        case weight = "Weight"
        case sleep = "Sleep"
        case steps = "Steps"
        case restingHR = "Resting HR"
        case sleepEfficiency = "Sleep Quality"
        case activeCalories = "Active Energy"
        
        var icon: String {
            switch self {
            case .weight: return "scalemass.fill"
            case .sleep: return "bed.double.fill"
            case .steps: return "figure.walk"
            case .restingHR: return "heart.fill"
            case .sleepEfficiency: return "moon.stars.fill"
            case .activeCalories: return "flame.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .weight: return .purple
            case .sleep: return .indigo
            case .steps: return .green
            case .restingHR: return .red
            case .sleepEfficiency: return .blue
            case .activeCalories: return .orange
            }
        }
        
        func unit(weightUnit: String) -> String {
            switch self {
            case .weight: return weightUnit
            case .sleep: return "hrs"
            case .steps: return "steps"
            case .restingHR: return "bpm"
            case .sleepEfficiency: return "%"
            case .activeCalories: return "kcal"
            }
        }
    }
    
    // User's preferred units
    private var weightUnit: String {
        let locale = Locale.current
        let usesMetric = locale.measurementSystem == .metric
        return usesMetric ? "kg" : "lbs"
    }
    
    private var filteredMetrics: [DailyWellnessMetrics] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cutoffDate = calendar.date(byAdding: .day, value: -selectedPeriod.rawValue, to: today)!
        
        return metrics
            .filter { $0.date >= cutoffDate && $0.date <= today }
            .sorted { $0.date < $1.date }
    }
    
    private var xDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -selectedPeriod.rawValue, to: today)!
        return startDate...today
    }
    
    private var chartData: [(date: Date, value: Double)] {
        filteredMetrics.compactMap { metric in
            guard let value = getValue(for: metric) else { return nil }
            return (date: metric.date, value: value)
        }
    }
    
    private func getValue(for metric: DailyWellnessMetrics) -> Double? {
        switch selectedMetric {
        case .weight:
            guard let kg = metric.bodyMass else { return nil }
            // Convert to user's preferred unit
            if weightUnit == "lbs" {
                return kg * 2.20462
            }
            return kg
        case .sleep:
            guard let sleep = metric.totalSleep else { return nil }
            return sleep / 3600.0 // Convert seconds to hours
        case .steps:
            return metric.steps.map { Double($0) }
        case .restingHR:
            return metric.restingHeartRate.map { Double($0) }
        case .sleepEfficiency:
            return metric.computedSleepEfficiency
        case .activeCalories:
            return metric.activeEnergyBurned
        }
    }
    
    private var averageValue: Double? {
        let values = chartData.map { $0.value }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private var yDomain: ClosedRange<Double>? {
        let values = chartData.map { $0.value }
        guard !values.isEmpty else { return nil }
        
        let minValue = values.min()!
        let maxValue = values.max()!
        
        // For weight, use a tighter range
        if selectedMetric == .weight {
            let range = maxValue - minValue
            let padding = max(range * 0.2, 1.0) // At least 1 unit padding
            return (minValue - padding)...(maxValue + padding)
        }
        
        // For other metrics, add 10% padding
        let range = maxValue - minValue
        let padding = max(range * 0.1, 1.0)
        return (minValue - padding)...(maxValue + padding)
    }
    
    private var trendDirection: String? {
        guard chartData.count >= 2 else { return nil }
        
        let recent = chartData.suffix(3).map { $0.value }
        let older = chartData.prefix(3).map { $0.value }
        
        guard !recent.isEmpty && !older.isEmpty else { return nil }
        
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        
        let percentChange = ((recentAvg - olderAvg) / olderAvg) * 100
        
        if abs(percentChange) < 2 {
            return "→ Stable"
        } else if percentChange > 0 {
            return "↗ Trending up"
        } else {
            return "↘ Trending down"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with title and stats
            HStack {
                Text("Wellness Trends")
                    .font(.headline)
                
                Spacer()
                
                if let avg = averageValue {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatValue(avg))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(selectedMetric.color)
                        
                        if let trend = trendDirection {
                            Text(trend)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Metric selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WellnessMetricType.allCases, id: \.self) { metric in
                        MetricPill(
                            metric: metric,
                            isSelected: selectedMetric == metric,
                            hasData: hasData(for: metric),
                            weightUnit: weightUnit
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMetric = metric
                            }
                        }
                    }
                }
            }
            
            // Period selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WellnessPeriod.allCases, id: \.rawValue) { period in
                        PeriodButton(
                            period: period,
                            isSelected: selectedPeriod == period
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedPeriod = period
                            }
                        }
                    }
                }
            }
            
            // Chart
            if chartData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: selectedMetric.icon)
                        .font(.title)
                        .foregroundColor(.secondary)
                    
                    Text("No \(selectedMetric.rawValue.lowercased()) data for this period")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(chartData, id: \.date) { item in
                        LineMark(
                            x: .value("Date", item.date),
                            y: .value(selectedMetric.rawValue, item.value)
                        )
                        .foregroundStyle(selectedMetric.color)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        
                        PointMark(
                            x: .value("Date", item.date),
                            y: .value(selectedMetric.rawValue, item.value)
                        )
                        .foregroundStyle(selectedMetric.color)
                        .symbolSize(30)
                    }
                    
                    // Average line
                    if let avg = averageValue {
                        RuleMark(y: .value("Average", avg))
                            .foregroundStyle(selectedMetric.color.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .chartXScale(domain: xDomain)
                .chartYScale(domain: yDomain ?? 0...100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(preset: .automatic, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(height: 200)
                
                // Legend
                HStack {
                    Circle()
                        .fill(selectedMetric.color)
                        .frame(width: 8, height: 8)
                    
                    Text(selectedMetric.rawValue)
                        .font(.caption)
                    
                    if let avg = averageValue {
                        Text("•")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Text("Avg: \(formatValue(avg))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func hasData(for metric: WellnessMetricType) -> Bool {
        return metrics.contains { getValue(for: $0) != nil }
    }
    
    private func formatValue(_ value: Double) -> String {
        switch selectedMetric {
        case .weight:
            return String(format: "%.1f %@", value, selectedMetric.unit(weightUnit: weightUnit))
        case .sleep:
            let hours = Int(value)
            let minutes = Int((value - Double(hours)) * 60)
            return "\(hours)h \(minutes)m"
        case .steps:
            return String(format: "%.0f %@", value, selectedMetric.unit(weightUnit: weightUnit))
        case .restingHR:
            return String(format: "%.0f %@", value, selectedMetric.unit(weightUnit: weightUnit))
        case .sleepEfficiency:
            return String(format: "%.0f%%", value)
        case .activeCalories:
            return String(format: "%.0f %@", value, selectedMetric.unit(weightUnit: weightUnit))
        }
    }
}

// MARK: - Metric Pill

struct MetricPill: View {
    let metric: WellnessTrendChart.WellnessMetricType
    let isSelected: Bool
    let hasData: Bool
    let weightUnit: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: metric.icon)
                    .font(.caption)
                
                Text(metric.rawValue)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .white : (hasData ? .primary : .secondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? metric.color : Color(.systemGray6))
            )
            .opacity(hasData ? 1.0 : 0.5)
        }
        .disabled(!hasData)
    }
}

// MARK: - Period Button

struct PeriodButton: View {
    let period: WellnessTrendChart.WellnessPeriod
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(period.name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.blue : Color(.systemGray6))
                )
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleMetrics = (0..<30).map { day in
        DailyWellnessMetrics(
            date: Calendar.current.date(byAdding: .day, value: -day, to: Date())!,
            steps: Int.random(in: 3000...12000),
            activeEnergyBurned: Double.random(in: 400...800),
            restingHeartRate: Int.random(in: 55...65),
            sleepDeep: Double.random(in: 1...2) * 3600,
            sleepREM: Double.random(in: 1.5...2.5) * 3600,
            sleepCore: Double.random(in: 3...4) * 3600,
            bodyMass: 75.0 + Double.random(in: -2...2)
        )
    }
    
    ScrollView {
        VStack(spacing: 20) {
            WellnessTrendChart(
                metrics: sampleMetrics
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
