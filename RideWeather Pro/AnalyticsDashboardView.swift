import SwiftUI
import Charts

// MARK: - Analytics Dashboard View

struct AnalyticsDashboardView: View {
    let hourlyData: [HourlyForecast]
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedMetric: AnalyticMetric = .comfort
    @State private var timeRange: TimeRange = .twentyFour
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case twelve = "12h"
        case twentyFour = "24h"
        case fortyEight = "48h"
        
        var id: String { rawValue }
        var hours: Int {
            switch self {
            case .twelve: return 12
            case .twentyFour: return 24
            case .fortyEight: return 48
            }
        }
        var displayName: String {
            switch self {
            case .twelve: return "Next 12 Hours"
            case .twentyFour: return "Next 24 Hours" 
            case .fortyEight: return "Next 48 Hours"
            }
        }
    }
    
    enum AnalyticMetric: String, CaseIterable, Identifiable {
        case comfort = "Cycling Comfort"
        case temperature = "Temperature"
        case wind = "Wind Analysis"
        case precipitation = "Precipitation"
        case optimal = "Optimal Times"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .comfort: return "heart.fill"
            case .temperature: return "thermometer"
            case .wind: return "wind"
            case .precipitation: return "cloud.rain"
            case .optimal: return "star.fill"
            }
        }
        var color: Color {
            switch self {
            case .comfort: return .green
            case .temperature: return .orange
            case .wind: return .cyan
            case .precipitation: return .blue
            case .optimal: return .yellow
            }
        }
    }
    
    var filteredData: [HourlyForecast] {
        Array(hourlyData.prefix(timeRange.hours))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header stats
                    quickStatsGrid
                    
                    // Time range selector
                    timeRangeSelector
                    
                    // Metric selector
                    metricSelector
                    
                    // Main chart
                    mainChart
                    
                    // Detailed analysis
                    detailedAnalysis
                    
                    // Smart recommendations
                    smartRecommendations
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("Weather Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    // MARK: - Quick Stats Grid
    
    private var quickStatsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
            QuickStatCard(
                icon: "star.fill",
                title: "Best Hour",
                value: bestHour?.time ?? "N/A",
                subtitle: "\(Int(bestHour?.cyclingComfort ?? 0))% comfort",
                color: .yellow
            )
            
            QuickStatCard(
                icon: "heart.fill",
                title: "Avg Comfort",
                value: "\(averageComfort)%",
                subtitle: "Overall score",
                color: .green
            )
            
            QuickStatCard(
                icon: "cloud.rain.fill",
                title: "Max Rain",
                value: "\(Int(maxRainChance * 100))%",
                subtitle: "Peak chance",
                color: .blue
            )
            
            QuickStatCard(
                icon: "wind",
                title: "Max Wind",
                value: "\(Int(maxWindSpeed))mph",
                subtitle: "Peak speed",
                color: .cyan
            )
        }
    }
    
    // MARK: - Time Range Selector
    
    private var timeRangeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Time Range", systemImage: "clock.arrow.circlepath")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            
            Picker("Time Range", selection: $timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Main Chart
    
    private var mainChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(selectedMetric.rawValue) Trends", systemImage: selectedMetric.icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Chart legend
                HStack(spacing: 8) {
                    Circle()
                        .fill(selectedMetric.color)
                        .frame(width: 8, height: 8)
                    Text(selectedMetric.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            
            // Chart content
            if #available(iOS 16.0, *) {
                Chart(filteredData, id: \.id) { hour in
                    switch selectedMetric {
                    case .comfort:
                        AreaMark(
                            x: .value("Time", hour.time),
                            y: .value("Comfort", hour.cyclingComfort * 100)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                    case .temperature:
                        LineMark(
                            x: .value("Time", hour.time),
                            y: .value("Temperature", hour.temp)
                        )
                        .foregroundStyle(selectedMetric.color)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        
                        PointMark(
                            x: .value("Time", hour.time),
                            y: .value("Temperature", hour.temp)
                        )
                        .foregroundStyle(selectedMetric.color)
                        
                        LineMark(
                            x: .value("Time", hour.time),
                            y: .value("Feels Like", hour.feelsLike)
                        )
                        .foregroundStyle(selectedMetric.color.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                        
                    case .wind:
                        AreaMark(
                            x: .value("Time", hour.time),
                            y: .value("Wind Speed", hour.windSpeed)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                    case .precipitation:
                        BarMark(
                            x: .value("Time", hour.time),
                            y: .value("Rain Chance", hour.pop * 100)
                        )
                        .foregroundStyle(selectedMetric.color)
                        .cornerRadius(2)
                        
                    case .optimal:
                        AreaMark(
                            x: .value("Time", hour.time),
                            y: .value("Optimal Score", hour.cyclingComfort * 100)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .frame(height: 250)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: timeRange.hours / 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            } else {
                // Fallback for iOS 15
                SimpleChartView(
                    data: filteredData,
                    metric: selectedMetric,
                    color: selectedMetric.color
                )
                .frame(height: 250)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Detailed Analysis
    
    private var detailedAnalysis: some View {
        HStack(alignment: .top, spacing: 16) {
            // Hourly breakdown
            VStack(alignment: .leading, spacing: 12) {
                Label("Hourly Details", systemImage: "clock.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(filteredData.enumerated().filter { $0.offset % 2 == 0 }), id: \.element.id) { index, hour in
                            HourlyDetailRow(hour: hour)
                                .environmentObject(viewModel)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            
            // Wind analysis
            VStack(alignment: .leading, spacing: 12) {
                Label("Wind Analysis", systemImage: "wind")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                WindAnalysisCard(hourlyData: filteredData)
                    .environmentObject(viewModel)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Smart Recommendations
    
    private var smartRecommendations: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Smart Cycling Recommendations", systemImage: "lightbulb.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 1), spacing: 12) {
                RecommendationCard(
                    icon: "star.fill",
                    title: "Optimal Window",
                    description: optimalWindowRecommendation,
                    color: .green
                )
                
                RecommendationCard(
                    icon: "map.fill",
                    title: "Route Strategy", 
                    description: routeStrategyRecommendation,
                    color: .blue
                )
                
                RecommendationCard(
                    icon: "bag.fill",
                    title: "Gear Advice",
                    description: gearAdviceRecommendation,
                    color: .orange
                )
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Computed Properties
    
    private var bestHour: HourlyForecast? {
        filteredData.max(by: { $0.cyclingComfort < $1.cyclingComfort })
    }
    
    private var averageComfort: Int {
        let total = filteredData.reduce(0) { $0 + $1.cyclingComfort }
        return Int((total / Double(filteredData.count)) * 100)
    }
    
    private var maxRainChance: Double {
        filteredData.map { $0.pop }.max() ?? 0
    }
    
    private var maxWindSpeed: Double {
        filteredData.map { $0.windSpeed }.max() ?? 0
    }
    
    private var optimalWindowRecommendation: String {
        guard let bestHour = bestHour else {
            return "Unable to determine optimal cycling window"
        }
        return "Best cycling from \(bestHour.time) with \(Int(bestHour.cyclingComfort * 100))% comfort score. Temperature will be \(Int(bestHour.temp))°F with \(Int(bestHour.windSpeed))mph winds."
    }
    
    private var routeStrategyRecommendation: String {
        if maxWindSpeed > 15 {
            return "High winds expected (\(Int(maxWindSpeed))mph). Choose sheltered routes or plan shorter rides."
        } else {
            return "Moderate winds. Any route should be comfortable for your planned distance."
        }
    }
    
    private var gearAdviceRecommendation: String {
        let minTemp = filteredData.map { $0.temp }.min() ?? 70
        let maxTemp = filteredData.map { $0.temp }.max() ?? 70
        
        if minTemp < 50 || maxTemp > 85 {
            return "Temperature extremes expected (\(Int(minTemp))°-\(Int(maxTemp))°F). Layer appropriately and bring extra fluids."
        } else {
            return "Standard cycling gear should be comfortable throughout your ride."
        }
    }
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [.blue.opacity(0.8), .indigo.opacity(0.6), .purple.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Supporting Views

struct QuickStatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct HourlyDetailRow: View {
    let hour: HourlyForecast
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            Text(hour.time)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, alignment: .leading)
            
            Image(systemName: hour.iconName)
                .font(.caption)
                .symbolRenderingMode(.multicolor)
                .frame(width: 20)
            
            Text("\(Int(hour.temp))°")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, alignment: .trailing)
            
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                    .rotationEffect(.degrees(Double(hour.windDeg) + 180))
                Text("\(Int(hour.windSpeed))")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.cyan)
            .frame(width: 40)
            
            Spacer()
            
            Text("\(Int(hour.cyclingComfort * 100))%")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(hour.comfortColor.opacity(0.3), in: Capsule())
                .foregroundStyle(hour.comfortColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WindAnalysisCard: View {
    let hourlyData: [HourlyForecast]
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var avgWindSpeed: Int {
        Int(hourlyData.reduce(0) { $0 + $1.windSpeed } / Double(hourlyData.count))
    }
    
    var primaryDirection: String {
        // Simplified wind direction calculation
        let avgDirection = hourlyData.reduce(0) { $0 + Double($1.windDeg) } / Double(hourlyData.count)
        return getWindDirection(degrees: avgDirection)
    }
    
    var windDistribution: [(range: String, count: Int, color: Color)] {
        [
            (range: "0-10 mph", count: hourlyData.filter { $0.windSpeed <= 10 }.count, color: .green),
            (range: "11-20 mph", count: hourlyData.filter { $0.windSpeed > 10 && $0.windSpeed <= 20 }.count, color: .yellow),
            (range: "20+ mph", count: hourlyData.filter { $0.windSpeed > 20 }.count, color: .red)
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Average Speed")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(avgWindSpeed) mph")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Primary Direction")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(primaryDirection)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Speed Distribution")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                
                ForEach(windDistribution, id: \.range) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        
                        Text(item.range)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("\(item.count)h")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
    
    private func getWindDirection(degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return directions[Int((degrees + 11.25) / 22.5) % 16]
    }
}

struct RecommendationCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(16)
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Simple Chart View for iOS 15 fallback

struct SimpleChartView: View {
    let data: [HourlyForecast]
    let metric: AnalyticsDashboardView.AnalyticMetric
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid lines
                ForEach(0..<5, id: \.self) { index in
                    Path { path in
                        let y = geometry.size.height * CGFloat(index) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(.white.opacity(0.1), lineWidth: 1)
                }
                
                // Chart line
                Path { path in
                    let values = getChartValues()
                    guard !values.isEmpty else { return }
                    
                    let maxValue = values.max()!
                    let minValue = values.min()!
                    let range = maxValue - minValue
                    
                    for (index, value) in values.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                        let y = geometry.size.height * (1 - normalizedValue)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 3)
                
                // Data points
                ForEach(Array(getChartValues().enumerated()), id: \.offset) { index, value in
                    let values = getChartValues()
                    let maxValue = values.max()!
                    let minValue = values.min()!
                    let range = maxValue - minValue
                    
                    let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                    let y = geometry.size.height * (1 - normalizedValue)
                    
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
        }
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func getChartValues() -> [Double] {
        switch metric {
        case .comfort, .optimal:
            return data.map { $0.cyclingComfort * 100 }
        case .temperature:
            return data.map { $0.temp }
        case .wind:
            return data.map { $0.windSpeed }
        case .precipitation:
            return data.map { $0.pop * 100 }
        }
    }
}

// MARK: - Extension for HourlyForecast

extension HourlyForecast {
    var cyclingComfort: Double {
        let tempF = temp * 9/5 + 32 // Convert to Fahrenheit for calculation
        
        var tempScore: Double = 1.0
        if tempF < 50 || tempF > 80 {
            tempScore = 0.3
        } else if tempF < 60 || tempF > 75 {
            tempScore = 0.7
        }
        
        var windScore: Double = 1.0
        if windSpeed > 15 {
            windScore = 0.3
        } else if windSpeed > 10 {
            windScore = 0.7
        }
        
        let rainScore = 1.0 - pop
        
        return (tempScore + windScore + rainScore) / 3.0
    }
    
    var comfortColor: Color {
        let comfort = cyclingComfort
        if comfort > 0.8 {
            return .green
        } else if comfort > 0.6 {
            return .yellow
        } else if comfort > 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}ectangle(cornerRadius: 20))
    }
    
    // MARK: - Metric Selector
    
    private var metricSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Analysis Type", systemImage: "chart.xyaxis.line")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AnalyticMetric.allCases) { metric in
                        Button {
                            withAnimation(.bouncy) {
                                selectedMetric = metric
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: metric.icon)
                                    .symbolRenderingMode(.hierarchical)
                                Text(metric.rawValue)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                selectedMetric == metric ? 
                                    metric.color.opacity(0.3) : 
                                    .white.opacity(0.1),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedMetric == metric ? 
                                            metric.color : 
                                            .white.opacity(0.3),
                                        lineWidth: 2
                                    )
                            )
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedR