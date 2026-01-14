//
//  RideWeatherWatchApp.swift
//  RideWeatherWatch Watch App
//

import SwiftUI
import UserNotifications

@main
struct RideWeatherWatch_App: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // ✅ REQUEST PERMISSION ON LAUNCH
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

struct ContentView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    
    var body: some View {
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
        }
        .tabViewStyle(.page)
        .onAppear {
            print("⌚️ ContentView appeared. Readiness: \(session.readinessData?.readinessScore ?? -1), TSB: \(session.loadSummary?.currentTSB ?? -999)")
        }
    }
}
