//
//  WatchDebugView.swift
//  RideWeatherWatch Watch App
//
//  Add this as a new tab in your Watch app to see what data was received
//

import SwiftUI

struct WatchDebugView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Received Data")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                // SYNC TIMESTAMP
                if let lastUpdate = session.lastContextUpdate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last Update")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(lastUpdate, style: .relative)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                        Text(lastUpdate.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                } else {
                    Text("No data received yet")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.bottom, 8)
                }
                
                // TRAINING LOAD
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRAINING LOAD")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let load = session.loadSummary {
                        DebugDataRow("TSB", String(format: "%.1f", load.currentTSB))
                        DebugDataRow("CTL", String(format: "%.1f", load.currentCTL))
                        DebugDataRow("ATL", String(format: "%.1f", load.currentATL))
                        DebugDataRow("Status", load.formStatus.rawValue)
                    } else {
                        Text("❌ No data")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(.bottom, 8)
                
                // WELLNESS
                VStack(alignment: .leading, spacing: 4) {
                    Text("WELLNESS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let wellness = session.wellnessSummary {
                        DebugDataRow("Avg Steps", wellness.averageSteps.map { "\(Int($0))" } ?? "—")
                        DebugDataRow("Avg Sleep", wellness.averageSleepHours.map { String(format: "%.1fh", $0) } ?? "—")
                        DebugDataRow("Sleep Debt", wellness.sleepDebt.map { String(format: "%.1fh", $0) } ?? "—")
                    } else {
                        Text("❌ No data")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(.bottom, 8)
                
                // READINESS
                VStack(alignment: .leading, spacing: 4) {
                    Text("READINESS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let readiness = session.readinessData {
                        DebugDataRow("Score", "\(readiness.readinessScore)")
                        DebugDataRow("HRV", readiness.latestHRV.map { String(format: "%.0fms", $0) } ?? "—")
                        DebugDataRow("RHR", readiness.latestRHR.map { String(format: "%.0f", $0) } ?? "—")
                        DebugDataRow("Sleep", readiness.sleepDuration.map { formatDuration($0) } ?? "—")
                    } else {
                        Text("❌ No data")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(.bottom, 8)
                
                // HISTORY
                VStack(alignment: .leading, spacing: 4) {
                    Text("HISTORY")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    DebugDataRow("Training Days", "\(session.trainingHistory.count)")
                    DebugDataRow("Wellness Days", "\(session.wellnessHistory.count)")
                }
                .padding(.bottom, 8)
                
                // COMPUTED
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMPUTED")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let recovery = session.recoveryStatus {
                        DebugDataRow("Recovery %", "\(recovery.recoveryPercent)")
                    }
                    
                    if session.weeklyProgress != nil {
                        DebugDataRow("Weekly Progress", "✓")
                    }
                    
/*                    if let stats = session.weeklyStats {
                        DebugDataRow("Week Rides", "\(stats.rideCount)")
                        DebugDataRow("Week Hours", String(format: "%.1f", stats.totalHours))
                        DebugDataRow("CTL Change", String(format: "%.1f", stats.fitnessChange))
                    } */
                }
            }
            .padding()
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

struct DebugDataRow: View {
    let label: String
    let value: String
    
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    WatchDebugView()
}
