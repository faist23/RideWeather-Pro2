//
// RideWeatherProApp.swift
//

import SwiftUI
import MapKit

@main
struct RideWeatherProApp: App {
    @StateObject private var weatherViewModel = WeatherViewModel()
    @StateObject private var stravaService = StravaService()
    @StateObject private var wahooService = WahooService()
    @StateObject private var healthManager = HealthKitManager()
    @State private var showLaunchView = true
    
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.blue.opacity(0.6).ignoresSafeArea()
                MainView()
                    .environmentObject(weatherViewModel)
                    .environmentObject(stravaService)
                    .environmentObject(wahooService)
                    .environmentObject(healthManager)
                
                if showLaunchView {
                    LaunchView()
                        .transition(.opacity.animation(.easeOut(duration: 0.5)))
                }
            }
            .onReceive(weatherViewModel.initialDataLoaded) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation {
                        showLaunchView = false
                    }
                }
                // Perform initial weight sync on first load
                Task {
                    await syncWeight()
                }
            }
            .task {
                // Initialize MapKit early to reduce first-time loading lag
                await initializeMapKit()
            }
            .onOpenURL { url in
                print("App received URL via onOpenURL: \(url.absoluteString)")
                // Check if it's the Strava callback URL based on scheme and host
                if url.scheme == "rideweatherpro" && url.host == "strava-auth" {
                    // Pass the URL to your StravaService instance
                    // Since StravaService is @MainActor, this call is safe
                    stravaService.handleRedirect(url: url)
                    // Check for the new Wahoo callback URL
                } else if url.scheme == "rideweatherpro" && url.host == "wahoo-auth" {
                    print("Handling Wahoo auth redirect...")
                    // You will need to create a WahooService that mirrors
                    // your StravaService and has its own handleRedirect method.
                    
                    wahooService.handleRedirect(url: url)
                    
                    // For now, you can print to confirm it works:
                    print("Wahoo auth code received: \(url.absoluteString)")
                                        
                } else if url.isFileURL {
                    print("Handling imported file URL...")
                    weatherViewModel.importRoute(from: url)
                    
                } else {
                    print("URL is not a file or a known auth callback.")
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // When app becomes active (e.g., user returns to it)
                if newPhase == .active && (oldPhase == .inactive || oldPhase == .background) {
                    // Run the daily sync logic
                    Task {
                        await syncWeight()
                        await healthManager.fetchReadinessData() // <-- ADD THIS
                    }
                    
                    // Also run the training load fill logic
                    TrainingLoadManager.shared.fillMissingDays()
                }
            }
        }
    }
    
    private func initializeMapKit() async {
        // Force MapKit initialization in background during app launch
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await MainActor.run {
                    // Create a temporary map view to initialize MapKit framework
                    let warmupMap = MKMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
                    warmupMap.mapType = .standard
                    // Set a reasonable region to trigger tile loading
                    warmupMap.region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    )
                    // Clean up
                    warmupMap.removeFromSuperview()
                }
            }
        }
    }

/*    func applicationDidBecomeActive() {
        // Fill any missing days with zero TSS
        TrainingLoadManager.shared.fillMissingDays()
    }*/

    private func syncWeight() async {
        if let newWeightKg = await stravaService.autoSyncWeightIfNeeded(settings: weatherViewModel.settings) {
            // Update the view model's settings, which will trigger UI updates and save to UserDefaults
            await MainActor.run {
                // Set the raw KG value
                weatherViewModel.settings.bodyWeight = newWeightKg
                
                // This will trigger the UI to update correctly in lbs or kg
                // by re-calculating from the new source KG value.
                let _ = weatherViewModel.settings.bodyWeightInUserUnits
            }
        }
    }
}
