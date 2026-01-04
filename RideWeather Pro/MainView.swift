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
    @State private var lastFitnessTap = Date()  // Track fitness tab taps

    @EnvironmentObject var wahooService: WahooService // Inherited from App
    @EnvironmentObject var healthManager: HealthKitManager  // Access HealthKit
    @EnvironmentObject var garminService: GarminService    // Access Garmin

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
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("Fitness", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tag(3)
                    // Sync wellness data when Fitness tab appears
                    .onAppear {
                        let now = Date()
                        // Only sync if it's been more than 5 minutes since last tap
                        if now.timeIntervalSince(lastFitnessTap) > 300 {
                            Task {
                                await syncWellnessData()
                            }
                            lastFitnessTap = now
                        }
                    }
            }
        }
        .environmentObject(wahooService)
        .onChange(of: selectedTab) { oldValue, newValue in
            // Refresh Live Weather when tapped
            if newValue == 0 && oldValue != 0 {
                Task {
                    await viewModel.refreshWeather()
                }
                lastLiveWeatherTap = Date()
            }
            
            // Sync wellness when Fitness tab is tapped
            if newValue == 3 && oldValue != 3 {
                Task {
                    await syncWellnessData()
                }
                lastFitnessTap = Date()
            }
        }
        .task {
            await warmUpMapComponents()
        }
        .preferredColorScheme(.dark)
    }
    
    // Wellness sync helper function
    private func syncWellnessData() async {
        let wellnessSync = UnifiedWellnessSync()
        
        await wellnessSync.syncFromConfiguredSource(
            healthManager: healthManager,
            garminService: garminService,
            days: 7  // Sync last 7 days to capture today's steps
        )
        
        print("🏋️ MainView: Wellness data synced from configured source")
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
