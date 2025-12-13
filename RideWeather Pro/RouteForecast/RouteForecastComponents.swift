//
//  RouteForecastComponents.swift
//  RideWeather Pro
//
//  Shared helper views for Route Forecast UI
//

import SwiftUI
import CoreLocation

// MARK: - Weather Annotation View
struct ModernWeatherAnnotationView: View {
    let weatherPoint: RouteWeatherPoint
    @EnvironmentObject var viewModel: WeatherViewModel

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: weatherPoint.weather.iconName)
                .font(.title2)
                .symbolRenderingMode(.multicolor)

            VStack(spacing: 2) {
                Text("\(weatherPoint.weather.temp, format: .number.precision(.fractionLength(0)))°")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                // Feels Like
                  Text("Feels like \(Int(weatherPoint.weather.feelsLike))\(viewModel.settings.units.tempSymbol)")
                      .font(.caption2)
                      .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(Double(weatherPoint.weather.windDeg) + 180))
                    
                    Text("\(String(format: "%.0f", weatherPoint.weather.windSpeed)) \(viewModel.settings.units.speedSymbol)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                 }
            }

            Text(weatherPoint.eta, style: .time)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .scaleEffect(1.0)
        .animation(.smooth, value: weatherPoint.weather.temp)
    }
} 


// MARK: - Weather Detail Sheet
struct WeatherDetailSheet: View {
    let weatherPoint: RouteWeatherPoint
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    
                    // Header Weather Icon + Temp
                    VStack(spacing: 12) {
                        Image(systemName: weatherPoint.weather.iconName)
                            .font(.system(size: 90))
                            .symbolRenderingMode(.multicolor)
                        
                        Text("\(Int(weatherPoint.weather.temp))\(viewModel.settings.units.tempSymbol)")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(tempColor(weatherPoint.weather.temp))
                        
                        Text(weatherPoint.weather.description.capitalized)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Quick Info Chips
                    HStack(spacing: 16) {
                        ChipView(
                            icon: "thermometer",
                            label: "Feels Like",
                            value: "\(Int(weatherPoint.weather.feelsLike))\(viewModel.settings.units.tempSymbol)"
                        )
                        
                        ChipView(
                            icon: "wind",
                            label: "Wind",
                            value: "\(Int(weatherPoint.weather.windSpeed)) \(viewModel.settings.units.speedSymbol)",
                            rotation: Double(weatherPoint.weather.windDeg) + 180
                        )
                    }
                    
                    ChipView(
                        icon: "clock",
                        label: "ETA",
                        value: weatherPoint.eta.formatted(date: .omitted, time: .shortened)
                    )
                    .padding(.top, -8)
                    
                    // Spacer
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Weather Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func tempColor(_ temp: Double) -> Color {
        if viewModel.settings.units == .metric {
            return temp < 10 ? .blue : (temp > 28 ? .red : .primary)
        } else {
            return temp < 50 ? .blue : (temp > 82 ? .red : .primary)
        }
    }
}

// MARK: - Chip View
struct ChipView: View {
    let icon: String
    let label: String
    let value: String
    var rotation: Double? = nil
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .rotationEffect(.degrees(rotation ?? 0))
                .foregroundStyle(.blue)
            
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

