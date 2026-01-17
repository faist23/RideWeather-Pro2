//
//  FormView.swift
//  RideWeatherWatch Watch App
//

import SwiftUI

struct FormView: View {
    let summary: TrainingLoadSummary
    let weeklyProgress: WeeklyProgress
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                WatchSyncIndicator()
                    .padding(.bottom, 1)

                // TSB GAUGE
                VStack(spacing: 6) {
                    Gauge(value: summary.currentTSB, in: -30...30) {
                        Text("Form")
                            .font(.system(size: 9))
                    } currentValueLabel: {
                        Text(summary.currentTSB > 0 ? "+\(Int(summary.currentTSB))" : "\(Int(summary.currentTSB))")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(formColor(summary.currentTSB))
                    } minimumValueLabel: {
                        Text("-30").font(.system(size: 8))
                    } maximumValueLabel: {
                        Text("+30").font(.system(size: 8))
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(Gradient(colors: [.red, .orange, .gray, .green, .mint]))
                    
                    Text(summary.formStatus.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(formColor(summary.currentTSB))
                }
                
                Divider()
                
                // FITNESS & FATIGUE with Trends
                HStack(spacing: 12) {
                    MetricWithTrend(
                        title: "FITNESS",
                        value: Int(summary.currentCTL),
                        trend: weeklyProgress.ctlTrend,
                        color: .blue
                    )
                    
                    MetricWithTrend(
                        title: "FATIGUE",
                        value: Int(summary.currentATL),
                        trend: weeklyProgress.atlTrend,
                        color: .pink
                    )
                }
                
                // WEEKLY TSS PROGRESS
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("WEEK TSS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(summary.weeklyTSS))/\(weeklyProgress.weeklyTarget)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .green],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: min(geometry.size.width, geometry.size.width * CGFloat(summary.weeklyTSS / Double(weeklyProgress.weeklyTarget))),
                                    height: 6
                                )
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.vertical, 4)
                
                // RAMP RATE WARNING
                HStack {
                    Image(systemName: rampRateIcon(summary.rampRate))
                        .font(.system(size: 10))
                        .foregroundStyle(rampRateColor(summary.rampRate))
                    
                    Text("Ramp Rate")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(String(format: "%+.1f TSS/wk", summary.rampRate))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(rampRateColor(summary.rampRate))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(rampRateColor(summary.rampRate).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding()
        }
        .containerBackground(.blue.gradient, for: .tabView)
    }
    
    // MARK: - Helper Functions
    
    func formColor(_ tsb: Double) -> Color {
        switch tsb {
        case ..<(-20): return .red
        case -20..<(-5): return .orange
        case -5...10: return .gray
        case 10...25: return .green
        default: return .mint
        }
    }
    
    func rampRateColor(_ rate: Double) -> Color {
        if rate > 8 { return .red }
        if rate < -5 { return .orange }
        return .green
    }
    
    func rampRateIcon(_ rate: Double) -> String {
        if rate > 8 { return "exclamationmark.triangle.fill" }
        if rate < -5 { return "arrow.down.circle.fill" }
        return "checkmark.circle.fill"
    }
}

// MARK: - Metric With Trend

struct MetricWithTrend: View {
    let title: String
    let value: Int
    let trend: TrendDirection
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Image(systemName: trend.icon)
                    .font(.system(size: 8))
                    .foregroundStyle(trend.color)
            }
            
            Text("\(value)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Supporting Models

struct WeeklyProgress {
    let weeklyTarget: Int
    let ctlTrend: TrendDirection
    let atlTrend: TrendDirection
    
    static func calculate(current: TrainingLoadSummary, history: [DailyTrainingLoad]) -> WeeklyProgress {
        // Get CTL from 7 days ago
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let oldCTL = history
            .first(where: { Calendar.current.isDate($0.date, inSameDayAs: sevenDaysAgo) })?
            .ctl ?? current.currentCTL
        
        let ctlChange = current.currentCTL - oldCTL
        let ctlTrend: TrendDirection = ctlChange > 1 ? .up : (ctlChange < -1 ? .down : .stable)
        
        // Same for ATL
        let oldATL = history
            .first(where: { Calendar.current.isDate($0.date, inSameDayAs: sevenDaysAgo) })?
            .atl ?? current.currentATL
        
        let atlChange = current.currentATL - oldATL
        let atlTrend: TrendDirection = atlChange > 1 ? .up : (atlChange < -1 ? .down : .stable)
        
        return WeeklyProgress(
            weeklyTarget: 350, // Could make this dynamic based on CTL
            ctlTrend: ctlTrend,
            atlTrend: atlTrend
        )
    }
}

enum TrendDirection {
    case up, down, stable
    
    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "minus"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .stable: return .gray
        }
    }
}
