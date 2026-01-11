//
//  RideWeatherWatchApp.swift
//  RideWeatherWatch Watch App
//
//  Created by Craig Faist on 1/10/26.
//

import SwiftUI

@main
struct RideWeatherWatch_App: App {
    @StateObject private var session = WatchSessionManager.shared
    
    var body: some Scene {
        WindowGroup {
            TabView {
                // PAGE 1: TRAINING LOAD
                if let load = session.loadSummary {
                    LoadDashboardView(summary: load)
                        .containerBackground(.blue.gradient, for: .tabView)
                } else {
                    ContentUnavailableView("No Load Data", systemImage: "chart.bar.xaxis", description: Text("Complete a ride to see stats"))
                        .containerBackground(.blue.gradient, for: .tabView)
                }
                
                // PAGE 2: WELLNESS (RECOVERY)
                if let wellness = session.wellnessSummary {
                    WellnessRingView(summary: wellness)
                        .containerBackground(.black.gradient, for: .tabView)
                } else {
                    // Show this empty state instead of hiding the tab
                    ContentUnavailableView("No Wellness", systemImage: "heart.slash", description: Text("Open iPhone app to sync"))
                        .containerBackground(.black.gradient, for: .tabView)
                }
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
