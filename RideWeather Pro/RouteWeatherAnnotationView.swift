import SwiftUI
import CoreLocation

struct RouteWeatherAnnotationView: View {
    let weatherPoint: RouteWeatherPoint
    @EnvironmentObject var viewModel: WeatherViewModel

    var body: some View {
        VStack(spacing: 6) {
            // Main weather icon
            Image(systemName: weatherPoint.weather.iconName)
                .font(.title2)
                .symbolRenderingMode(.multicolor)

            VStack(spacing: 2) {
                // Temperature
                Text("\(weatherPoint.weather.temp, format: .number.precision(.fractionLength(0)))°")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                // Wind arrow & speed
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        // Wind arrows show blowing direction (add 180° to "from" direction)
                        .rotationEffect(.degrees(Double(weatherPoint.weather.windDeg) + 180))

                    Text("\(String(format: "%.0f", weatherPoint.weather.windSpeed))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // ETA
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
