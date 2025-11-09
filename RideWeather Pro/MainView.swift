
//
// MainView.swift
//

import SwiftUI
import MapKit
import CoreLocation

struct MainView: View {
    @StateObject private var viewModel = WeatherViewModel()
    @State private var selectedTab = 0
    @State private var lastLiveWeatherTap = Date()
    @EnvironmentObject var wahooService: WahooService // 1. Receive the service.....not convinced this is needed
    
    var body: some View {
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
            TrainingLoadView()
                .environmentObject(viewModel)  // Pass the WeatherViewModel
                .tabItem {
                    Label("Fitness", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
        }
        .environmentObject(wahooService) //i'm not convinced this line is needed
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
