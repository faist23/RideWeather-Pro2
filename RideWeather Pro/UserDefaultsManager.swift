//
// UserDefaultsManager.swift - Enhanced with FTP and Power Analysis Support
//

import Foundation

struct AppSettings: Codable, Equatable {
    var units: UnitSystem = .imperial
    var idealTemperature: Double = 70.0
    
    // MARK: - NEW Safety Warning Settings
    var enableColdWeatherWarning: Bool = true
    var coldWeatherWarningThreshold: Double = 45.0 // Stored in user's preferred units

    // Existing advanced options
    var includeRestStops: Bool = false
    var restStopCount: Int = 1
    var restStopDuration: Int = 10
    var considerElevation: Bool = false
    
    // NEW: Speed calculation method
    var speedCalculationMethod: SpeedCalculationMethod = .averageSpeed
    
    // NEW: Power-based analysis settings (only used when speedCalculationMethod == .powerBased)
    var functionalThresholdPower: Int = 200 // watts
    var bodyWeight: Double = 70.0 // kg (always stored in kg internally)
    var bikeAndEquipmentWeight: Double = 10.0 // kg (always stored in kg internally)
//    var powerTargetPercentage: Double = 75.0 // percentage of FTP to use for ride
    
    // Traditional speed setting (only used when speedCalculationMethod == .averageSpeed)
    var averageSpeed: Double = 16.5 // stored in user's preferred units
    
    var autoSyncWeightFromStrava: Bool = false 

    // Exclusive Weight Source Selection
    var weightSource: WeightSource = .manual

    // Enhanced recommendation preferences
    var primaryRidingGoal: RidingGoal = .performance
    var temperatureTolerance: TemperatureTolerance = .neutral
    var windTolerance: WindTolerance = .moderate
    var wakeUpEarliness: WakeUpPreference = .moderate

    // Fueling preferences
    var maxCarbsPerHour: Double = 60.0
    var preferredFuelTypes: [String] = ["gel", "drink", "bar", "solid"] // Store as strings for Codable
    var preferLiquids: Bool = false
    var avoidGluten: Bool = false
    var avoidCaffeine: Bool = false
    
    // Convert to/from FuelingPreferences
    var fuelingPreferences: FuelingPreferences {
        get {
            FuelingPreferences(
                maxCarbsPerHour: maxCarbsPerHour,
                fuelTypes: preferredFuelTypes.compactMap { FuelType(rawValue: $0) },
                preferLiquids: preferLiquids,
                avoidGluten: avoidGluten,
                avoidCaffeine: avoidCaffeine
            )
        }
        set {
            maxCarbsPerHour = newValue.maxCarbsPerHour
            preferredFuelTypes = newValue.fuelTypes.map { $0.rawValue }
            preferLiquids = newValue.preferLiquids
            avoidGluten = newValue.avoidGluten
            avoidCaffeine = newValue.avoidCaffeine
        }
    }
    
    // MARK: - Computed Properties for Weight in User Units
    
    var bodyWeightInUserUnits: Double {
        get {
            return units == .metric ? bodyWeight : bodyWeight * 2.20462 // kg to lbs
        }
        set {
            bodyWeight = units == .metric ? newValue : newValue / 2.20462 // lbs to kg
        }
    }
    
    var bikeWeightInUserUnits: Double {
        get {
            return units == .metric ? bikeAndEquipmentWeight : bikeAndEquipmentWeight * 2.20462
        }
        set {
            bikeAndEquipmentWeight = units == .metric ? newValue : newValue / 2.20462
        }
    }
    
    var totalWeightKg: Double {
        return bodyWeight + bikeAndEquipmentWeight
    }
    
    // MARK: - Enums
    
    enum WeightSource: String, CaseIterable, Identifiable, Codable {
            case manual = "Manual Input"
            case strava = "Strava"
            case healthKit = "Apple Health"
            
            var id: String { self.rawValue }
        }
        
    enum SpeedCalculationMethod: String, CaseIterable, Identifiable, Codable {
        case averageSpeed = "average_speed"
        case powerBased = "power_based"
        
        var id: String { self.rawValue }
        
        var description: String {
            switch self {
            case .averageSpeed: return "Average Speed"
            case .powerBased: return "Power-Based Analysis"
            }
        }
        
        var detailDescription: String {
            switch self {
            case .averageSpeed:
                return "Uses a fixed average speed for time estimates. Simple and reliable."
            case .powerBased:
                return "Calculates speed based on power output, accounting for terrain, wind, and physics. More accurate for varied terrain."
            }
        }
    }
        
    enum RidingGoal: String, CaseIterable, Identifiable, Codable {
        case commute, performance, enjoyment
        
        var id: String { self.rawValue }
        
        var description: String {
            switch self {
            case .commute: return "Commuting"
            case .performance: return "Performance"
            case .enjoyment: return "Enjoyment"
            }
        }
    }
    
    enum TemperatureTolerance: String, CaseIterable, Identifiable, Codable {
        case verySensitive, prefersWarm, neutral, prefersCool, veryTolerant
        
        var id: String { self.rawValue }
        
        var description: String {
            switch self {
            case .verySensitive: return "Very Sensitive"
            case .prefersWarm: return "Prefers Warm"
            case .neutral: return "Neutral"
            case .prefersCool: return "Prefers Cool"
            case .veryTolerant: return "Very Tolerant"
            }
        }
    }
    
    enum WindTolerance: String, CaseIterable, Identifiable, Codable {
        case windSensitive, moderate, windTolerant
        
        var id: String { self.rawValue }
        
        var description: String {
            switch self {
            case .windSensitive: return "Wind Sensitive"
            case .moderate: return "Moderate"
            case .windTolerant: return "Wind Tolerant"
            }
        }
    }
    
    enum WakeUpPreference: String, CaseIterable, Identifiable, Codable {
        case earlyBird, moderate, nightOwl
        
        var id: String { self.rawValue }
        
        var description: String {
            switch self {
            case .earlyBird: return "Early Bird"
            case .moderate: return "Moderate"
            case .nightOwl: return "Night Owl"
            }
        }
    }
}

enum UnitSystem: String, CaseIterable, Identifiable, Codable {
    case imperial
    case metric

    var id: String { self.rawValue }

    var description: String {
        switch self {
        case .imperial: return "Imperial (°F, mph)"
        case .metric: return "Metric (°C, kph)"
        }
    }
    
    var tempSymbol: String {
        return self == .imperial ? "°F" : "°C"
    }

    var speedSymbol: String {
        return self == .imperial ? "mph" : "m/s"
    }

    var speedUnitAbbreviation: String {
        switch self {
        case .imperial: return "mph"
        case .metric: return "kph"
        }
    }
    
    var weightSymbol: String {
        return self == .imperial ? "lbs" : "kg"
    }
    
    var distanceSymbol: String {
        return self == .imperial ? "ft" : "m"
    }
}

class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    private let settingsKey = "appSettings"
    private let defaults = UserDefaults.standard

    private init() {}

    func saveSettings(_ settings: AppSettings) {
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: settingsKey)
        }
    }

    func loadSettings() -> AppSettings {
        if let data = defaults.data(forKey: settingsKey) {
            if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                return decoded
            }
        }
        return AppSettings()
    }
}

