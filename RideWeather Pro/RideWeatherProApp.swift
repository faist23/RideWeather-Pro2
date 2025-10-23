//
// RideWeatherProApp.swift
//

import SwiftUI
import MapKit

@main
struct RideWeatherProApp: App {
    @StateObject private var weatherViewModel = WeatherViewModel()
    @StateObject private var stravaService = StravaService() // Add this
    @State private var showLaunchView = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.blue.opacity(0.6).ignoresSafeArea()
                MainView()
                    .environmentObject(weatherViewModel)
                    .environmentObject(stravaService) // Pass it down
                
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
            }
            .task {
                // Initialize MapKit early to reduce first-time loading lag
                await initializeMapKit()
            }
            // V V V ADD THIS MODIFIER V V V
            .onOpenURL { url in
                print("App received URL via onOpenURL: \(url.absoluteString)")
                // Check if it's the Strava callback URL based on scheme and host
                if url.scheme == "rideweatherpro" && url.host == "strava-auth" {
                    // Pass the URL to your StravaService instance
                    // Since StravaService is @MainActor, this call is safe
                    stravaService.handleRedirect(url: url)
                } else {
                    print("URL is not the expected Strava callback.")
                    // Handle other URL schemes if your app supports them
                }
            }
            // ^ ^ ^ ADD THIS MODIFIER ^ ^ ^
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
}
