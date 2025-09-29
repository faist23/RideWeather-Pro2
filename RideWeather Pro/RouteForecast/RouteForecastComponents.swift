//
//  RouteForecastComponents.swift
//  RideWeather Pro
//
//  Shared helper views for Route Forecast UI
//

import SwiftUI
import CoreLocation

// MARK: - Modern Progress View
struct ModernProgressView: View {
    let progress: Double
    let label: String
    
    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 120)
                .tint(.blue)
            
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}

// MARK: - Estimated Time Chip
struct EstimatedTimeChip: View {
    let timeString: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
            
            Text("Estimated: \(timeString)")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}

// MARK: - Modern Loading View
struct ModernLoadingView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            
            Text("Calculating Weather Forecast...")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Import Button
struct ImportButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.down.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 50, height: 50)
        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.blue)
        .shadow(radius: 2)
    }
}

// MARK: - Weather Annotation View
/*struct ModernWeatherAnnotationView: View {
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

                // ✅ Add Feels Like back
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
} */

struct ModernWeatherAnnotationView: View {
    let weatherPoint: RouteWeatherPoint
    @EnvironmentObject var viewModel: WeatherViewModel
    
    // Dynamic color for temp
    private var tempColor: Color {
        let t = weatherPoint.weather.temp
        if t <= 40 { return .blue }
        else if t <= 70 { return .teal }
        else if t <= 85 { return .orange }
        else { return .red }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Weather icon
            Image(systemName: weatherPoint.weather.iconName)
                .font(.title2)
                .symbolRenderingMode(.multicolor)
            
            // Temperature + feels like
            VStack(spacing: 2) {
                Text("\(Int(weatherPoint.weather.temp))°")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tempColor)
                
                Text("Feels \(Int(weatherPoint.weather.feelsLike))°")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Wind badge
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.15))
                        .frame(width: 22, height: 22)
                    Image(systemName: "arrow.up")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                        .rotationEffect(.degrees(Double(weatherPoint.weather.windDeg)))
                }
                
                Text("\(String(format: "%.0f", weatherPoint.weather.windSpeed)) \(viewModel.settings.units.speedSymbol)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // ETA chip
            Text(weatherPoint.eta, style: .time)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .scaleEffect(1.0)
        .animation(.smooth, value: weatherPoint.weather.temp)
    }
}


// MARK: - Weather Detail Sheet
/*struct WeatherDetailSheet: View {
    let weatherPoint: RouteWeatherPoint
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: weatherPoint.weather.iconName)
                        .font(.system(size: 80))
                        .symbolRenderingMode(.multicolor)
                    
                    VStack(spacing: 4) {
                        Text("\(weatherPoint.weather.temp, format: .number.precision(.fractionLength(0)))\(viewModel.settings.units.tempSymbol)")
                            .font(.largeTitle.weight(.bold))
                        
                        Text(weatherPoint.weather.description)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    WeatherDetailCard(
                        title: "Feels Like",
                        value: "\(Int(weatherPoint.weather.feelsLike))\(viewModel.settings.units.tempSymbol)",
                        icon: "thermometer"
                    )
                    
                    WeatherDetailCard(
                        title: "Wind Speed",
                        value: "\(Int(weatherPoint.weather.windSpeed)) \(viewModel.settings.units.speedSymbol)",
                        icon: "wind"
                    )
                    
                    WeatherDetailCard(
                        title: "Wind Direction",
                        value: weatherPoint.weather.windDirection,
                        icon: "arrow.up",
                        rotation: Double(weatherPoint.weather.windDeg)
                    )
                    
                    WeatherDetailCard(
                        title: "ETA",
                        value: weatherPoint.eta.formatted(date: .omitted, time: .shortened),
                        icon: "clock"
                    )
                }
                
                Spacer()
            }
            .padding(24)
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
}
*/

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


// MARK: - Weather Detail Card
struct WeatherDetailCard: View {
    let title: String
    let value: String
    let icon: String
    let rotation: Double?
    
    init(title: String, value: String, icon: String, rotation: Double? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.rotation = rotation
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .rotationEffect(.degrees(rotation ?? 0))
            
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
