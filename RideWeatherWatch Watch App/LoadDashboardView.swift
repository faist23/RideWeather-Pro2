/*
 //
//  LoadDashboardView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 1/10/26.
//

import SwiftUI

struct LoadDashboardView: View {
    let summary: TrainingLoadSummary
    
    // Local state to trigger animations when view appears
    @State private var isVisible = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 1. TSB GAUGE (The "Form" Meter)
                Gauge(value: summary.currentTSB, in: -30...30) {
                    Text("Form")
                        .font(.system(size: 10, weight: .medium))
                } currentValueLabel: {
                    Text("\(Int(summary.currentTSB))")
                        .font(.system(.title, design: .rounded).bold())
                        .foregroundStyle(formColor(summary.currentTSB))
                        // ✅ ANIMATION 1: Scroll numbers smoothly
                        .contentTransition(.numericText(value: summary.currentTSB))
                } minimumValueLabel: {
                    Text("-30").font(.system(size: 8))
                } maximumValueLabel: {
                    Text("+30").font(.system(size: 8))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.red, .orange, .gray, .green, .mint]))
                // ✅ ANIMATION 2: Smooth needle movement
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: summary.currentTSB)
                
                // Form Status Text (e.g., "Fresh", "High Fatigue")
                ZStack {
                    // ✅ ANIMATION 3: Subtle background glow for status
                    Capsule()
                        .fill(formColor(summary.currentTSB).opacity(0.2))
                        .frame(height: 24)
                        .blur(radius: 8)
                    
                    Text(summary.formStatus.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(formColor(summary.currentTSB))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        // ✅ ANIMATION 4: Smooth color transition
                        .animation(.easeInOut(duration: 0.5), value: summary.currentTSB)
                }
                .padding(.top, -4)

                Divider()
                
                // 2. KEY METRICS GRID
                Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 8) {
                    GridRow {
                        MetricCell(title: "FITNESS (CTL)", value: "\(Int(summary.currentCTL))", color: .blue)
                        MetricCell(title: "FATIGUE (ATL)", value: "\(Int(summary.currentATL))", color: .pink)
                    }
                    GridRow {
                        MetricCell(title: "RAMP RATE", value: String(format: "%.1f", summary.rampRate), color: rampColor(summary.rampRate))
                        MetricCell(title: "7-DAY TSS", value: "\(Int(summary.weeklyTSS))", color: .secondary)
                    }
                }
                
                Divider()
                
                // 3. COACH'S ADVICE (Recommendation)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "quote.bubble.fill")
                        Text("ADVICE")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    
                    Text(summary.recommendation)
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true) // Allow multiline
                        // ✅ ANIMATION 5: Fade in text changes
                        .transition(.opacity)
                        .id("advice-\(summary.recommendation.hash)") // Forces transition on text change
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .padding()
            // ✅ ANIMATION 6: Overall content fade-in
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    isVisible = true
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    func formColor(_ tsb: Double) -> Color {
        switch tsb {
        case ..<(-20): return .red        // High Fatigue
        case -20..<(-5): return .orange   // Building
        case -5...10: return .gray        // Neutral
        case 10...25: return .green       // Fresh
        default: return .mint             // Very Fresh
        }
    }
    
    func rampColor(_ rate: Double) -> Color {
        if rate > 8 { return .red }       // Risky
        if rate < -5 { return .orange }   // Losing fitness
        return .green                     // Good
    }
}

// Helper View for the Grid
struct MetricCell: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).bold())
                .foregroundStyle(color)
                // ✅ ANIMATION: Metric numbers also scroll
                .contentTransition(.numericText())
        }
    }
}
*/
