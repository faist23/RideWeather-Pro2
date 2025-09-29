import SwiftUI

struct WeatherInsightsCard: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Weather Insights", systemImage: "chart.line.uptrend.xyaxis")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                InsightItem(
                    title: "UV Index",
                    value: "Moderate",
                    icon: "sun.max.fill",
                    color: .yellow
                )
                
                InsightItem(
                    title: "Air Quality",
                    value: "Good",
                    icon: "leaf.fill",
                    color: .green
                )
                
                InsightItem(
                    title: "Visibility",
                    value: "Clear",
                    icon: "eye.fill",
                    color: .blue
                )
                
                InsightItem(
                    title: "Comfort",
                    value: comfortLevel,
                    icon: "heart.fill",
                    color: comfortColor
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
    
    private var comfortLevel: String {
        let tempF = viewModel.settings.units == .metric ? (weather.temp * 9/5) + 32 : weather.temp
        let wind = weather.windSpeed
        
        if tempF < 40 || tempF > 85 || wind > 15 {
            return "Challenging"
        } else if tempF < 55 || tempF > 75 || wind > 10 {
            return "Moderate"
        } else {
            return "Excellent"
        }
    }
    
    private var comfortColor: Color {
        switch comfortLevel {
        case "Excellent": return .green
        case "Moderate": return .yellow
        case "Challenging": return .red
        default: return .gray
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