//
//  MainView.swift
//  RideWeather Pro
//


import SwiftUI
import MapKit
import CoreLocation

struct MainView: View {
    @StateObject private var viewModel = WeatherViewModel()
    // OBSERVE THE DATA SOURCE MANAGER
    @ObservedObject private var dataSourceManager = DataSourceManager.shared
    
    @State private var selectedTab = 0
    @State private var lastLiveWeatherTap = Date()
    @EnvironmentObject var wahooService: WahooService // Inherited from App
    
    var body: some View {
        ZStack(alignment: .topTrailing) { // WRAP IN ZSTACK
            TabView(selection: $selectedTab) {
                LiveWeatherView()
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("Live Weather", systemImage: "sun.max.fill")
                    }
                    .tag(0)
                    .onAppear {
                        // Only refresh if it's been more than 30 seconds since last tap
                        // or if this is the first time appearing
                        let now = Date()
                        if now.timeIntervalSince(lastLiveWeatherTap) > 30 {
                            Task {
                                await viewModel.refreshWeather()
                            }
                            lastLiveWeatherTap = now
                        }
                    }
                
                RouteForecastView()
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("Route Forecast", systemImage: "map.fill")
                    }
                    .tag(1)
                
                // MARK: - Conditional Analysis Tab
                // Only accessible if Power-Based Analysis is enabled in Settings
                if viewModel.settings.speedCalculationMethod == .powerBased {
                    RideAnalysisView(weatherViewModel: viewModel)
                        .tabItem {
                            Label("Analysis", systemImage: "stopwatch.fill")
                        }
                        .tag(2)
                }
                
                TrainingLoadView()
                    .environmentObject(viewModel)  // Pass the WeatherViewModel
                    .tabItem {
                        Label("Fitness", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tag(3)
                
            }
        }
        .environmentObject(wahooService)
        .onChange(of: selectedTab) { oldValue, newValue in
            // When user taps Live Weather tab, refresh the weather
            if newValue == 0 && oldValue != 0 {
                Task {
                    await viewModel.refreshWeather()
                }
                lastLiveWeatherTap = Date()
            }
        }
        .task {
            // Additional MapKit warming - create map components early
            await warmUpMapComponents()
        }
        .preferredColorScheme(.dark)
    }
    
    private func warmUpMapComponents() async {
        // This helps pre-load map-related components in the background
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await MainActor.run {
                    // Pre-initialize location services
                    let _ = CLLocationManager()
                    
                    // Pre-warm coordinate systems
                    let _ = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                    let _ = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    )
                }
            }
        }
    }
}

// SUBVIEW FOR THE BADGE
struct DataSourceBadge: View {
    let source: DataSourceConfiguration.TrainingLoadSource
    
    var body: some View {
        HStack(spacing: 6) {
            // Icon
            if source.icon.contains("_logo") {
                Image(source.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: source.icon)
                    .font(.caption2)
            }
            
            // Text
            Text(source.rawValue)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}
