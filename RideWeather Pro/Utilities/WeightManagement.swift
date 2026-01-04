//
//  WeightManagement.swift
//  RideWeather Pro
//
//  Apple-style weight management UI with wellness source alignment
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
    @State private var showConflictAlert = false
    @State private var pendingSource: AppSettings.WeightSource?
    
    private var wellnessSource: DataSourceConfiguration.WellnessSource {
        DataSourceManager.shared.configuration.wellnessSource
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Show wellness source info if there's a potential conflict
                if wellnessSource != .none {
                    Section {
                        WellnessSourceInfoBanner(wellnessSource: wellnessSource)
                    }
                }
                
                // Automatic Sync Options
                Section {
                    if healthConnected {
                        WeightSourceOption(
                            icon: "heart.fill",
                            color: .red,
                            title: "Apple Health",
                            subtitle: getSubtitle(for: .healthKit),
                            isSelected: currentSource == .healthKit,
                            isConnected: true,
                            showWarning: shouldWarn(for: .healthKit)
                        ) {
                            await selectSourceWithValidation(.healthKit)
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
                            subtitle: getSubtitle(for: .garmin),
                            isSelected: currentSource == .garmin,
                            isConnected: true,
                            showWarning: shouldWarn(for: .garmin)
                        ) {
                            await selectSourceWithValidation(.garmin)
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
                            isConnected: true,
                            showWarning: false
                        ) {
                            await selectSourceWithValidation(.strava)
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
                        isConnected: true,
                        showWarning: false
                    ) {
                        await selectSourceWithValidation(.manual)
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
            .alert("Weight Source Mismatch", isPresented: $showConflictAlert) {
                Button("Use Anyway") {
                    if let source = pendingSource {
                        Task { await selectSource(source) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingSource = nil
                }
            } message: {
                Text(getConflictMessage())
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Helper Methods
    
    private func getSubtitle(for source: AppSettings.WeightSource) -> String {
        switch source {
        case .healthKit:
            if wellnessSource == .appleHealth {
                return "✓ Matches your wellness data source"
            } else {
                return "Automatically syncs from Health app"
            }
        case .garmin:
            if wellnessSource == .garmin {
                return "✓ Matches your wellness data source"
            } else {
                return "Syncs from Garmin Connect wellness data"
            }
        case .strava:
            return "Syncs from your Strava athlete profile"
        case .manual:
            return "Set and update weight manually"
        }
    }
    
    private func shouldWarn(for source: AppSettings.WeightSource) -> Bool {
        switch wellnessSource {
        case .garmin:
            return source == .healthKit
        case .appleHealth:
            return source == .garmin
        case .none:
            return false
        }
    }
    
    private func getConflictMessage() -> String {
        guard let pending = pendingSource else { return "" }
        
        switch wellnessSource {
        case .garmin:
            if pending == .healthKit {
                return "Your wellness data (sleep, HRV, etc.) comes from Garmin, but you're selecting Apple Health for weight. This may cause inconsistent data. Consider using Garmin for both, or change your wellness source in Data Sources settings."
            }
        case .appleHealth:
            if pending == .garmin {
                return "Your wellness data (sleep, HRV, etc.) comes from Apple Health, but you're selecting Garmin for weight. This may cause inconsistent data. Consider using Apple Health for both, or change your wellness source in Data Sources settings."
            }
        case .none:
            break
        }
        
        return "Using different sources for weight and wellness data may cause inconsistencies."
    }
    
    private func selectSourceWithValidation(_ source: AppSettings.WeightSource) async {
        // Check if this creates a mismatch with wellness source
        let hasConflict = shouldWarn(for: source)
        
        if hasConflict {
            pendingSource = source
            showConflictAlert = true
        } else {
            await selectSource(source)
        }
    }
    
    private func selectSource(_ source: AppSettings.WeightSource) async {
        isSyncing = true
        syncStatus = nil
        
        currentSource = source
        
        // Mark that user has explicitly chosen a weight source
        UserDefaults.standard.set(true, forKey: "hasUserSetWeightSource")
        
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

// MARK: - Wellness Source Info Banner

struct WellnessSourceInfoBanner: View {
    let wellnessSource: DataSourceConfiguration.WellnessSource
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Wellness Data Source")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Currently using \(wellnessSource.rawValue)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
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
    let showWarning: Bool
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
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        if showWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(showWarning ? .orange : .secondary)
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
