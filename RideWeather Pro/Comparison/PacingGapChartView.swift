//
//  PacingGapChartView.swift
//  RideWeather Pro
//

import SwiftUI
import Charts

/// Scrubbable course-position comparison of a completed ride vs. its pacing
/// plan: elevation profile on top, cumulative time gap below, with a shared
/// cursor showing grade, power vs. target, and time ahead/behind at any point.
struct PacingGapChartView: View {
    let curve: [PacingPlanComparison.PerformancePoint]

    @State private var selectedDistance: Double?

    private let units = UserDefaultsManager.shared.loadSettings().units

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Course Comparison")
                .font(.headline)

            calloutCard

            elevationChart
                .frame(height: 140)

            gapChart
                .frame(height: 90)

            Text("Drag across the course to see where you gained or lost time vs. the plan.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Callout

    private var calloutCard: some View {
        HStack(spacing: 16) {
            if let point = selectedPoint {
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationLabel(point))
                        .font(.subheadline.weight(.semibold))
                    if let grade = grade(at: point) {
                        Text(String(format: "%.1f%% grade", grade))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let actual = point.actualPower, let target = point.targetPower {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(actual))W")
                            .font(.subheadline.weight(.semibold))
                        Text("plan \(Int(target))W")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                gapLabel(point.gapSeconds)
                    .font(.subheadline.weight(.bold))
            } else {
                Text("At the finish:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                gapLabel(curve.last?.gapSeconds ?? 0)
                    .font(.subheadline.weight(.bold))
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private func gapLabel(_ gapSeconds: TimeInterval) -> some View {
        let magnitude = abs(gapSeconds)
        let text: String
        let color: Color
        if magnitude < 1 {
            text = "on plan"
            color = .secondary
        } else if gapSeconds < 0 {
            text = "\(formatGap(magnitude)) ahead"
            color = .green
        } else {
            text = "\(formatGap(magnitude)) behind"
            color = .red
        }
        return Text(text).foregroundColor(color)
    }

    // MARK: - Charts

    private var elevationChart: some View {
        Chart {
            ForEach(curve) { point in
                if let altitude = point.altitude {
                    AreaMark(
                        x: .value("Distance", displayDistance(point.distanceMeters)),
                        yStart: .value("Base", elevationDomain.lowerBound),
                        yEnd: .value("Elevation", displayAltitude(altitude))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.45), .blue.opacity(0.1)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }
            }

            if let selectedDistance {
                RuleMark(x: .value("Position", selectedDistance))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: elevationDomain)
        .chartXSelection(value: $selectedDistance)
        .chartYAxisLabel(units == .metric ? "m" : "ft")
        .chartXAxis(.hidden)
    }

    private var gapChart: some View {
        Chart {
            // Positive advantage (ahead of plan) fills green above the zero
            // line; deficit fills red below. Clamped duals keep the fill
            // continuous through sign changes.
            ForEach(curve) { point in
                AreaMark(
                    x: .value("Distance", displayDistance(point.distanceMeters)),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Ahead", max(0, -point.gapSeconds)),
                    series: .value("Side", "ahead")
                )
                .foregroundStyle(.green.opacity(0.45))
                .interpolationMethod(.monotone)
            }
            ForEach(curve) { point in
                AreaMark(
                    x: .value("Distance", displayDistance(point.distanceMeters)),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Behind", min(0, -point.gapSeconds)),
                    series: .value("Side", "behind")
                )
                .foregroundStyle(.red.opacity(0.45))
                .interpolationMethod(.monotone)
            }

            RuleMark(y: .value("Plan", 0))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 0.5))

            if let selectedDistance {
                RuleMark(x: .value("Position", selectedDistance))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXSelection(value: $selectedDistance)
        .chartYAxisLabel("s vs plan")
        .chartXAxisLabel(units == .metric ? "km" : "mi", alignment: .trailing)
    }

    // MARK: - Selection helpers

    private var selectedPoint: PacingPlanComparison.PerformancePoint? {
        guard let selectedDistance else { return nil }
        return curve.min(by: {
            abs(displayDistance($0.distanceMeters) - selectedDistance) <
            abs(displayDistance($1.distanceMeters) - selectedDistance)
        })
    }

    /// Local grade (percent) around a curve point, from its neighbors.
    private func grade(at point: PacingPlanComparison.PerformancePoint) -> Double? {
        guard let index = curve.firstIndex(where: { $0.id == point.id }) else { return nil }
        let lower = max(0, index - 1)
        let upper = min(curve.count - 1, index + 1)
        guard upper > lower,
              let startAlt = curve[lower].altitude,
              let endAlt = curve[upper].altitude else { return nil }
        let run = curve[upper].distanceMeters - curve[lower].distanceMeters
        guard run > 0 else { return nil }
        return (endAlt - startAlt) / run * 100
    }

    // MARK: - Units & formatting

    private var elevationDomain: ClosedRange<Double> {
        let altitudes = curve.compactMap(\.altitude).map(displayAltitude)
        guard let minAlt = altitudes.min(), let maxAlt = altitudes.max(), maxAlt > minAlt else {
            return 0...100
        }
        let padding = (maxAlt - minAlt) * 0.1
        return (minAlt - padding)...(maxAlt + padding)
    }

    private func displayDistance(_ meters: Double) -> Double {
        units == .metric ? meters / 1000 : meters / 1609.34
    }

    private func displayAltitude(_ meters: Double) -> Double {
        units == .metric ? meters : meters * 3.28084
    }

    private func locationLabel(_ point: PacingPlanComparison.PerformancePoint) -> String {
        let distance = displayDistance(point.distanceMeters)
        return units == .metric ?
            String(format: "Km %.1f", distance) :
            String(format: "Mile %.1f", distance)
    }

    private func formatGap(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ?
            "\(total / 60):\(String(format: "%02d", total % 60))" :
            "\(total)s"
    }
}
