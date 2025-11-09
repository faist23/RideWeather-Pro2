//
//  WeatherInsightsCard.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//


import SwiftUI

struct WeatherInsightsCard: View {
    let weather: DisplayWeatherModel
    let insights: EnhancedWeatherInsights? // Add this
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Weather Insights", systemImage: "chart.line.uptrend.xyaxis")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                if let insights = insights {
                    InsightItem(
                        title: "UV Index",
                        value: "\(String(format: "%.1f", insights.uvIndex)) • \(insights.uvLevel)",
                        icon: "sun.max.fill",
                        color: insights.uvColor
                    )
                    
                    InsightItem(
                        title: "Air Quality",
                        value: insights.airQualityLevel,
                        icon: "leaf.fill",
                        color: insights.airQualityColor
                    )
                    
                    InsightItem(
                        title: "Visibility",
                        value: formatVisibility(insights.visibility),
                        icon: "eye.fill",
                        color: insights.visibilityColor
                    )
                } else {
                    // Fallback to existing hardcoded values while loading
                    InsightItem(
                        title: "UV Index",
                        value: "Loading...",
                        icon: "sun.max.fill",
                        color: .gray
                    )
                    
                    InsightItem(
                        title: "Air Quality",
                        value: "Loading...",
                        icon: "leaf.fill",
                        color: .gray
                    )
                    
                    InsightItem(
                        title: "Visibility",
                        value: "Loading...",
                        icon: "eye.fill",
                        color: .gray
                    )
                }
                
                InsightItem(
                     title: "Comfort",
                     value: enhancedComfortLevel, // Use the new computed property
                     icon: "heart.fill",
                     color: enhancedComfortColor // Use the new computed property
                 )
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
    
    private func formatVisibility(_ meters: Int) -> String {
        let units = viewModel.settings.units
        if units == .metric {
            if meters >= 1000 {
                return "\(meters/1000) km"
            } else {
                return "\(meters) m"
            }
        } else {
            let miles = Double(meters) * 0.000621371
            return String(format: "%.2f mi", miles)
        }
    }
    
    // MARK: - Enhanced Comfort Calculation
    
    // Calculates the raw enhanced comfort score from 0.0 to 1.0.
    private var enhancedComfortScore: Double {
        // Create a temporary HourlyForecast object to access the formula.
        // We can use dummy values for properties not used in the calculation.
        let forecastForCalculation = HourlyForecast(
            time: "",
            date: Date(),
            iconName: "",
            temp: weather.temp,
            feelsLike: weather.feelsLike,
            pop: weather.pop,
            windSpeed: weather.windSpeed,
            windDeg: weather.windDeg,
            humidity: weather.humidity,
            uvIndex: insights?.uvIndex,
            aqi: insights?.airQuality
        )
        
//        return forecastForCalculation.enhancedCyclingComfort(using: viewModel.settings.units, uvIndex: insights?.uvIndex, aqi: insights?.airQuality)
        return forecastForCalculation.enhancedCyclingComfort(using: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature, uvIndex: insights?.uvIndex, aqi: insights?.airQuality)
    }
    
    // Converts the numeric comfort score into a descriptive label.
    private var enhancedComfortLevel: String {
        let score = enhancedComfortScore
        switch score {
        case ..<0.4: return "Challenging"
        case 0.4..<0.6: return "Moderate"
        case 0.6..<0.8: return "Good"
        default: return "Excellent"
        }
    }
    
    // Determines the color based on the numeric comfort score.
    private var enhancedComfortColor: Color {
        let score = enhancedComfortScore
        switch score {
        case ..<0.4: return .red
        case 0.4..<0.6: return .orange
        case 0.6..<0.8: return .yellow
        default: return .green
        }
    }

}
struct InsightItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
