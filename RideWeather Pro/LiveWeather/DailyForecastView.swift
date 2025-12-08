//
// DailyForecastView.swift
// RideWeather Pro
//
// Simple modern card for 7-day forecast
//

import SwiftUI

struct DailyForecastView: View {
    let daily: [DailyForecast]

    // Track which day is expanded
    @State private var selectedDayId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("7-Day Forecast")
                .font(.title3.weight(.semibold))
                .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(daily) { day in
                    DailyForecastRow(
                        day: day,
                        isExpanded: selectedDayId == day.id
                    )
                    .onTapGesture {
                        // Fluid spring animation for the toggle
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            if selectedDayId == day.id {
                                selectedDayId = nil
                            } else {
                                selectedDayId = day.id
                            }
                        }
                    }
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
    let isExpanded: Bool // Pass this in

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header (Always Visible)
            HStack(spacing: 8) {
                // Day label
                Text(day.dayName)
                    .font(.body.weight(.medium))
                    .frame(width: 42, alignment: .leading)

                // Weather icon
                Image(systemName: day.iconName)
                    .font(.title2)
                    .symbolRenderingMode(.multicolor) // Ensure multicolor for better icons
                    .frame(width: 30, alignment: .leading)

                // Temps aligned
                HStack(spacing: 6) {
                    Text("\(Int(day.high))°")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Text("\(Int(day.low))°")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))

                }
                .frame(width: 70, alignment: .leading)

                if day.pop > 0.05 {
                    Text("\(Int(day.pop * 100))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                        .padding(4)
                        .background(.blue.opacity(0.1), in: Capsule())
                }
                
                Spacer()

                // Wind
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .rotationEffect(.degrees(blowingDegrees(for: day)))

                    Text("\(Int(day.windSpeed))")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                // Chevron to indicate expandability
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding() // Apply padding to the header content
            .contentShape(Rectangle()) // Tappable area

            // MARK: - Expanded Summary
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    Text(day.summary)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                .padding([.horizontal, .bottom])
            }
        }
        .background(
            // Highlight the selected row slightly
            RoundedRectangle(cornerRadius: 14)
                .fill(isExpanded ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func blowingDegrees(for day: DailyForecast) -> Double {
        Double((day.windDeg + 180) % 360)
    }
}
