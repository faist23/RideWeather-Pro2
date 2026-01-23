//
//  FormView.swift
//  RideWeatherWatch Watch App
//
//  Fixed: Explicit blue gradient background
//

import SwiftUI

struct FormView: View {
    let summary: TrainingLoadSummary
    let weeklyProgress: WeeklyProgress
    
    var body: some View {
        ZStack {
            // Explicit blue gradient background
            LinearGradient(
                colors: [Color(red: 0.35, green: 0, blue: 0.6), Color(red: 0.1, green: 0, blue: 0.2), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 10) {
                    
                    // --- PRIMARY DASHBOARD ---
                    HStack(alignment: .center, spacing: 8) {
                        
                        // LEFT: The TSB (Form)
                        VStack(spacing: -2) {
                            Text(summary.currentTSB > 0 ? "+\(Int(summary.currentTSB))" : "\(Int(summary.currentTSB))")
                                .font(.system(size: 52, weight: .black, design: .rounded))
                                .foregroundStyle(formColor(summary.currentTSB))
                            
                            Text("FORM (TSB)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        // RIGHT: Fitness & Fatigue
                        VStack(alignment: .leading, spacing: 8) {
                            // Fitness
                            CompactMetricRow(
                                icon: "arrow.up.forward",
                                value: "\(Int(summary.currentCTL))",
                                unit: "Fitness",
                                color: .blue
                            )
                            
                            // Fatigue
                            CompactMetricRow(
                                icon: "arrow.down.forward",
                                value: "\(Int(summary.currentATL))",
                                unit: "Fatigue",
                                color: .pink
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 4)
                    
                    // --- WEEKLY LOAD BAR ---
                    VStack(spacing: 4) {
                        HStack {
                            Text("WEEKLY LOAD")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(summary.weeklyTSS)) / \(weeklyProgress.weeklyTarget)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.gray.opacity(0.3))
                                Capsule()
                                    .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: min(geo.size.width, geo.size.width * (summary.weeklyTSS / Double(weeklyProgress.weeklyTarget))))
                            }
                        }
                        .frame(height: 6)
                    }
                    
                    // --- RAMP RATE ---
                    HStack {
                        Image(systemName: rampRateIcon(summary.rampRate))
                            .foregroundStyle(rampRateColor(summary.rampRate))
                        
                        Text("Ramp Rate: \(String(format: "%+.1f", summary.rampRate))")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(rampRateColor(summary.rampRate).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    WatchSyncIndicator()
                        .scaleEffect(0.7)
                        .opacity(0.5)
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helpers
    
    func formColor(_ tsb: Double) -> Color {
        if tsb > 10 { return .green }       // Fresh
        if tsb < -20 { return .red }        // Overload
        if tsb < -5 { return .orange }      // Optimal Training
        return .gray                        // Neutral
    }
    
    func rampRateColor(_ rate: Double) -> Color {
        if rate > 8 { return .red }
        if rate < -5 { return .orange }
        return .green
    }
    
    func rampRateIcon(_ rate: Double) -> String {
        if rate > 8 { return "exclamationmark.triangle.fill" }
        return "chart.xyaxis.line"
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

