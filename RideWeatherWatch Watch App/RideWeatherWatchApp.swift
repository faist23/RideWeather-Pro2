//
//  RideWeatherWatchApp.swift
//  RideWeatherWatch Watch App
//
//  Updated: Adds Conditional Alert Tab at Index 0
//

import SwiftUI
import UserNotifications
import Combine

// MARK: - Tab Definitions
enum WatchTab: Hashable {
    case readiness
    case form
    case recovery
    case steps
    case weather
    case alert
}

@main
struct RideWeatherWatch_App: App {
    @StateObject private var navigationManager = NavigationManager()
    
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigationManager.path) {
                ContentView()
            }
            .environmentObject(navigationManager)
            .onOpenURL { url in
                navigationManager.handleURL(url)
            }
            .onAppear {
                // Permissions & Background Tasks
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                
                Task { @MainActor in
                    BackgroundStepsUpdater.shared.startBackgroundUpdates()
                }
                
                Task {
                    await WatchLocationManager.shared.startUpdating()
                }
            }
        }
    }
}

// MARK: - Navigation Manager

@MainActor
class NavigationManager: ObservableObject {
    @Published var path = NavigationPath()
    @Published var selectedTab: WatchTab = .readiness
    
    func handleURL(_ url: URL) {
        // Reset stack
        if !path.isEmpty { path.removeLast(path.count) }
        
        // Deep Link Handling
        switch url.host {
        case "weather": selectedTab = .weather
        case "steps": selectedTab = .steps
        case "alert": selectedTab = .alert // Handle alert deep links
        default: break
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @ObservedObject private var session = WatchSessionManager.shared
    
    var body: some View {
        // We bind the selection to the navigation manager.
        TabView(selection: $navigationManager.selectedTab) {
            
            // PAGE 1: READINESS
            Group {
                if let readiness = session.readinessData,
                   let load = session.loadSummary {
                    ReadinessView(readiness: readiness, tsb: load.currentTSB)
                } else {
                    ContentUnavailableView("No Data", systemImage: "figure.strengthtraining.traditional")
                        .containerBackground(.gray.gradient, for: .tabView)
                }
            }
            .tag(WatchTab.readiness)
            
            // PAGE 2: FORM
            Group {
                if let load = session.loadSummary,
                   let weeklyProgress = session.weeklyProgress {
                    FormView(summary: load, weeklyProgress: weeklyProgress)
                } else {
                    ContentUnavailableView("No Data", systemImage: "chart.bar.xaxis")
                        .containerBackground(.blue.gradient, for: .tabView)
                }
            }
            .tag(WatchTab.form)
            
            // PAGE 3: RECOVERY
            Group {
                if let recovery = session.recoveryStatus,
                   let wellness = session.currentWellness {
                    RecoveryView(recovery: recovery, wellness: wellness)
                } else {
                    ContentUnavailableView("No Data", systemImage: "heart.slash")
                        .containerBackground(.black.gradient, for: .tabView)
                }
            }
            .tag(WatchTab.recovery)
            
            // PAGE 4: STEPS
            StepsDetailView()
                .tag(WatchTab.steps)
            
            // PAGE 5: WEATHER
            WeatherDetailView()
                .tag(WatchTab.weather)
            
            // PAGE 6: ALERT (Only if active)
            if let alert = session.weatherAlert {
                AlertView(alert: alert)
                    .tag(WatchTab.alert)
            }
        }
        .tabViewStyle(.page)
        // Auto-switch to alert ONLY if it's a new, severe warning.
        // Otherwise, let the user discover it via the banner.
        .onChange(of: session.weatherAlert?.message) { _, newValue in
            if let alert = session.weatherAlert, alert.severity == .severe {
                withAnimation { navigationManager.selectedTab = .alert }
            }
        }
    }
}

