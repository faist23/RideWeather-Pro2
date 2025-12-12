//
//  DataSourceSettingsView.swift
//  RideWeather Pro
//
//  Smart UI for configuring training and wellness data sources
//

import SwiftUI

struct DataSourceSettingsView: View {
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var healthManager: HealthKitManager
    
    @StateObject private var dataSourceManager = DataSourceManager.shared
    
    @State private var showingRecommendations = false
    @State private var recommendedConfig: RecommendedConfiguration?
    @State private var verifyingSource: DataSourceConfiguration.TrainingLoadSource? = nil
    
    var body: some View {
        Form {
            // MARK: - NEW: Active Configuration Summary
            // This clears up the confusion about "What is powering what?"
            activeConfigurationSection
            
            // Status Overview
            connectionStatusSection
            
            // Smart Recommendations
            if !configStatus.isValid || configStatus.hasWarnings {
                recommendationsSection
            }
            
            // Training Load Source
            trainingLoadSourceSection
            
            // Wellness Source
            wellnessSourceSection
            
            // Quick Actions
            quickActionsSection
        }
        .navigationTitle("Data Sources")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            generateRecommendations()
        }
        .onChange(of: stravaService.isAuthenticated) { _, _ in
            generateRecommendations()
        }
        .onChange(of: garminService.isAuthenticated) { _, _ in
            generateRecommendations()
        }
        .onChange(of: healthManager.isAuthorized) { _, _ in
            generateRecommendations()
        }
        .onChange(of: dataSourceManager.configuration.trainingLoadSource) { oldValue, newValue in
            // When source changes, request permissions if needed
            if newValue == .appleHealth && !healthManager.isAuthorized {
                Task {
                    let authorized = await healthManager.requestAuthorization()
                    if authorized {
                        // Post notification to trigger sync in TrainingLoadView
                        NotificationCenter.default.post(name: .dataSourceChanged, object: nil)
                    }
                }
            } else {
                // Post notification for other sources
                NotificationCenter.default.post(name: .dataSourceChanged, object: nil)
            }
        }
    }
    
    // MARK: - Active Configuration Section
    
    private var activeConfigurationSection: some View {
        Section {
            HStack(spacing: 0) {
                // Training Load Config
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRAINING LOAD")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        SourceIconView(icon: dataSourceManager.configuration.trainingLoadSource.icon)
                        Text(dataSourceManager.configuration.trainingLoadSource.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Vertical Divider
                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 8)
                
                // Wellness Config
                VStack(alignment: .leading, spacing: 4) {
                    Text("WELLNESS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        SourceIconView(icon: dataSourceManager.configuration.wellnessSource.icon, isWellness: true)
                        Text(dataSourceManager.configuration.wellnessSource.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Active Configuration")
        }
    }
    
    // MARK: - Connection Status Section
    
    private var connectionStatusSection: some View {
        Section {
            ConnectionStatusRow(
                title: "Strava",
                isConnected: stravaService.isAuthenticated,
                icon: "strava_logo",
                color: .orange
            )
            
            ConnectionStatusRow(
                title: "Apple Health",
                isConnected: healthManager.isAuthorized,
                icon: "heart.fill",
                color: .red
            )
            
            ConnectionStatusRow(
                title: "Garmin",
                isConnected: garminService.isAuthenticated,
                icon: "garmin_logo",
                color: .blue
            )
            
            if let ecosystem = dataSourceManager.configuration.detectedEcosystem {
                HStack {
                    Image(systemName: "applewatch")
                        .foregroundColor(.secondary)
                    Text("Detected: \(ecosystem.rawValue)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Connection Status") // Renamed for clarity
        } footer: {
            Text("Connect services here to make them available as sources.")
        }
    }
    
    // MARK: - Recommendations Section
    
    private var recommendationsSection: some View {
        Section {
            if !configStatus.isValid {
                ForEach(configStatus.issues, id: \.self) { issue in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(issue)
                            .font(.subheadline)
                    }
                }
            }
            
            if configStatus.hasWarnings {
                ForEach(configStatus.warnings, id: \.self) { warning in
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                        Text(warning)
                            .font(.subheadline)
                    }
                }
            }
            
            if let recommended = recommendedConfig,
               (recommended.trainingLoadSource != dataSourceManager.configuration.trainingLoadSource ||
                recommended.wellnessSource != dataSourceManager.configuration.wellnessSource) {
                
                Button {
                    applyRecommendedConfiguration()
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Apply Recommended Settings")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .sheet(isPresented: $showingRecommendations) {
                    RecommendationsSheetView(
                        recommended: recommended,
                        onApply: {
                            applyRecommendedConfiguration()
                            showingRecommendations = false
                        }
                    )
                }
            }
        } header: {
            Text(configStatus.isValid ? "Suggestions" : "Configuration Issues")
        }
    }
    
    // MARK: - Training Load Source Section
    
    private var trainingLoadSourceSection: some View {
        Section {
            ForEach(DataSourceConfiguration.TrainingLoadSource.allCases) { source in
                HStack { // Wrap in HStack to add the spinner
                    DataSourceOptionRow(
                        source: source,
                        isSelected: dataSourceManager.configuration.trainingLoadSource == source,
                        isAvailable: isTrainingSourceAvailable(source),
                        onSelect: {
                            handleSourceChange(to: source)
                        }
                    )
                    
                    // ✅ SHOW SPINNER IF VERIFYING THIS SOURCE
                    if verifyingSource == source {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 8)
                    }
                }
            }
        } header: {
            Text("Training Load Source")
        } footer: {
            Text(dataSourceManager.configuration.trainingLoadSource.description)
                .font(.caption)
        }
    }
    
    // ✅ NEW HELPER FUNCTION TO HANDLE THE TRANSITION
    private func handleSourceChange(to source: DataSourceConfiguration.TrainingLoadSource) {
        // 1. Set Transition State
        withAnimation { verifyingSource = source }
        
        Task {
            // 2. Perform the logic
            dataSourceManager.configuration.trainingLoadSource = source
            dataSourceManager.saveConfiguration()
            
            if source == .appleHealth && !healthManager.isAuthorized {
                _ = await healthManager.requestAuthorization()
            }
            
            // Simulate a short "check" or perform actual sync
            // This small delay feels "pro" - like the app is actually checking connections
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await performInitialSync(for: source)
            
            // 3. Clear Transition State
            await MainActor.run {
                withAnimation { verifyingSource = nil }
                NotificationCenter.default.post(name: .dataSourceChanged, object: nil)
            }
        }
    }
    
    // MARK: - Wellness Source Section
    
    private var wellnessSourceSection: some View {
        Section {
            ForEach(DataSourceConfiguration.WellnessSource.allCases) { source in
                WellnessSourceOptionRow(
                    source: source,
                    isSelected: dataSourceManager.configuration.wellnessSource == source,
                    isAvailable: isWellnessSourceAvailable(source),
                    onSelect: {
                        dataSourceManager.configuration.wellnessSource = source
                        dataSourceManager.saveConfiguration()
                    }
                )
            }
        } header: {
            Text("Wellness Data Source")
        } footer: {
            Text(dataSourceManager.configuration.wellnessSource.description)
                .font(.caption)
        }
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        Section {
            Button {
                dataSourceManager.autoConfigureFromConnections(
                    stravaConnected: stravaService.isAuthenticated,
                    healthConnected: healthManager.isAuthorized,
                    garminConnected: garminService.isAuthenticated
                )
            } label: {
                Label("Auto-Configure from Connections", systemImage: "wand.and.stars")
            }
            
            NavigationLink(destination: IntegrationsSettingsView()) {
                Label("Manage Connections", systemImage: "link")
            }
        } header: {
            Text("Quick Actions")
        }
    }
    
    // MARK: - Helper Methods
    
    private var configStatus: ConfigurationStatus {
        dataSourceManager.validateConfiguration(
            stravaConnected: stravaService.isAuthenticated,
            healthConnected: healthManager.isAuthorized,
            garminConnected: garminService.isAuthenticated
        )
    }
    
    private func isTrainingSourceAvailable(_ source: DataSourceConfiguration.TrainingLoadSource) -> Bool {
        switch source {
        case .strava: return stravaService.isAuthenticated
        case .appleHealth: return healthManager.isAuthorized
        case .garmin: return garminService.isAuthenticated
        case .manual: return true
        }
    }
    
    private func isWellnessSourceAvailable(_ source: DataSourceConfiguration.WellnessSource) -> Bool {
        switch source {
        case .appleHealth: return healthManager.isAuthorized
        case .garmin: return garminService.isAuthenticated
        case .none: return true
        }
    }
    
    private func generateRecommendations() {
        recommendedConfig = dataSourceManager.getRecommendedConfiguration(
            stravaConnected: stravaService.isAuthenticated,
            healthConnected: healthManager.isAuthorized,
            garminConnected: garminService.isAuthenticated
        )
    }
    
    private func applyRecommendedConfiguration() {
        guard let recommended = recommendedConfig else { return }
        
        dataSourceManager.configuration.trainingLoadSource = recommended.trainingLoadSource
        dataSourceManager.configuration.wellnessSource = recommended.wellnessSource
        dataSourceManager.configuration.detectedEcosystem = recommended.detectedEcosystem
        dataSourceManager.saveConfiguration()
    }
    
    private func performInitialSync(for source: DataSourceConfiguration.TrainingLoadSource) async {
        guard source == .appleHealth else { return }
        
        let trainingSync = UnifiedTrainingLoadSync()
        
        await trainingSync.syncFromConfiguredSource(
            stravaService: stravaService,
            garminService: garminService,
            healthManager: healthManager,
            userFTP: 200, // You'll need to pass this from settings
            userLTHR: nil,
            startDate: Calendar.current.date(byAdding: .day, value: -90, to: Date())
        )
    }
}

// MARK: - Helper View: Source Icon

struct SourceIconView: View {
    let icon: String
    var isWellness: Bool = false
    
    var body: some View {
        if icon.contains("_logo") {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isWellness ? .red : .blue)
        }
    }
}

// MARK: - Connection Status Row

struct ConnectionStatusRow: View {
    let title: String
    let isConnected: Bool
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            if icon.contains("_logo") {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 24)
            }
            
            Text(title)
            
            Spacer()
            
            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
                Text("Not Connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Data Source Option Row

struct DataSourceOptionRow: View {
    let source: DataSourceConfiguration.TrainingLoadSource
    let isSelected: Bool
    let isAvailable: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: {
            if isAvailable {
                onSelect()
            }
        }) {
            HStack(spacing: 12) {
                if source.icon.contains("_logo") {
                    Image(source.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: source.icon)
                        .font(.title3)
                        .frame(width: 28)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.rawValue)
                        .font(.body)
                        .foregroundColor(isAvailable ? .primary : .secondary)
                    
                    if !isAvailable && source.requiresConnection {
                        Text("Not connected")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1.0 : 0.6)
    }
}

// MARK: - Wellness Source Option Row

struct WellnessSourceOptionRow: View {
    let source: DataSourceConfiguration.WellnessSource
    let isSelected: Bool
    let isAvailable: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: {
            if isAvailable {
                onSelect()
            }
        }) {
            HStack(spacing: 12) {
                if source.icon.contains("_logo") {
                    Image(source.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: source.icon)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundColor(source == .none ? .secondary : .red)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.rawValue)
                        .font(.body)
                        .foregroundColor(isAvailable ? .primary : .secondary)
                    
                    if !isAvailable && source.requiresConnection {
                        Text("Not connected")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1.0 : 0.6)
    }
}

// MARK: - Recommendations Sheet

struct RecommendationsSheetView: View {
    let recommended: RecommendedConfiguration
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Detected Ecosystem
                    VStack(spacing: 12) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Detected: \(recommended.detectedEcosystem.rawValue)")
                            .font(.headline)
                    }
                    .padding()
                    
                    Divider()
                    
                    // Training Load Recommendation
                    RecommendationCard(
                        title: "Training Load",
                        source: recommended.trainingLoadSource.rawValue,
                        icon: recommended.trainingLoadSource.icon,
                        reason: recommended.trainingLoadReason,
                        color: .blue
                    )
                    
                    // Wellness Recommendation
                    RecommendationCard(
                        title: "Wellness Data",
                        source: recommended.wellnessSource.rawValue,
                        icon: recommended.wellnessSource.icon,
                        reason: recommended.wellnessReason,
                        color: .green
                    )
                    
                    // Apply Button
                    Button {
                        onApply()
                    } label: {
                        Text("Apply These Settings")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Recommended Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RecommendationCard: View {
    let title: String
    let source: String
    let icon: String
    let reason: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if icon.contains("_logo") {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(source)
                        .font(.headline)
                }
                
                Spacer()
            }
            
            Text(reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DataSourceSettingsView()
            .environmentObject(StravaService())
            .environmentObject(GarminService())
            .environmentObject(HealthKitManager())
    }
}

extension Notification.Name {
    static let dataSourceChanged = Notification.Name("dataSourceChanged")
}
