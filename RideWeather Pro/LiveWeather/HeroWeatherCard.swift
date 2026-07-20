//
//  HeroWeatherCard.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//


import SwiftUI

struct HeroWeatherCard: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var animateTemp = false
    @State private var showingAQIExplanation = false

    private var showsAQI: Bool {
        viewModel.currentAirQuality.map { $0.category > .good } ?? false
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: weather.iconName)
                    .font(.system(size: 70, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .symbolEffect(.bounce.byLayer, value: animateTemp)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(weather.temp))")
                            .font(.system(size: 64, weight: .thin, design: .rounded))
                            .contentTransition(.numericText())
                        
                        Text(viewModel.settings.units.tempSymbol)
                            .font(.system(size: 28, weight: .light))
                            .offset(y: -6)
                    }
                    .foregroundStyle(.white)
                    
                    Text(weather.description)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .contentTransition(.opacity)
                }
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: showsAQI ? 4 : 3), spacing: 12) {
                WeatherDetailItem(
                    icon: "thermometer",
                    label: "Feels Like",
                    value: "\(Int(weather.feelsLike))°",
                    color: .orange
                )
                
                WeatherDetailItem(
                    icon: "wind",
                    label: "Wind",
                    value: "\(Int(weather.windSpeed)) \(viewModel.settings.units.speedSymbol)",
                    color: .cyan,
                    rotation: Double(weather.windDeg)
                )
                
                if weather.humidity > 0 {
                    WeatherDetailItem(
                        icon: "humidity.fill",
                        label: "Humidity",
                        value: "\(weather.humidity)%",
                        color: .blue
                    )
                }

                if showsAQI, let airQuality = viewModel.currentAirQuality {
                    WeatherDetailItem(
                        icon: "aqi.medium",
                        label: "AQI",
                        value: "\(airQuality.aqi)",
                        color: airQuality.category.color
                    )
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showingAQIExplanation = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows what the Air Quality Index means")
                }
            }

            if let heatIndex = HeatIndexCalculator.reading(
                temperature: weather.temp,
                humidity: weather.humidity,
                units: viewModel.settings.units
            ) {
                HeatIndexBanner(reading: heatIndex)
            }
        }
        .sheet(isPresented: $showingAQIExplanation) {
            AQIExplanationView(current: viewModel.currentAirQuality)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onAppear {
            animateTemp = true
        }
        .onChange(of: weather.temp) { _, _ in
            animateTemp.toggle()
        }
    }
}

/// NWS heat index with its advisory category, shown alongside (not instead of)
/// the provider's feels-like temperature whenever the heat index reaches 80 °F.
struct HeatIndexBanner: View {
    let reading: HeatIndexCalculator.Reading

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "thermometer.sun.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(reading.category.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Heat Index \(Int(reading.value.rounded()))°")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)

                    Text(reading.category.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(reading.category.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(reading.category.color.opacity(0.2), in: Capsule())
                }

                Text(reading.category.ridingAdvice)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(reading.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(reading.category.color.opacity(0.35), lineWidth: 1)
        )
    }
}

struct WeatherDetailItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    var rotation: Double? = nil
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .rotationEffect(.degrees(rotation ?? 0))
                .animation(.smooth, value: rotation)
            
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 8)
    }
}
