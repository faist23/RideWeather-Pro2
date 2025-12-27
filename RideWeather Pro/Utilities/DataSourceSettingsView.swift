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
    @State private var shouldShowAutoConfig = false

    var body: some View {
        Form {
            // MARK: - Active Configuration Summary
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
//        .onAppear {
//            generateRecommendations()
//        }
        .onChange(of: stravaService.isAuthenticated) { _, _ in
            // Just mark that we need to regenerate, don't auto-show
            recommendedConfig = nil
        }
        .onChange(of: garminService.isAuthenticated) { _, _ in
            recommendedConfig = nil
        }
        .onChange(of: healthManager.isAuthorized) { _, _ in
            recommendedConfig = nil
        }
        .onChange(of: dataSourceManager.configuration.trainingLoadSource) { oldValue, newValue in
            if newValue == .appleHealth && !healthManager.isAuthorized {
                Task {
                    let authorized = await healthManager.requestAuthorization()
                    if authorized {
                        NotificationCenter.default.post(name: .dataSourceChanged, object: nil)
                    }
                }
            } else {
                NotificationCenter.default.post(name: .dataSourceChanged, object: nil)
            }
        }
        // FIXED: Properly unwrap optional before passing to sheet
        .sheet(item: $recommendedConfig) { recommended in
            AutoConfigurationSheet(
                recommended: recommended,
                onApply: {
                    applyAutoConfiguration()
                    recommendedConfig = nil  // Dismiss by setting to nil
                },
                onCancel: {
                    recommendedConfig = nil  // Dismiss by setting to nil
                }
            )
            .presentationDetents([.fraction(0.7), .large])  // 70% of screen or large
        }
    }
    
    // MARK: - Active Configuration Section
    
    private var activeConfigurationSection: some View {
        Section {
            HStack(spacing: 0) {
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
                
                Divider()
                    .frame(height: 30)
                    .padding(.horizontal, 8)
                
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
            Text("Connection Status")
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
                HStack {
                    DataSourceOptionRow(
                        source: source,
                        isSelected: dataSourceManager.configuration.trainingLoadSource == source,
                        isAvailable: isTrainingSourceAvailable(source),
                        onSelect: {
                            handleSourceChange(to: source)
                        }
                    )
                    
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
    
    private func handleSourceChange(to source: DataSourceConfiguration.TrainingLoadSource) {
        withAnimation { verifyingSource = source }
        
        Task {
            dataSourceManager.configuration.trainingLoadSource = source
            dataSourceManager.saveConfiguration()
            
            if source == .appleHealth && !healthManager.isAuthorized {
                _ = await healthManager.requestAuthorization()
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            await performInitialSync(for: source)
            
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
                // Generate recommendations
                generateRecommendations()
                // Explicitly show the sheet
                shouldShowAutoConfig = true
            } label: {
                Label("Auto-Configure from Connections", systemImage: "wand.and.stars")
            }
            
            NavigationLink(destination: IntegrationsSettingsView()) {
                Label("Manage Connections", systemImage: "link")
            }
        } header: {
            Text("Quick Actions")
        } footer: {
            Text("Auto-configure analyzes your connected services and suggests optimal data sources.")
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
        print("📊 Generated recommendations: Training=\(recommendedConfig?.trainingLoadSource.rawValue ?? "nil"), Wellness=\(recommendedConfig?.wellnessSource.rawValue ?? "nil")")
    }
    
    private func applyRecommendedConfiguration() {
        guard let recommended = recommendedConfig else { return }
        
        dataSourceManager.configuration.trainingLoadSource = recommended.trainingLoadSource
        dataSourceManager.configuration.wellnessSource = recommended.wellnessSource
        dataSourceManager.configuration.detectedEcosystem = recommended.detectedEcosystem
        dataSourceManager.saveConfiguration()
    }
    
    private func applyAutoConfiguration() {
        guard let recommended = recommendedConfig else { return }
        
        dataSourceManager.configuration.trainingLoadSource = recommended.trainingLoadSource
        dataSourceManager.configuration.wellnessSource = recommended.wellnessSource
        dataSourceManager.configuration.detectedEcosystem = recommended.detectedEcosystem
        dataSourceManager.saveConfiguration()
        
        NotificationCenter.default.post(name: .dataSourceChanged, object: nil)
        
        print("📊 Data Sources: Auto-configuration applied")
        print("   Training: \(dataSourceManager.configuration.trainingLoadSource.rawValue)")
        print("   Wellness: \(dataSourceManager.configuration.wellnessSource.rawValue)")
    }
    
    private func performInitialSync(for source: DataSourceConfiguration.TrainingLoadSource) async {
        guard source == .appleHealth else { return }
        
        let trainingSync = UnifiedTrainingLoadSync()
        
        await trainingSync.syncFromConfiguredSource(
            stravaService: stravaService,
            garminService: garminService,
            healthManager: healthManager,
            userFTP: 200,
            userLTHR: nil,
            startDate: Calendar.current.date(byAdding: .day, value: -90, to: Date())
        )
    }
}

// MARK: - Supporting Views (keep existing implementations)

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

struct RecommendationsSheetView: View {
    let recommended: RecommendedConfiguration
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Detected: \(recommended.detectedEcosystem.rawValue)")
                            .font(.headline)
                    }
                    .padding()
                    
                    Divider()
                    
                    RecommendationCard(
                        title: "Training Load",
                        source: recommended.trainingLoadSource.rawValue,
                        icon: recommended.trainingLoadSource.icon,
                        reason: recommended.trainingLoadReason,
                        color: .blue
                    )
                    
                    RecommendationCard(
                        title: "Wellness Data",
                        source: recommended.wellnessSource.rawValue,
                        icon: recommended.wellnessSource.icon,
                        reason: recommended.wellnessReason,
                        color: .green
                    )
                    
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

// MARK: - Custom Auto-Configuration Sheet

struct AutoConfigurationSheet: View {
    let recommended: RecommendedConfiguration  // FIXED: Not optional
    let onApply: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Recommended Configuration")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Based on your connected services")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Recommendations
                VStack(spacing: 16) {
                    ConfigurationRow(
                        label: "Training Load",
                        value: recommended.trainingLoadSource.rawValue,
                        icon: recommended.trainingLoadSource.icon,
                        description: recommended.trainingLoadReason
                    )
                    
                    Divider()
                    
                    ConfigurationRow(
                        label: "Wellness",
                        value: recommended.wellnessSource.rawValue,
                        icon: recommended.wellnessSource.icon,
                        description: recommended.wellnessReason
                    )
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
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
                    
                    Button {
                        onCancel()
                    } label: {
                        Text("Keep My Current Settings")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

struct ConfigurationRow: View {
    let label: String
    let value: String
    let icon: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if icon.contains("_logo") {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.headline)
                }
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

extension Notification.Name {
    static let dataSourceChanged = Notification.Name("dataSourceChanged")
}
