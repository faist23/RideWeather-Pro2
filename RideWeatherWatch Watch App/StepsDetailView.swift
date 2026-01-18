//
//  StepsDetailView.swift
//  RideWeatherWatch Watch App
//

import SwiftUI

struct StepsDetailView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // HEADER
                Text("DAILY ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                
                if let wellness = session.currentWellness {
                    // MAIN STEP COUNT
                    VStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        
                        Text("\(wellness.steps ?? 0)")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                        
                        Text("steps today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // ACTIVITY METRICS
                    VStack(spacing: 8) {
                        if let activeEnergy = wellness.activeEnergyBurned {
                            DetailRow(
                                icon: "flame.fill",
                                label: "Active Calories",
                                value: "\(Int(activeEnergy)) cal",
                                color: .red
                            )
                        }
                        
                        if let score = wellness.activityScore {
                            DetailRow(
                                icon: "chart.bar.fill",
                                label: "Activity Score",
                                value: "\(Int(score))",
                                color: .green
                            )
                        }
                        
                        if let sleep = wellness.totalSleep {
                            let hours = sleep / 3600
                            DetailRow(
                                icon: "bed.double.fill",
                                label: "Last Night's Sleep",
                                value: String(format: "%.1fh", hours),
                                color: .blue
                            )
                        }
                        
                        if let rhr = wellness.restingHeartRate {
                            DetailRow(
                                icon: "heart.fill",
                                label: "Resting Heart Rate",
                                value: "\(rhr) bpm",
                                color: .pink
                            )
                        }
                    }
                    
                    // MOVEMENT INSIGHT
                    VStack(spacing: 6) {
                        Text("TODAY'S MOVEMENT")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        
                        Text(activityAdvice(steps: wellness.steps ?? 0))
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                    }
                    .padding(.top, 8)
                    
                } else {
                    ContentUnavailableView(
                        "No Activity Data",
                        systemImage: "figure.walk",
                        description: Text("Sync from iPhone")
                    )
                }
            }
            .padding()
        }
        .containerBackground(.green.gradient, for: .navigation)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func activityAdvice(steps: Int) -> String {
        switch steps {
        case 0..<3000:
            return "Light activity day - consider a short walk"
        case 3000..<7000:
            return "Moderate activity - you're moving well"
        case 7000..<10000:
            return "Great job! Almost at 10k steps"
        case 10000..<15000:
            return "Excellent activity level today!"
        default:
            return "Outstanding! You're crushing it today!"
        }
    }
}

// MARK: - Shared Detail Row Component

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Weather Detail") {
    NavigationStack {
        WeatherDetailView()
    }
}

#Preview("Steps Detail") {
    NavigationStack {
        StepsDetailView()
    }
}
