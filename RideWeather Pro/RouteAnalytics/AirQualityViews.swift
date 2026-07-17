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
