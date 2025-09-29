//
//  ModernHourlyForecastView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//


import SwiftUI

struct ModernHourlyForecastView: View {
    let hourlyData: [HourlyForecast]
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("6-Hour Forecast", systemImage: "clock.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(hourlyData.enumerated()), id: \.element.id) { index, hour in
                        HourlyForecastCard(hour: hour, index: index)
                            .environmentObject(viewModel)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

struct HourlyForecastCard: View {
    let hour: HourlyForecast
    let index: Int
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 10) {
            Text(hour.time)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
            
            Image(systemName: hour.iconName)
                .font(.title2)
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.bounce, value: appeared)
            
            VStack(spacing: 4) {
                Text("\(Int(hour.temp))°")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                
                Text("Feels \(Int(hour.feelsLike))°")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                    .rotationEffect(.degrees(Double(hour.windDeg) + 180))
                
                Text("\(Int(hour.windSpeed))")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.cyan)
            
            if hour.pop > 0.1 {
                VStack(spacing: 2) {
                    Image(systemName: "cloud.rain.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    
                    Text("\(Int(hour.pop * 100))%")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(minWidth: 80)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1.0 : 0.8)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.bouncy.delay(Double(index) * 0.1)) {
                appeared = true
            }
        }
    }
}