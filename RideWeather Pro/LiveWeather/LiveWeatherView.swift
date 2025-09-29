
//
// LiveWeatherView.swift
// RideWeather Pro
//
// Modern iOS 26+ interface with enhanced animations and interactions
//

import SwiftUI
import CoreLocation

struct LiveWeatherView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isShowingSettings = false
    @State private var scrollOffset: CGFloat = 0
    @State private var refreshTrigger = false
    
    // Enhanced background with dynamic colors
    var backgroundGradient: LinearGradient {
        let hour = Calendar.current.component(.hour, from: viewModel.rideDate)
        let isDayTime = hour >= 6 && hour < 19
        let temp = viewModel.displayWeather?.temp ?? 20
        
        // Temperature-based gradient selection
        if isDayTime {
            if temp > 25 { // Hot day
                return LinearGradient(
                    colors: [.orange.opacity(0.8), .red.opacity(0.6), .yellow.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if temp < 10 { // Cold day
                return LinearGradient(
                    colors: [.blue.opacity(0.8), .cyan.opacity(0.6), .mint.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else { // Pleasant day
                return LinearGradient(
                    colors: [.blue.opacity(0.7), .cyan.opacity(0.5), .green.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            return LinearGradient(
                colors: [.black, .indigo.opacity(0.8), .purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dynamic background with mesh gradient effect
                backgroundGradient
                    .ignoresSafeArea()
                    .animation(.smooth(duration: 1.0), value: viewModel.displayWeather?.temp)
                
                // Subtle background pattern
                backgroundDecoration
                
                // Main content
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            // Header with parallax effect
                            headerView
                                .offset(y: scrollOffset * 0.3)
                                .opacity(1 - (scrollOffset / 200).clamped(to: 0...0.5))
                            
                            // Main weather content
                            if viewModel.isLoading && viewModel.displayWeather == nil {
                                ModernShimmerView()
                                    .transition(.opacity.combined(with: .scale)) // CORRECTED
                            } else if let weatherData = viewModel.displayWeather {
                                VStack(spacing: 28) {
                                    // Hero weather card
                                    HeroWeatherCard(weather: weatherData)
                                        .environmentObject(viewModel)
                                        .scaleEffect(1 - (scrollOffset / 1000).clamped(to: 0...0.1))
                                    
                                    // Enhanced hourly forecast
                                    ModernHourlyForecastView(hourlyData: viewModel.hourlyForecast)
                                        .environmentObject(viewModel)
                                    
                                    // Smart recommendations with enhanced UI
                                    EnhancedBikeRecommendationView(weather: weatherData)
                                        .environmentObject(viewModel)
                                    
                                    // Weather insights card
                                    WeatherInsightsCard(weather: weatherData)
                                        .environmentObject(viewModel)
                                }
                                // CORRECTED: Replaced non-standard asymmetric transition
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            } else if let errorMessage = viewModel.errorMessage {
                                ModernErrorView(message: errorMessage) {
                                    Task { await viewModel.refreshWeather() }
                                }
                                .transition(.opacity.combined(with: .scale)) // CORRECTED
                            }
                            
                            // Bottom spacing for safe area
                            Color.clear.frame(height: 20)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .background(
                            GeometryReader { scrollGeometry in
                                Color.clear
                                    .preference(key: ScrollOffsetPreferenceKey.self,
                                              value: scrollGeometry.frame(in: .named("scroll")).minY)
                            }
                        )
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        withAnimation(.smooth) {
                            scrollOffset = -value
                        }
                    }
                }
                .refreshable {
                    withAnimation(.bouncy) {
                        refreshTrigger.toggle()
                    }
                    await viewModel.refreshWeather()
                }
            }
            .navigationTitle("Cycling Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Refresh button with animation
                    Button {
                        withAnimation(.bouncy) {
                            refreshTrigger.toggle()
                        }
                        Task { await viewModel.refreshWeather() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, value: refreshTrigger)
                    }
                    .disabled(viewModel.isLoading)
                    
                    // Settings button
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                ModernSettingsView(currentRideDate: viewModel.rideDate)
                    .environmentObject(viewModel)
            }
        }
    }
    
    
    // MARK: - Background Decoration
        
    private var backgroundDecoration: some View {
        AlternativeBackgroundDecoration()
    }
    
    // MARK: - Animated Floating Circle

    struct AnimatedFloatingCircle: View {
        let index: Int
        let refreshTrigger: Bool
        
        // Static properties that won't change during animation
        private let size: CGFloat
        private let baseOffset: CGPoint
        private let animationDuration: Double
        private let animationDelay: Double
        
        @State private var animationOffset = CGSize.zero
        @State private var isAnimating = false
        
        init(index: Int, refreshTrigger: Bool) {
            self.index = index
            self.refreshTrigger = refreshTrigger
            
            // Set static properties based on index for consistency
            self.size = [80, 100, 120][index % 3]
            self.baseOffset = [
                CGPoint(x: -100, y: -150),
                CGPoint(x: 50, y: 100),
                CGPoint(x: -50, y: -50)
            ][index % 3]
            self.animationDuration = [4.0, 5.0, 6.0][index % 3]
            self.animationDelay = Double(index) * 0.5
        }
        
        var body: some View {
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: size, height: size)
                .offset(
                    x: baseOffset.x + animationOffset.width,
                    y: baseOffset.y + animationOffset.height
                )
                .onAppear {
                    startAnimation()
                }
                .onChange(of: refreshTrigger) { _, _ in
                    // Restart animation when refresh is triggered
                    withAnimation(.easeInOut(duration: 0.3)) {
                        animationOffset = .zero
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        startAnimation()
                    }
                }
        }
        
        private func startAnimation() {
            withAnimation(
                .easeInOut(duration: animationDuration)
                .repeatForever(autoreverses: true)
                .delay(animationDelay)
            ) {
                // Create consistent animation pattern
                switch index % 3 {
                case 0:
                    animationOffset = CGSize(width: 60, height: 80)
                case 1:
                    animationOffset = CGSize(width: -40, height: -60)
                case 2:
                    animationOffset = CGSize(width: 80, height: -40)
                default:
                    animationOffset = CGSize(width: 50, height: 50)
                }
            }
        }
    }

    // Alternative: Simplified version using TimelineView for consistent animations
    struct AlternativeBackgroundDecoration: View {
        var body: some View {
            ZStack {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    
                    // Floating circles - sped up
                    ForEach(0..<3, id: \.self) { index in
                        let phase = time * 1.0 + Double(index) * 2.0  // Increased from 0.3 and 0.2
                        let offsetX = sin(phase * 1.0) * 30  // Increased frequency
                        let offsetY = cos(phase * 0.8) * 40  // Increased frequency
                        
                        Circle()
                            .fill(.white.opacity(0.05))
                            .frame(width: CGFloat(80 + index * 20))
                            .offset(
                                x: [-100, 50, -50][index] + offsetX,
                                y: [-150, 100, -50][index] + offsetY
                            )
                    }
                    
                    // Animated bike silhouette - much faster
                    let bikePhase = time * 0.125  // this is the main speed control
                    let bikeOffsetX = sin(bikePhase) * 80
                    let bikeOffsetY = cos(bikePhase * 1.2) * 60  // Increased frequency multiplier
                    let bikeRotation = sin(bikePhase * 1.5) * 15 // Increased frequency multiplier
                    
                    Image(systemName: "bicycle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 300, height: 300)
                        .foregroundStyle(.white.opacity(0.08)) // Back to subtle opacity
                        .rotationEffect(.degrees(-15 + bikeRotation))
                        .offset(
                            x: -80 + bikeOffsetX,
                            y: 150 + bikeOffsetY
                        )
                        .blur(radius: 1)
                }
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Location with subtle animation
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.pulse.byLayer, options: .repeating, isActive: viewModel.isLoading)
                
                Text(viewModel.locationDisplayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            
            // Date and time with enhanced styling
            Text("\(viewModel.rideDate, style: .date) at \(viewModel.rideDate, style: .time)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.white.opacity(0.15), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
// MARK: - Hero Weather Card

struct HeroWeatherCard: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var animateTemp = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Main temperature display
            HStack(alignment: .top, spacing: 20) {
                // Weather icon with animation
                Image(systemName: weather.iconName)
                    .font(.system(size: 80, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .symbolEffect(.bounce.byLayer, value: animateTemp)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Temperature
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(weather.temp))")
                            .font(.system(size: 72, weight: .thin, design: .rounded))
                            .contentTransition(.numericText())
                        
                        Text(viewModel.settings.units.tempSymbol)
                            .font(.system(size: 32, weight: .light))
                            .offset(y: -8)
                    }
                    .foregroundStyle(.white)
                    
                    // Description
                    Text(weather.description)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .contentTransition(.opacity)
                }
            }
            
            // Weather details grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
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
        .padding(12)
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

// MARK: - Weather Detail Item

struct WeatherDetailItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let rotation: Double?
    
    init(icon: String, label: String, value: String, color: Color, rotation: Double? = nil) {
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
        self.rotation = rotation
    }
    
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

// MARK: - Modern Hourly Forecast

struct ModernHourlyForecastView: View {
    let hourlyData: [HourlyForecast]
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var showingAnalytics = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("6-Hour Forecast", systemImage: "clock.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Updated View All button
                Menu {
                    Button {
                        showingAnalytics = true
                    } label: {
                        Label("Analytics Dashboard", systemImage: "chart.xyaxis.line")
                    }
                    
                    Button {
                        // Show extended hourly view (24-48 hours)
                        // Implementation for ExtendedHourlyForecastView
                    } label: {
                        Label("Extended Forecast", systemImage: "clock.arrow.circlepath")
                    }
                    
                    Button {
                        // Show weekly planning view
                        // Implementation for WeeklyCyclingPlanView
                    } label: {
                        Label("Weekly Planning", systemImage: "calendar")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(hourlyData.prefix(6).enumerated()), id: \.element.id) { index, hour in
                        HourlyForecastCard(hour: hour, index: index)
                            .environmentObject(viewModel)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .fullScreenCover(isPresented: $showingAnalytics) {
            AnalyticsDashboardView(hourlyData: viewModel.allHourlyData)
                .environmentObject(viewModel)
        }
    }
}


// MARK: - Hourly Forecast Card

struct HourlyForecastCard: View {
    let hour: HourlyForecast
    let index: Int
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 10) {
            // Time
            Text(hour.time)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
            
            // Weather icon
            Image(systemName: hour.iconName)
                .font(.title2)
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.bounce, value: appeared)
            
            // Temperature
            VStack(spacing: 4) {
                Text("\(Int(hour.temp))°")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                
                Text("Feels \(Int(hour.feelsLike))°")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            // Wind
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                    .rotationEffect(.degrees(Double(hour.windDeg) + 180))
                
                Text("\(Int(hour.windSpeed))")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.cyan)
            
            // Precipitation probability
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

// MARK: - Enhanced Bike Recommendation

struct EnhancedBikeRecommendationView: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var animateIcon = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Smart Recommendations", systemImage: recommendation.icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: animateIcon)
                
                Spacer()
                
                // Recommendation severity indicator
                Circle()
                    .fill(recommendationColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Recommendation content
            VStack(alignment: .leading, spacing: 12) {
                Text(recommendation.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(recommendation.advice)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(nil)
                
                // Action buttons (if applicable)
                if needsActionButton {
                    Button(actionButtonText) {
                        // Future implementation for actions
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(recommendationColor.opacity(0.8), in: Capsule())
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(recommendationColor.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: recommendationColor.opacity(0.2), radius: 12, y: 4)
        .onAppear {
            withAnimation(.bouncy.delay(0.3)) {
                animateIcon = true
            }
        }
    }
    
    private var recommendation: (title: String, advice: String, icon: String) {
        let tempF = viewModel.settings.units == .metric ? (weather.temp * 9/5) + 32 : weather.temp
        let wind = weather.windSpeed
        let desc = weather.description.lowercased()
        
        if desc.contains("rain") || desc.contains("thunderstorm") || desc.contains("drizzle") {
            return ("Rain Gear Essential", "It's wet out there! Wear a waterproof jacket, consider fenders, and be cautious on slick surfaces. Visibility may be reduced.", "cloud.rain.fill")
        }
        
        let windThreshold = viewModel.settings.units == .metric ? 6.7 : 15
        if wind > windThreshold {
            return ("High Wind Warning", "Strong winds detected. Expect extra resistance and be mindful of crosswinds. Consider a more aerodynamic position.", "wind")
        }
        
        if tempF < 40 {
            return ("Cold Weather Ride", "Dress in layers with thermal gear, gloves, and a head cover. Pre-warm your muscles and stay hydrated with warm fluids.", "thermometer.snowflake")
        }
        
        if tempF > 85 {
            return ("Hot Weather Alert", "Hydrate well before and during your ride. Use sunscreen, wear light breathable clothing, and consider starting earlier.", "sun.max.fill")
        }
        
        return ("Perfect Cycling Conditions!", "The weather looks great for a ride. Enjoy the road and stay safe out there!", "bicycle")
    }
    
    private var recommendationColor: Color {
        let desc = weather.description.lowercased()
        let tempF = viewModel.settings.units == .metric ? (weather.temp * 9/5) + 32 : weather.temp
        let wind = weather.windSpeed
        let windThreshold = viewModel.settings.units == .metric ? 6.7 : 15
        
        if desc.contains("rain") || desc.contains("thunderstorm") {
            return .blue
        } else if wind > windThreshold {
            return .orange
        } else if tempF < 40 {
            return .cyan
        } else if tempF > 85 {
            return .red
        } else {
            return .green
        }
    }
    
    private var needsActionButton: Bool {
        let desc = weather.description.lowercased()
        return desc.contains("rain") || desc.contains("thunderstorm")
    }
    
    private var actionButtonText: String {
        return "Gear Checklist"
    }
}

// MARK: - Weather Insights Card

struct WeatherInsightsCard: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Weather Insights", systemImage: "chart.line.uptrend.xyaxis")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
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
        .padding(20)
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

// MARK: - Insight Item

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

// MARK: - Modern Shimmer View

struct ModernShimmerView: View {
    var body: some View {
        VStack(spacing: 12) {
            // Hero card shimmer
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 80, height: 80)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.3))
                            .frame(width: 120, height: 40)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.2))
                            .frame(width: 100, height: 20)
                    }
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 30, height: 30)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.2))
                                .frame(height: 16)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shimmer()
            
            // Additional shimmer cards
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20)
                    .fill(.thinMaterial)
                    .frame(height: 120)
                    .shimmer()
            }
        }
    }
}

// MARK: - Modern Error View

struct ModernErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.yellow)
                .symbolEffect(.bounce)
            
            VStack(spacing: 8) {
                Text("Weather Unavailable")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(.blue, in: Capsule())
                    .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Modern Settings View

struct ModernSettingsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @State private var localRideDate: Date

    init(currentRideDate: Date) {
        _localRideDate = State(initialValue: currentRideDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Ride Date & Time",
                        selection: $localRideDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    
                    // Quick time adjustments
                    HStack(spacing: 12) {
                        quickTimeButton("Now", action: { localRideDate = Date() })
                        quickTimeButton("+1 Hr", action: { adjustTime(by: .hour, value: 1) })
                        quickTimeButton("+1 Day", action: { adjustTime(by: .day, value: 1) })
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Label("Ride Time", systemImage: "clock")
                }
                
                Section {
                    Picker("Temperature & Speed Units", selection: $viewModel.settings.units) {
                        ForEach(UnitSystem.allCases) { unit in
                            Text(unit.description).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Units", systemImage: "gauge")
                }
                
                Section {
                    Label("Made for Cyclists", systemImage: "bicycle")
                        .foregroundStyle(.secondary)
                    
                    Label("Weather data by OpenWeather", systemImage: "cloud.fill")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if viewModel.rideDate != localRideDate {
                            viewModel.rideDate = localRideDate
                            Task { await viewModel.fetchAllWeather() }
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func quickTimeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .frame(maxWidth: .infinity)
    }
    
    private func adjustTime(by component: Calendar.Component, value: Int) {
        localRideDate = Calendar.current.date(byAdding: component, value: value, to: localRideDate) ?? localRideDate
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Extensions

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
