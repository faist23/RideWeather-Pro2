import SwiftUI

struct HeroWeatherCard: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var animateTemp = false
    
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
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
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
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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