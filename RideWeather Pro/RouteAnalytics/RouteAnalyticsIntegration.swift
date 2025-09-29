//
//  RouteAnalyticsButton.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/17/25.
//


//
//  RouteAnalyticsIntegration.swift
//  RideWeather Pro
//
//  Integration components for route analytics
//

import SwiftUI

// MARK: - Analytics Button for Route Bottom Controls
struct RouteAnalyticsButton: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var showingAnalytics = false
    
    var body: some View {
        Button {
            showingAnalytics = true
        } label: {
            Label("Analyze Weather", systemImage: "chart.xyaxis.line")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.weatherDataForRoute.isEmpty)
        .tint(.purple)
        .sheet(isPresented: $showingAnalytics) {
            RouteAnalyticsDashboardView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Analytics Card for Route Forecast View
struct RouteAnalyticsCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var showingAnalytics = false
    
    private var routeAnalytics: RouteWeatherAnalytics {
        RouteWeatherAnalytics(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units
        )
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weather Analysis Ready")
                        .font(.headline.weight(.semibold))
                    
                    Text("\(routeAnalytics.weatherPoints.count) weather points along your route")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
            }
            
            // Quick preview stats
            HStack(spacing: 20) {
                AnalyticsPreviewStat(
                    icon: "thermometer",
                    label: "Temp Range",
                    value: "\(Int(routeAnalytics.temperatureRange.min))° - \(Int(routeAnalytics.temperatureRange.max))°"
                )
                
                AnalyticsPreviewStat(
                    icon: "clock",
                    label: "Duration",
                    value: routeAnalytics.estimatedDuration
                )
                
                AnalyticsPreviewStat(
                    icon: "exclamationmark.triangle",
                    label: "Insights",
                    value: "\(routeAnalytics.keyInsights.count)"
                )
            }
            
            Button {
                showingAnalytics = true
            } label: {
                Label("View Detailed Analysis", systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.purple)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingAnalytics) {
            RouteAnalyticsDashboardView()
                .environmentObject(viewModel)
        }
    }
}

struct AnalyticsPreviewStat: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.purple)
            
            Text(value)
                .font(.caption.weight(.semibold))
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Updated Route Bottom Controls with Analytics
struct EnhancedRouteBottomControlsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Binding var isImporting: Bool
    @FocusState var isSpeedFieldFocused: Bool
    @Binding var showBottomControls: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Status indicators
            if viewModel.isLoading {
                ModernLoadingView()
            }
            
            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }
            
            // Show analytics card if weather data exists
            if !viewModel.weatherDataForRoute.isEmpty {
                RouteAnalyticsCard()
                    .environmentObject(viewModel)
                    .transition(.opacity.combined(with: .scale))
            }
            
            // Settings
            VStack(spacing: 0) {
                // Ride Time Setting
                LabeledContent {
                    DatePicker(
                        "",
                        selection: $viewModel.rideDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                } label: {
                    Label("Ride Time", systemImage: "clock")
                        .font(.headline)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Average Speed Setting
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("Speed", text: $viewModel.averageSpeedInput)
                            .keyboardType(.decimalPad)
                            .focused($isSpeedFieldFocused)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        
                        Text(viewModel.settings.units.speedUnitAbbreviation)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Avg. Speed", systemImage: "speedometer")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            // Action buttons
            VStack(spacing: 8) {
                // Generate forecast button
                Button {
                    isSpeedFieldFocused = false
                    withAnimation(.smooth) {
                        showBottomControls = false
                    }
                    Task { await viewModel.calculateAndFetchWeather() }
                } label: {
                    Label("Generate Forecast", systemImage: "cloud.sun.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.routePoints.isEmpty)
                
                // Analytics button (only show if weather data exists)
                if !viewModel.weatherDataForRoute.isEmpty {
                    RouteAnalyticsButton()
                        .environmentObject(viewModel)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            
            // Import button
            Button {
                isImporting = true
            } label: {
                Label("Import New Route", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .shadow(color: .black.opacity(0.1), radius: 16, y: 4)
        .animation(.smooth, value: viewModel.weatherDataForRoute.isEmpty)
    }
}

// MARK: - Weather Summary Card (appears above map when weather data loads)
struct RouteWeatherSummaryCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var showingAnalytics = false
    
    private var routeAnalytics: RouteWeatherAnalytics {
        RouteWeatherAnalytics(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units
        )
    }
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    
                    Text("Weather Analysis Complete")
                        .font(.headline.weight(.semibold))
                }
                
                Text("\(routeAnalytics.estimatedDuration) ride • \(Int(routeAnalytics.temperatureRange.min))°-\(Int(routeAnalytics.temperatureRange.max))° • \(routeAnalytics.keyInsights.count) insights")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                showingAnalytics = true
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
        .sheet(isPresented: $showingAnalytics) {
            RouteAnalyticsDashboardView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Integration with Existing RouteForecastView
extension RouteForecastView {
    var enhancedOverlayContent: some View {
        VStack {
            if let timeString = estimatedRideTime {
                EstimatedTimeChip(timeString: timeString)
                    .padding(.top, 12)
            }
            
            // Show weather summary card when weather data is available
            if !viewModel.weatherDataForRoute.isEmpty && !viewModel.isLoading {
                RouteWeatherSummaryCard()
                    .environmentObject(viewModel)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Spacer()

            if viewModel.routePoints.isEmpty {
                RouteEmptyStateView {
                    isImporting = true
                }
                .transition(.opacity.combined(with: .scale))
                Spacer()
            }

            if showBottomControls {
                EnhancedRouteBottomControlsView(
                    isImporting: $isImporting,
                    isSpeedFieldFocused: _isSpeedFieldFocused,
                    showBottomControls: $showBottomControls
                )
                .environmentObject(viewModel)
                .transition(.move(edge: .bottom))
            } else {
                Button { 
                    withAnimation(.smooth) { showBottomControls = true } 
                } label: {
                    Label("Show Controls", systemImage: "chevron.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Usage Instructions
/*
 To integrate this route-aware analytics system:
 
 1. Replace your existing RouteBottomControlsView with EnhancedRouteBottomControlsView
 2. Add the RouteWeatherSummaryCard to appear above the map when weather data loads
 3. The analytics will automatically show:
    - Route-specific weather timeline during the ride duration
    - Key insights about temperature changes, wind conditions, rain risk
    - Route segment analysis breaking down conditions by mile markers
    - Alternative start time recommendations
    - Detailed weather at each point along the route
 
 The analytics only appear AFTER a route is loaded and weather data is fetched,
 making them contextual and actionable for the specific ride plan.
 */