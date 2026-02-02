//
//  RideWeatherWatchApp.swift
//  RideWeatherWatch Watch App
//
//  Fixed: Proper background colors for all tabs including placeholders
//

import SwiftUI
import UserNotifications
import Combine

// Ensure WeatherAlert is Equatable for onChange to work
extension WeatherAlert: Equatable {
    static func == (lhs: WeatherAlert, rhs: WeatherAlert) -> Bool {
        return lhs.message == rhs.message && lhs.description == rhs.description
    }
}

// MARK: - Tab Definitions
enum WatchTab: Hashable {
    case readiness
    case form
    case recovery
    case steps
    case weather
    case alert(Int) // CHANGED: Now accepts an index (0, 1, 2...)
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
    @Published var weatherResetTrigger = false
    
    func handleURL(_ url: URL) {
        // Reset stack
        if !path.isEmpty { path.removeLast(path.count) }
        
        // Deep Link Handling
        switch url.host {
        case "weather":
            selectedTab = .weather
            weatherResetTrigger.toggle()
        case "steps": selectedTab = .steps
        case "alert": selectedTab = .alert(0)
        default: break
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @ObservedObject private var session = WatchSessionManager.shared
    
    var body: some View {
        TabView(selection: $navigationManager.selectedTab) {
            
            // PAGE 1: READINESS
            Group {
                if let readiness = session.readinessData,
                   let load = session.loadSummary {
                    ReadinessView(readiness: readiness, tsb: load.currentTSB)
                } else {
                    ContentUnavailableView("No Data", systemImage: "figure.strengthtraining.traditional")
                        .containerBackground(Color(red: 0.3, green: 0, blue: 0).gradient, for: .tabView)
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
                        .containerBackground(Color(red: 0, green: 0, blue: 0.3).gradient, for: .tabView)
                }
            }
            .tag(WatchTab.recovery)
            
            // PAGE 4: STEPS
            StepsDetailView()
                .tag(WatchTab.steps)
            
            // PAGE 5: WEATHER
            WeatherDetailView()
                .tag(WatchTab.weather)
            
            // PAGE 6+: DYNAMIC ALERTS
            // Check if array is empty
            if !session.weatherAlerts.isEmpty {
                // Enumerated loop to give each alert a unique index tag
                ForEach(Array(session.weatherAlerts.enumerated()), id: \.offset) { index, alert in
                    AlertView(alert: alert)
                        .tag(WatchTab.alert(index))
                }
            }
        }
        .tabViewStyle(.page)
        // FIX: Remove '$' from session.weatherAlerts
        // FIX: Ensure WeatherAlert conforms to Equatable (added extension above)
        .onChange(of: session.weatherAlerts) { oldValue, newValue in
            // Logic: If we have alerts, and the first one is severe, auto-switch to it
            if let firstAlert = newValue.first, firstAlert.severity == .severe {
                withAnimation {
                    // Only switch if we weren't already looking at an alert
                    // (Optional check to prevent annoyance while scrolling)
                    navigationManager.selectedTab = .alert(0)
                }
            }
        }
    }
}
