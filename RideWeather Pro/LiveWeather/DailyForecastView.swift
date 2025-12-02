//
// DailyForecastView.swift
// RideWeather Pro
//
// Simple modern card for 7-day forecast
//

import SwiftUI

struct DailyForecastView: View {
    let daily: [DailyForecast]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("7-Day Forecast")
                .font(.title3.weight(.semibold))
                .padding(.horizontal)

            VStack(spacing: 8) {
           ForEach(daily) { day in
                DailyForecastRow(day: day)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

struct DailyForecastRow: View {
    let day: DailyForecast

    var body: some View {
        HStack(spacing: 8) {

            // Day label
            Text(day.dayName)
                .font(.body.weight(.medium))
                .frame(width: 42, alignment: .leading)

            // Weather icon
            Image(systemName: day.iconName)
                .font(.title2)
                .frame(width: 30, alignment: .leading)

            // Temps aligned
            HStack(spacing: 6) {
                Text("\(Int(day.high))°")
                    .font(.body.weight(.semibold))

                Text("\(Int(day.low))°")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .leading)

            if day.pop > 0.05 {
                Text("\(Int(day.pop * 100))%")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.blue)
            }
            
            Spacer()

            // Wind: arrow rotated to the *blowing direction*
            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.body)
                    .rotationEffect(.degrees(blowingDegrees(for: day)))

                Text("\(Int(day.windSpeed))")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Wind Direction (Blowing To)
    private func blowingDegrees(for day: DailyForecast) -> Double {
        // Convert windDeg (where it's coming FROM)
        // into the arrow direction it's blowing TO
        let blowingDeg = Double((day.windDeg + 180) % 360)
        return blowingDeg
    }
}

