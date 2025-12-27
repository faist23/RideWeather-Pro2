//
//  DataSourceSettings.swift
//  RideWeather Pro
//
//  Smart data source management for training & wellness
//

import Foundation
import SwiftUI
import Combine

// MARK: - Data Source Configuration

struct DataSourceConfiguration: Codable, Equatable {
    
    // MARK: - Training Load Source
    var trainingLoadSource: TrainingLoadSource = .strava
    
    // MARK: - Wellness Source
    var wellnessSource: WellnessSource = .appleHealth
    
    // MARK: - Auto-detected ecosystem
    var detectedEcosystem: WatchEcosystem?
    
    enum TrainingLoadSource: String, CaseIterable, Identifiable, Codable {
        case strava = "Strava"
        case appleHealth = "Apple Health"
        case garmin = "Garmin"
        case manual = "Manual Entry"
        
        var id: String { rawValue }
        
        var description: String {
            switch self {
            case .strava:
                return "Best for multi-platform users. Accurate TSS from power/HR data across all your devices"
            case .appleHealth:
                return "Works with Apple Watch workouts and imported activities (Strava, Garmin, etc.). Can include power data"
            case .garmin:
                return "Best for Garmin ecosystem users. Native integration with Garmin Connect activities"
            case .manual:
                return "Manually log training sessions when automatic tracking isn't available"
            }
        }
        
        var icon: String {
            switch self {
            case .strava: return "strava_logo"
            case .appleHealth: return "heart.fill"
            case .garmin: return "garmin_logo"
            case .manual: return "pencil.circle.fill"
            }
        }
        
        var requiresConnection: Bool {
            self != .manual
        }
    }
    
    enum WellnessSource: String, CaseIterable, Identifiable, Codable {
        case appleHealth = "Apple Health"
        case garmin = "Garmin"
        case none = "None"
        
        var id: String { rawValue }
        
        var description: String {
            switch self {
            case .appleHealth:
                return "Full wellness tracking: steps, sleep stages, HRV, body composition"
            case .garmin:
                return "Wellness data from Garmin: steps, sleep, body battery, stress"
            case .none:
                return "Focus on training load only"
            }
        }
        
        var icon: String {
            switch self {
            case .appleHealth: return "heart.fill"
            case .garmin: return "garmin_logo"
            case .none: return "minus.circle"
            }
        }
        
        var requiresConnection: Bool {
            self != .none
        }
    }
    
    enum WatchEcosystem: String, Codable {
        case apple = "Apple Watch"
        case garmin = "Garmin"
        case none = "None"
    }
}

// MARK: - Data Source Manager

@MainActor
class DataSourceManager: ObservableObject {
    static let shared = DataSourceManager()
    
    @Published var configuration: DataSourceConfiguration
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "dataSourceConfiguration"
    
    private init() {
        // Load saved config
        if let data = userDefaults.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(DataSourceConfiguration.self, from: data) {
            configuration = decoded
        } else {
            configuration = DataSourceConfiguration()
        }
    }
    
    func saveConfiguration() {
        if let encoded = try? JSONEncoder().encode(configuration) {
            userDefaults.set(encoded, forKey: configKey)
        }
    }
    
    // MARK: - Smart Recommendations
    
    /// Analyzes connected services and suggests optimal configuration
    func getRecommendedConfiguration(
        stravaConnected: Bool,
        healthConnected: Bool,
        garminConnected: Bool
    ) -> RecommendedConfiguration {
        
        // Detect watch ecosystem
        let ecosystem = detectWatchEcosystem(
            healthConnected: healthConnected,
            garminConnected: garminConnected
        )
        
        // Determine training load source
        // Priority logic:
        // 1. Match the ecosystem (Garmin users likely have all data in Garmin)
        // 2. Strava for multi-platform users
        // 3. Apple Health (may have power data from imports)
        // 4. Manual fallback
        
        let trainingSource: DataSourceConfiguration.TrainingLoadSource
        let trainingReason: String
        
        // KEY INSIGHT: If user has Garmin wellness, they likely have Garmin training too
        if garminConnected && ecosystem == .garmin {
            trainingSource = .garmin
            trainingReason = "Garmin ecosystem detected. All your activities and wellness data are in one place"
        } else if stravaConnected && !garminConnected {
            // Only prefer Strava if Garmin ISN'T connected
            trainingSource = .strava
            trainingReason = "Strava works across platforms and typically has the most detailed activity data"
        } else if stravaConnected && healthConnected {
            // Both available - Strava slightly preferred for training accuracy
            trainingSource = .strava
            trainingReason = "Strava provides detailed power/HR analysis, complementing Apple Health wellness data"
        } else if healthConnected {
            trainingSource = .appleHealth
            trainingReason = "Apple Health can estimate training load from workouts and imported activities"
        } else {
            trainingSource = .manual
            trainingReason = "No connected services - manual entry available"
        }
        
        // Determine wellness source
        // Priority: match the ecosystem
        let wellnessSource: DataSourceConfiguration.WellnessSource
        let wellnessReason: String
        
        switch ecosystem {
        case .apple:
            wellnessSource = .appleHealth
            wellnessReason = "Apple Watch provides comprehensive wellness: sleep stages, HRV, and daily activity"
        case .garmin:
            wellnessSource = .garmin
            wellnessReason = "Garmin watches track Body Battery, stress, sleep, and recovery metrics"
        case .none:
            // No clear ecosystem - pick what's connected
            if healthConnected {
                wellnessSource = .appleHealth
                wellnessReason = "Apple Health can provide wellness insights from your data"
            } else if garminConnected {
                wellnessSource = .garmin
                wellnessReason = "Garmin can provide wellness data"
            } else {
                wellnessSource = .none
                wellnessReason = "No wellness tracking services connected"
            }
        }
        
        return RecommendedConfiguration(
            trainingLoadSource: trainingSource,
            trainingLoadReason: trainingReason,
            wellnessSource: wellnessSource,
            wellnessReason: wellnessReason,
            detectedEcosystem: ecosystem
        )
    }
    
    /// Detects which watch ecosystem the user is in
    private func detectWatchEcosystem(
        healthConnected: Bool,
        garminConnected: Bool
    ) -> DataSourceConfiguration.WatchEcosystem {
        
        // Check for actual data presence (more reliable than just connection)
        // If Health has sleep stages or HRV → likely Apple Watch user
        // If Garmin has data → Garmin user
        
        if healthConnected && garminConnected {
            // Both connected - need to check which has more recent data
            // For now, prefer Apple Watch if both are connected
            return .apple
        } else if healthConnected {
            return .apple
        } else if garminConnected {
            return .garmin
        } else {
            return .none
        }
    }
    
    // MARK: - Validation
    
    /// Checks if current configuration is valid given connected services
    func validateConfiguration(
        stravaConnected: Bool,
        healthConnected: Bool,
        garminConnected: Bool
    ) -> ConfigurationStatus {
        
        var issues: [String] = []
        var warnings: [String] = []
        
        // Check training load source
        switch configuration.trainingLoadSource {
        case .strava:
            if !stravaConnected {
                issues.append("Strava is selected but not connected")
            }
        case .appleHealth:
            if !healthConnected {
                issues.append("Apple Health is selected but not authorized")
            }
        case .garmin:
            if !garminConnected {
                issues.append("Garmin is selected but not connected")
            }
        case .manual:
            warnings.append("Manual entry requires you to log each workout")
        }
        
        // Check wellness source
        switch configuration.wellnessSource {
        case .appleHealth:
            if !healthConnected {
                issues.append("Apple Health wellness is selected but not authorized")
            }
        case .garmin:
            if !garminConnected {
                issues.append("Garmin wellness is selected but not connected")
            }
        case .none:
            warnings.append("Wellness tracking disabled - missing recovery insights")
        }
        
        // Check for suboptimal configurations (but only suggest obvious improvements)
        
        // Only suggest Strava if user is using Manual (no power data at all)
        if stravaConnected && configuration.trainingLoadSource == .manual {
            warnings.append("Strava is connected - consider using it for automatic training load tracking")
        }
        
        // Only suggest wellness tracking if it's disabled but Health/Garmin is available
        if healthConnected && configuration.wellnessSource == .none {
            warnings.append("Apple Health is connected - enable wellness tracking for recovery insights")
        }
        
        if garminConnected && configuration.wellnessSource == .none {
            warnings.append("Garmin is connected - enable wellness tracking for Body Battery and stress insights")
        }
        return ConfigurationStatus(
            isValid: issues.isEmpty,
            issues: issues,
            warnings: warnings
        )
    }
    
    // MARK: - Auto-configuration
    
    /// Automatically configures based on what's connected
    func autoConfigureFromConnections(
        stravaConnected: Bool,
        healthConnected: Bool,
        garminConnected: Bool
    ) {
        let recommended = getRecommendedConfiguration(
            stravaConnected: stravaConnected,
            healthConnected: healthConnected,
            garminConnected: garminConnected
        )
        
        configuration.trainingLoadSource = recommended.trainingLoadSource
        configuration.wellnessSource = recommended.wellnessSource
        configuration.detectedEcosystem = recommended.detectedEcosystem
        
        saveConfiguration()
        
        print("📊 Data Sources: Auto-configured")
        print("   Training: \(configuration.trainingLoadSource.rawValue)")
        print("   Wellness: \(configuration.wellnessSource.rawValue)")
        print("   Ecosystem: \(configuration.detectedEcosystem?.rawValue ?? "None")")
    }
}

// MARK: - Supporting Types

struct RecommendedConfiguration: Identifiable {
    let id = UUID()  // Add Identifiable conformance
    let trainingLoadSource: DataSourceConfiguration.TrainingLoadSource
    let trainingLoadReason: String
    let wellnessSource: DataSourceConfiguration.WellnessSource
    let wellnessReason: String
    let detectedEcosystem: DataSourceConfiguration.WatchEcosystem
}

struct ConfigurationStatus {
    let isValid: Bool
    let issues: [String]
    let warnings: [String]
    
    var hasWarnings: Bool { !warnings.isEmpty }
}
