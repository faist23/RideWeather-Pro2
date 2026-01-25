//
// LiveWeatherView.swift (Updated with Analytics)
// RideWeather Pro
//
// Modern iOS 26+ interface with enhanced analytics integration
//

import SwiftUI
import CoreLocation

struct LiveWeatherView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isShowingSettings = false
    @State private var scrollOffset: CGFloat = 0
    @State private var refreshTrigger = false
    
    var backgroundGradient: LinearGradient {
        let hour = Calendar.current.component(.hour, from: viewModel.rideDate)
        let isDayTime = hour >= 6 && hour < 19
        let temp = viewModel.displayWeather?.temp ?? 20
        
        if isDayTime {
            if temp > 25 { // Hot day
                return LinearGradient(colors: [.orange.opacity(0.8), .red.opacity(0.6), .yellow.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else if temp < 10 { // Cold day
                return LinearGradient(colors: [.blue.opacity(0.8), .cyan.opacity(0.6), .mint.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else { // Pleasant day
                return LinearGradient(colors: [.blue.opacity(0.7), .cyan.opacity(0.5), .green.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else { // Night time
            return LinearGradient(colors: [.black, .indigo.opacity(0.8), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        headerView
                            .offset(y: scrollOffset > 0 ? -scrollOffset * 0.7 : 0)
                            .opacity(1 - (scrollOffset / 200).clamped(to: 0...1))
                        
                        // Weather Alerts Carousel
                        if !viewModel.weatherAlerts.isEmpty {
                            WeatherAlertsCarousel(alerts: viewModel.weatherAlerts)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        if viewModel.isLoading && viewModel.displayWeather == nil {
                            ModernShimmerView()
                                .transition(.opacity.combined(with: .scale))
                        } else if let weatherData = viewModel.displayWeather {
                            VStack(spacing: 12) {
                                HeroWeatherCard(weather: weatherData)
                                    .environmentObject(viewModel)
                                
                                ModernHourlyForecastView(hourlyData: viewModel.hourlyForecast)
                                    .environmentObject(viewModel)
                                
                                // 7-day forecast card
                                 if !viewModel.dailyForecast.isEmpty {
                                     DailyForecastView(daily: viewModel.dailyForecast)
                                         .environmentObject(viewModel)
                                         .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                 }

                                if viewModel.shouldShowAnalytics {
                                    ModernAnalyticsPreviewCard()
                                        .environmentObject(viewModel)
                                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                                
                                EnhancedBikeRecommendationView(weather: weatherData)
                                    .environmentObject(viewModel)
                                
                                WeatherInsightsCard(weather: weatherData, insights: viewModel.enhancedInsights)
                                    .environmentObject(viewModel)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                            
                        } else if let errorMessage = viewModel.errorMessage {
                            ModernErrorView(message: errorMessage) {
                                Task { await viewModel.refreshWeather() }
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                        
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: scrollGeometry.frame(in: .named("scroll")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = -value
                }
            }
            .animatedBackground(
                gradient: .cyclingBackground(
                    temperature: viewModel.displayWeather?.temp,
                    rideDate: viewModel.rideDate
                ),
                decorationColor: .white,
                decorationIntensity: 0.05
            )
            .refreshable {
                await viewModel.refreshWeather()
            }
            .navigationTitle("Live Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshWeather() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $viewModel.showingAnalytics) {
                AnalyticsDashboardView(hourlyData: viewModel.hourlyForecasts)
                    .environmentObject(viewModel)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundStyle(.white.opacity(0.9))
                
                Text(viewModel.locationDisplayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            
            Text(viewModel.formattedRideDate)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.white.opacity(0.15), in: Capsule())
        }
        .padding(.top)
    }
}

// MARK: - Modern Analytics Preview Card

struct ModernAnalyticsPreviewCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isAnimating = false
    
    private var analyticsHelper: CyclingAnalyticsHelper {
        CyclingAnalyticsHelper(hourlyData: viewModel.hourlyForecasts, units: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with icon and title
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
  //                  .rotationEffect(.degrees(isAnimating ? 360 : 0))
  //                  .animation(.easeInOut(duration: 4).repeatForever(autoreverses: false), value: isAnimating)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycling Analytics")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Smart insights for your ride")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Spacer()
                
                // Notification badge for challenging conditions
                if viewModel.analyticsNotificationBadge {
                    Circle()
                        .fill(.red.gradient)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 2)
                        )
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isAnimating)
                }
            }
            
            // Quick stats grid
            HStack(spacing: 12) {
                ModernAnalyticsStatCard(
                    icon: "heart.fill",
                    title: "Comfort",
                    value: "\(analyticsHelper.averageComfort)%",
                    color: comfortColor(for: analyticsHelper.averageComfort)
                )
                
                ModernAnalyticsStatCard(
                    icon: "star.fill",
                    title: "Optimal",
                    value: "\(analyticsHelper.optimalHoursCount)h",
                    color: .yellow
                )
                
                if let bestHour = analyticsHelper.bestHour {
                    ModernAnalyticsStatCard(
                        icon: "clock.fill",
                        title: "Best Time",
                        value: bestHour.time,
                        color: .blue
                    )
                }
            }
            
            // Call to action button
            Button {
                // Launch an asynchronous Task to call the new function
                Task {
                    await viewModel.openAnalytics()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("View Detailed Analysis")
                        .font(.subheadline.weight(.semibold))
                    
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .onAppear {
            isAnimating = true
        }
    }
    
    private func comfortColor(for comfort: Int) -> Color {
        if comfort > 80 {
            return .green
        } else if comfort > 60 {
            return .yellow
        } else if comfort > 40 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Modern Analytics Stat Card

struct ModernAnalyticsStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.bouncy(duration: 0.3), value: isPressed)
        .onTapGesture {
            withAnimation(.bouncy) {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                }
            }
        }
    }
}

// MARK: - Weather Alerts Carousel

struct WeatherAlertsCarousel: View {
    let alerts: [WeatherAlert]
    @State private var scrollPosition: UUID?
    @State private var expandedAlertId: UUID?
    
    // Sort alerts by severity (severe > warning > advisory)
    private var sortedAlerts: [WeatherAlert] {
        alerts.sorted { alert1, alert2 in
            let severityOrder: [WeatherAlert.Severity: Int] = [
                .severe: 0,
                .warning: 1,
                .advisory: 2
            ]
            return (severityOrder[alert1.severity] ?? 3) < (severityOrder[alert2.severity] ?? 3)
        }
    }
    
    private var currentIndex: Int {
        guard let scrollPosition = scrollPosition,
              let index = sortedAlerts.firstIndex(where: { $0.id == scrollPosition }) else {
            return 0
        }
        return index
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Horizontal ScrollView for all alerts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(sortedAlerts.enumerated()), id: \.element.id) { index, alert in
                        WeatherAlertBanner(
                            alert: alert,
                            isExpanded: expandedAlertId == alert.id,
                            onToggle: {
                                print("🔔 Alert tapped: \(alert.message)")
                                withAnimation(.spring()) {
                                    if expandedAlertId == alert.id {
                                        print("🔔 Collapsing alert")
                                        expandedAlertId = nil
                                    } else {
                                        print("🔔 Expanding alert")
                                        expandedAlertId = alert.id
                                    }
                                }
                            },
                            totalAlerts: sortedAlerts.count,
                            currentIndex: index
                        )
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.8)
                                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                        }
                        .id(alert.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPosition)
            .onChange(of: scrollPosition) { oldValue, newValue in
                // Auto-expand the new alert if previous one was expanded
                if oldValue != newValue, expandedAlertId != nil, let newValue = newValue {
                    withAnimation(.spring()) {
                        expandedAlertId = newValue
                    }
                }
            }
            .onAppear {
                // Set initial position to first alert
                if scrollPosition == nil {
                    scrollPosition = sortedAlerts.first?.id
                }
            }
            
            // Page Indicators - subtle dots only
            if sortedAlerts.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<sortedAlerts.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? .white : .white.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .scaleEffect(index == currentIndex ? 1.2 : 1.0)
                            .animation(.spring(duration: 0.3), value: currentIndex)
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Weather Alert Banner (Updated)

struct WeatherAlertBanner: View {
    let alert: WeatherAlert
    let isExpanded: Bool
    let onToggle: () -> Void
    let totalAlerts: Int
    let currentIndex: Int
    
    // Convenience init for single alerts
    init(alert: WeatherAlert, isExpanded: Bool, onToggle: @escaping () -> Void) {
        self.alert = alert
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.totalAlerts = 1
        self.currentIndex = 0
    }
    
    // Full init for carousel
    init(alert: WeatherAlert, isExpanded: Bool, onToggle: @escaping () -> Void, totalAlerts: Int, currentIndex: Int) {
        self.alert = alert
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.totalAlerts = totalAlerts
        self.currentIndex = currentIndex
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                onToggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(alert.textColor)
                        .symbolEffect(.pulse, options: .repeating, isActive: true)
                    
                    Text(alert.message.capitalized)
                        .font(.headline.bold())
                        .foregroundStyle(alert.textColor)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Show "+X" badge if there are more alerts
                    if totalAlerts > 1 {
                        Text("+\(totalAlerts - 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(alert.textColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(alert.textColor.opacity(0.2), in: Capsule())
                    }
                    
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(alert.textColor.opacity(0.8))
                }
                .padding()
                .background(alert.color.gradient)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(alert.cleanDescription)
                        .font(.subheadline)
                        .foregroundStyle(alert.textColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    
                    Text("Severity: \(alert.severity.rawValue.capitalized)")
                        .font(.caption.bold())
                        .foregroundStyle(alert.textColor.opacity(0.8))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alert.color)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
    }
}

// MARK: - Extensions for WeatherViewModel

extension WeatherViewModel {
    var shouldShowAnalytics: Bool {
        return !hourlyForecasts.isEmpty && hourlyForecasts.count >= 6
    }
    
    var analyticsNotificationBadge: Bool {
        guard !hourlyForecasts.isEmpty else { return false }
        let helper = CyclingAnalyticsHelper(hourlyData: hourlyForecasts, units: settings.units, idealTemp: settings.idealTemperature)
        let maxPrecip = hourlyForecasts.map { $0.pop }.max() ?? 0
        return helper.challengingHoursCount > helper.optimalHoursCount ||
               maxPrecip > 0.6 ||
               helper.averageComfort < 50
    }
}

/*
#Preview("Multiple Alerts") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 20) {
                WeatherAlertsCarousel(alerts: [
                    WeatherAlert(
                        message: "Winter Storm Warning",
                        description: "Heavy snow expected. Total snow accumulations of 8 to 12 inches possible. Winds gusting as high as 35 mph. Travel could be very difficult. The hazardous conditions could impact the morning or evening commute.",
                        severity: .severe
                    ),
                    WeatherAlert(
                        message: "Wind Advisory",
                        description: "Sustained winds of 20 to 30 mph with gusts up to 50 mph expected.",
                        severity: .warning
                    ),
                    WeatherAlert(
                        message: "Frost Advisory",
                        description: "Temperatures as low as 32 degrees will result in frost formation.",
                        severity: .advisory
                    )
                ])
                .padding()
                
                Text("Swipe to see all alerts →")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .background(.blue.gradient)
    }
}

#Preview("Single Alert") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 20) {
                WeatherAlertsCarousel(alerts: [
                    WeatherAlert(
                        message: "Winter Storm Warning",
                        description: "Heavy snow expected. Total snow accumulations of 8 to 12 inches possible. Winds gusting as high as 35 mph. Travel could be very difficult. The hazardous conditions could impact the morning or evening commute.",
                        severity: .severe
                    )
                ])
                .padding()
                
                Text("Single alert - no carousel needed")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .background(.blue.gradient)
    }
}
*/
