//
//  AirQualityViews.swift
//  RideWeather Pro
//
//  Air quality UI shared by the route forecast and Live Weather:
//  hazard banner + always-on summary chip.
//

import SwiftUI

/// Full-width warning banner shown when the AQI is Unhealthy (≥ 151) or
/// worse. Category colors at this level (red, EPA purple, EPA maroon) all
/// carry white text.
struct AirQualityWarningBanner: View {
    let aqi: Int
    let category: EPAAirQualityCalculator.Category

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Air Quality: \(aqi) – \(category.displayName)")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(category.riderGuidance)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(category.color, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Capsule chip matching the SunTimesRow style, visible at every AQI level.
struct AirQualityChipRow: View {
    let summary: RouteAirQualitySummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "aqi.medium")
                .font(.caption)
                .foregroundStyle(summary.category.color)

            Text("Air Quality: \(summary.aqi) – \(summary.category.displayName)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Explains the EPA Air Quality Index: what it measures, the rider's current
/// reading in context, and the full six-category legend (color, numeric range,
/// riding guidance). Presented as a sheet from the Live Weather AQI stat.
struct AQIExplanationView: View {
    /// The user's current reading, shown as a highlighted callout. Nil hides
    /// the callout — the legend below is always complete.
    let current: CurrentAirQuality?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Air Quality Index")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("The AQI is the US EPA's 0–500 scale for how polluted the air is. Higher numbers mean more pollution and more risk during outdoor exercise. The color shows the category at a glance.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let current {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RIGHT NOW")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                Text("\(current.aqi)")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundColor(current.category.color)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(current.category.displayName)
                                        .font(.headline)
                                        .foregroundColor(current.category.color)
                                    Text(current.category.riderGuidance)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(current.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Categories")
                            .font(.headline)

                        ForEach(EPAAirQualityCalculator.Category.allCases, id: \.self) { category in
                            AQICategoryRow(category: category)
                        }
                    }

                    Text("Based on the US EPA Air Quality Index. Readings come from official AirNow monitoring stations when available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Air Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One row of the AQI legend: color swatch, category name, numeric range,
/// and riding guidance. File-private helper for `AQIExplanationView`.
private struct AQICategoryRow: View {
    let category: EPAAirQualityCalculator.Category

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(category.color)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(category.rangeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(category.riderGuidance)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
