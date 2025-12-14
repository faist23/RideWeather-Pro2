//
//  RideWeatherProApp.swift
//  RideWeather Pro
//

import SwiftUI
import MapKit

@main
struct RideWeatherProApp: App {
    @StateObject private var weatherViewModel = WeatherViewModel()
    @StateObject private var stravaService = StravaService()
    @StateObject private var wahooService = WahooService()
    @StateObject private var garminService = GarminService()
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
                    .environmentObject(garminService)
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
                    wahooService.handleRedirect(url: url)
                    
                } else if url.scheme == "rideweatherpro" && url.host == "garmin-auth" {
                    print("Handling Garmin auth redirect...")
                    garminService.handleRedirect(url: url)
                    
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
        // Check the user's preferred source
        let source = weatherViewModel.settings.weightSource
        
        var newWeight: Double? = nil
        
        switch source {
        case .strava:
            // Only attempt if user wants Strava and is connected
            if stravaService.isAuthenticated {
                do {
                    // We call fetchAthleteWeight directly, bypassing the old "autoSync" boolean check
                    newWeight = try await stravaService.fetchAthleteWeight()
                } catch {
                    print("Strava weight sync failed: \(error)")
                }
            }
            
        case .healthKit:
            // Only fetch from HealthKit if selected
            if healthManager.isAuthorized {
                newWeight = await healthManager.fetchLatestWeight()
            }
            
        case .garmin:
            // Fetch from Garmin wellness data
            if garminService.isAuthenticated {
                newWeight = await fetchWeightFromGarmin()
            }

        case .manual:
            // Do nothing - user wants to manage it manually
            return
        }
        
        // If we got a valid weight from the selected source, update the app settings
        if let weight = newWeight, weight > 0 {
            await MainActor.run {
                // Update settings with the new weight
                weatherViewModel.settings.bodyWeight = weight
                
                // Trigger UI update (computed property access)
                let _ = weatherViewModel.settings.bodyWeightInUserUnits
                print("✅ Synced weight from \(source.rawValue): \(weight) kg")
            }
        }
    }
    
    private func fetchWeightFromGarmin() async -> Double? {
        // Fetch from WellnessManager (which gets Garmin data)
        let wellnessManager = WellnessManager.shared
        
        // Get most recent wellness metrics that has body mass
        if let latestMetrics = wellnessManager.dailyMetrics
            .sorted(by: { $0.date > $1.date })
            .first(where: { $0.bodyMass != nil }),
           let bodyMass = latestMetrics.bodyMass {
            print("✅ Fetched weight from Garmin wellness: \(bodyMass) kg")
            return bodyMass
        }
        
        print("⚠️ No weight data found in Garmin wellness")
        return nil
    }
}
