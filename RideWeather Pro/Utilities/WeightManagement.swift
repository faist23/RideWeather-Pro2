//
//  WeightManagement.swift
//  RideWeather Pro
//
//  Apple-style weight management UI
//

import SwiftUI

// MARK: - Weight Source Picker Sheet

struct WeightSourcePickerSheet: View {
    @Binding var currentSource: AppSettings.WeightSource
    @Binding var settings: AppSettings
    @Environment(\.dismiss) var dismiss
    
    let healthConnected: Bool
    let stravaConnected: Bool
    let garminConnected: Bool
    let onSourceChanged: (AppSettings.WeightSource) async -> Void
    
    @State private var isSyncing = false
    @State private var syncStatus: String?
    
    var body: some View {
        NavigationStack {
            List {
                // Automatic Sync Options
                Section {
                    if healthConnected {
                        WeightSourceOption(
                            icon: "heart.fill",
                            color: .red,
                            title: "Apple Health",
                            subtitle: "Automatically syncs from Health app",
                            isSelected: currentSource == .healthKit,
                            isConnected: true
                        ) {
                            await selectSource(.healthKit)
                        }
                    } else {
                        DisconnectedSourceOption(
                            icon: "heart.fill",
                            color: .red,
                            title: "Apple Health",
                            subtitle: "Connect in Integrations to enable"
                        )
                    }
                    
                    if garminConnected {
                        WeightSourceOption(
                            icon: "figure.run.circle.fill",
                            color: .blue,
                            title: "Garmin",
                            subtitle: "Syncs from Garmin Connect wellness data",
                            isSelected: currentSource == .garmin,
                            isConnected: true
                        ) {
                            await selectSource(.garmin)
                        }
                    } else {
                        DisconnectedSourceOption(
                            icon: "figure.run.circle.fill",
                            color: .blue,
                            title: "Garmin",
                            subtitle: "Connect in Integrations to enable"
                        )
                    }
                    
                    if stravaConnected {
                        WeightSourceOption(
                            icon: "figure.run",
                            color: .orange,
                            title: "Strava Profile",
                            subtitle: "Syncs from your Strava athlete profile",
                            isSelected: currentSource == .strava,
                            isConnected: true
                        ) {
                            await selectSource(.strava)
                        }
                    } else {
                        DisconnectedSourceOption(
                            icon: "figure.run",
                            color: .orange,
                            title: "Strava",
                            subtitle: "Connect in Integrations to enable"
                        )
                    }
                } header: {
                    Text("Automatic Sync")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight will update automatically when you weigh yourself")
                        
                        if isSyncing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Syncing weight...")
                                    .font(.caption)
                            }
                        }
                        
                        if let status = syncStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                // Manual Option
                Section {
                    WeightSourceOption(
                        icon: "hand.raised.fill",
                        color: .purple,
                        title: "Manual Entry",
                        subtitle: "Set and update weight manually",
                        isSelected: currentSource == .manual,
                        isConnected: true
                    ) {
                        await selectSource(.manual)
                    }
                } header: {
                    Text("Manual")
                } footer: {
                    Text("Choose this if you weigh yourself infrequently or prefer to enter your weight manually")
                }
            }
            .navigationTitle("Weight Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func selectSource(_ source: AppSettings.WeightSource) async {
        isSyncing = true
        syncStatus = nil
        
        currentSource = source
        await onSourceChanged(source)
        
        // Show success message briefly
        if source != .manual {
            let weight = settings.bodyWeightInUserUnits
            let unit = settings.units.weightSymbol
            syncStatus = "✓ Weight synced: \(String(format: "%.1f", weight)) \(unit)"
        }
        
        isSyncing = false
        
        // Auto-dismiss after success
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        dismiss()
    }
}

// MARK: - Weight Source Option Button

struct WeightSourceOption: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isConnected: Bool
    let action: () async -> Void
    
    @State private var isProcessing = false
    
    var body: some View {
        Button {
            Task {
                isProcessing = true
                await action()
                isProcessing = false
            }
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection indicator or spinner
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(!isConnected)
    }
}

// MARK: - Disconnected Source Option

struct DisconnectedSourceOption: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon (grayed out)
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Info icon
            Image(systemName: "info.circle")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}
