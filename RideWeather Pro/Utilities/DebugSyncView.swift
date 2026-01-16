//
//  DebugSyncView.swift
//  RideWeather Pro
//
//  Add this view to your iPhone app to manually trigger and verify sync
//

import SwiftUI

struct DebugSyncView: View {
    @StateObject private var healthKit = HealthKitManager()
    @State private var syncLog: [String] = []
    @State private var lastSyncTime: Date?
    
    var body: some View {
        List {
            Section("Current Data") {
                if let summary = TrainingLoadManager.shared.getCurrentSummary() {
                    LabeledContent("TSB", value: String(format: "%.1f", summary.currentTSB))
                    LabeledContent("CTL", value: String(format: "%.1f", summary.currentCTL))
                    LabeledContent("ATL", value: String(format: "%.1f", summary.currentATL))
                    LabeledContent("Status", value: summary.formStatus.rawValue)
                } else {
                    Text("No Training Load Data")
                        .foregroundStyle(.secondary)
                }
                
                if let wellness = WellnessManager.shared.currentSummary {
                    LabeledContent("Avg Steps", value: wellness.averageSteps.map { "\(Int($0))" } ?? "—")
                    LabeledContent("Avg Sleep", value: wellness.averageSleepHours.map { String(format: "%.1fh", $0) } ?? "—")
                } else {
                    Text("No Wellness Data")
                        .foregroundStyle(.secondary)
                }
                
                LabeledContent("Readiness", value: "\(healthKit.readiness.readinessScore)")
                if let hrv = healthKit.readiness.latestHRV {
                    LabeledContent("HRV", value: String(format: "%.0fms", hrv))
                }
            }
            
            Section("Sync Control") {
                Button("Force Full Sync to Watch") {
                    forceSyncToWatch()
                }
                .buttonStyle(.bordered)
                
                if let lastSync = lastSyncTime {
                    Text("Last sync: \(lastSync.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Sync Log") {
                ForEach(syncLog.indices.reversed(), id: \.self) { index in
                    Text(syncLog[index])
                        .font(.caption)
                        .monospaced()
                }
            }
        }
        .navigationTitle("Watch Sync Debug")
        .task {
            await healthKit.fetchReadinessData()
        }
    }
    
    private func forceSyncToWatch() {
        syncLog.append("[\(Date().formatted(date: .omitted, time: .standard))] Starting force sync...")
        
        Task { @MainActor in
            // 1. Fetch fresh data
            let trainingLoadSummary = TrainingLoadManager.shared.getCurrentSummary()
            let wellnessSummary = WellnessManager.shared.currentSummary
            let currentWellness = WellnessManager.shared.dailyMetrics.first { 
                Calendar.current.isDateInToday($0.date) 
            }
            let readiness = healthKit.readiness
            
            // 2. Log what we're sending
            if let tl = trainingLoadSummary {
                syncLog.append("  📱 Training: TSB=\(String(format: "%.1f", tl.currentTSB)), CTL=\(String(format: "%.1f", tl.currentCTL)), ATL=\(String(format: "%.1f", tl.currentATL))")
            } else {
                syncLog.append("  ⚠️ No Training Load Summary")
            }
            
            if let ws = wellnessSummary {
                syncLog.append("  📱 Wellness: Steps=\(ws.averageSteps.map { "\(Int($0))" } ?? "—"), Sleep=\(ws.averageSleepHours.map { String(format: "%.1f", $0) } ?? "—")h")
            } else {
                syncLog.append("  ⚠️ No Wellness Summary")
            }
            
            if currentWellness != nil {
                syncLog.append("  📱 Current Wellness: ✓")
            } else {
                syncLog.append("  ⚠️ No Current Wellness")
            }
            
            syncLog.append("  📱 Readiness: \(readiness.readinessScore)")
            
            // 3. Force sync
            PhoneSessionManager.shared.forceFullSync(
                trainingLoadSummary: trainingLoadSummary,
                wellnessSummary: wellnessSummary,
                currentWellness: currentWellness,
                readiness: readiness
            )
            
            lastSyncTime = Date()
            syncLog.append("  ✅ Sync command sent to PhoneSessionManager")
        }
    }
}

#Preview {
    NavigationStack {
        DebugSyncView()
    }
}
