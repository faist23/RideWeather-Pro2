//
//  RideWeatherWatchApp.swift
//  RideWeatherWatch Watch App
//
//  Updated with URL handling for complication taps
//

import SwiftUI
import UserNotifications
import Combine

@main
struct RideWeatherWatch_App: App {
    @StateObject private var navigationManager = NavigationManager()
    
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigationManager.path) {
                ContentView()
                    .navigationDestination(for: ComplicationDestination.self) { destination in
                        switch destination {
                        case .weather:
                            WeatherDetailView()
                        case .steps:
                            StepsDetailView()
                        }
                    }
            }
            .environmentObject(navigationManager)
            .onOpenURL { url in
                navigationManager.handleURL(url)
            }
            .onAppear {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        print("⌚️ Notification permission granted")
                    } else if let error = error {
                        print("⌚️ Notification permission error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

// MARK: - Navigation Manager

@MainActor
class NavigationManager: ObservableObject {
    @Published var path = NavigationPath()
    
    func handleURL(_ url: URL) {
        print("⌚️ Received URL: \(url.absoluteString)")
        print("⌚️ URL Host: \(url.host ?? "none")")
        
        // Clear existing path first
        path.removeLast(path.count)
        
        // Navigate based on URL
        switch url.host {
        case "weather":
            print("⌚️ Navigating to weather")
            path.append(ComplicationDestination.weather)
        case "steps":
            print("⌚️ Navigating to steps")
            path.append(ComplicationDestination.steps)
        default:
            print("⌚️ Unknown destination: \(url.host ?? "none")")
        }
    }
}

enum ComplicationDestination: Hashable, Identifiable {
    case weather
    case steps
    
    var id: Self { self }
}

struct ContentView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @State private var showingAlertDetails = false
    
    var body: some View {
        ZStack {
            TabView {
                // PAGE 1: READINESS (The Decision Maker)
                if let readiness = session.readinessData,
                   let load = session.loadSummary {
                    ReadinessView(readiness: readiness, tsb: load.currentTSB)
                } else {
                    ContentUnavailableView(
                        "No Readiness Data",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Open iPhone app to sync")
                    )
                    .containerBackground(.gray.gradient, for: .tabView)
                }
                
                // PAGE 2: FORM (Training Load)
                if let load = session.loadSummary,
                   let weeklyProgress = session.weeklyProgress {
                    FormView(summary: load, weeklyProgress: weeklyProgress)
                } else {
                    ContentUnavailableView(
                        "No Form Data",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Open iPhone app to sync")
                    )
                    .containerBackground(.blue.gradient, for: .tabView)
                }
                
                // PAGE 3: RECOVERY
                if let recovery = session.recoveryStatus,
                   let wellness = session.currentWellness {
                    RecoveryView(recovery: recovery, wellness: wellness)
                } else {
                    ContentUnavailableView(
                        "No Recovery Data",
                        systemImage: "heart.slash",
                        description: Text("Open iPhone app to sync")
                    )
                    .containerBackground(.black.gradient, for: .tabView)
                }
                
                // PAGE 4: WEEKLY SUMMARY
                if let weekStats = session.weeklyStats {
                    WeeklyView(
                        weekStats: weekStats,
                        weatherAlert: session.weatherAlert
                    )
                } else {
                    ContentUnavailableView(
                        "No Weekly Data",
                        systemImage: "calendar",
                        description: Text("Open iPhone app to sync")
                    )
                    .containerBackground(.indigo.gradient, for: .tabView)
                }
                
                // PAGE 5: DEBUG
                WatchDebugView()
                    .containerBackground(.black.gradient, for: .tabView)
            }
            .tabViewStyle(.page)
            
            // Global Alert Overlay
            if session.weatherAlert != nil {
                VStack {
                    Button {
                        showingAlertDetails = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("ALERT")
                                .font(.caption2)
                                .fontWeight(.black)
                        }
                        .foregroundStyle(.black)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                        .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    
                    Spacer()
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingAlertDetails) {
            if let alert = session.weatherAlert {
                ScrollView {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.yellow)
                        Text(alert.message)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("Check phone for details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
