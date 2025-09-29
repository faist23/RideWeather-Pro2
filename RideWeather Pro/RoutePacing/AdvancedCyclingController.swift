//
//  AdvancedCyclingController.swift
//  RideWeather Pro
//

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Main Integration Controller

@MainActor
final class AdvancedCyclingController: ObservableObject {
    
    // MARK: - Published Properties
    @Published var pacingPlan: PacingPlan?
    @Published var energyExpenditure: EnergyExpenditure?
    @Published var fuelingStrategy: FuelingStrategy?
    @Published var isGeneratingPlan = false
    @Published var syncResults: [SyncResult] = []
    
    // MARK: - Components
    private var pacingEngine: PacingEngine
    private var energyCalculator: EnergyCalculator
    private var deviceSyncManager: DeviceSyncManager
    private let settings: AppSettings
    
    // MARK: - Initialization
    
    init(settings: AppSettings) {
        self.settings = settings
        self.pacingEngine = PacingEngine(settings: settings)
        self.energyCalculator = EnergyCalculator(settings: settings)
        self.deviceSyncManager = DeviceSyncManager()
    }
    
    // MARK: - Main Workflow
    
    /// Generate comprehensive race plan from power analysis results
    func generateAdvancedRacePlan(
        from powerAnalysis: PowerRouteAnalysisResult,
        strategy: PacingStrategy = .balanced,
        fuelingPreferences: FuelingPreferences = FuelingPreferences(),
        startTime: Date = Date().addingTimeInterval(7200) // 2 hours from now
    ) async {
        
        isGeneratingPlan = true
        
        do {
            print("🚴‍♂️ Generating advanced race plan...")
            
            // Step 1: Generate pacing plan
            print("📊 Calculating optimal pacing strategy...")
            let pacing = pacingEngine.generatePacingPlan(
                from: powerAnalysis,
                strategy: strategy,
                startTime: startTime
            )
            
            // Step 2: Calculate energy expenditure
            print("⚡ Analyzing energy requirements...")
            let energy = energyCalculator.calculateEnergyExpenditure(from: pacing)
            
            // Step 3: Generate fueling strategy
            print("🍌 Creating fueling strategy...")
            let fueling = energyCalculator.generateFuelingStrategy(
                from: energy,
                preferences: fuelingPreferences
            )
            
            // Update published properties
            self.pacingPlan = pacing
            self.energyExpenditure = energy
            self.fuelingStrategy = fueling
            
            print("✅ Advanced race plan generated successfully!")
            print("📈 \(String(format: "%.1f", pacing.totalDistance))km in \(formatDuration(pacing.totalTimeMinutes * 60))")
            print("⚡ \(Int(energy.totalCalories)) calories, \(Int(pacing.estimatedTSS)) TSS")
            
        } catch {
            print("❌ Error generating race plan: \(error)")
        }
        
        isGeneratingPlan = false
    }
    
    /// Sync current race plan to selected devices
    func syncToDevices(_ platforms: [DevicePlatform], options: WorkoutOptions = WorkoutOptions()) async {
        guard let pacing = pacingPlan else {
            print("❌ No pacing plan available to sync")
            return
        }
        
        print("📱 Starting device sync to \(platforms.map { $0.displayName }.joined(separator: ", "))...")
        
        var results: [SyncResult] = []
        
        for platform in platforms {
            do {
                // Check authentication
                if !deviceSyncManager.isAuthenticated(platform) {
                    print("🔐 Authenticating with \(platform.displayName)...")
                    let authResult = await deviceSyncManager.authenticateDevice(platform)
                    
                    if !authResult.success {
                        results.append(SyncResult(
                            success: false,
                            platform: platform,
                            workoutId: nil,
                            workoutName: options.workoutName,
                            message: "Authentication failed",
                            syncInstructions: [],
                            estimatedSyncTime: nil,
                            error: authResult.error
                        ))
                        continue
                    }
                }
                
                // Convert pacing plan to workout
                let workout = try deviceSyncManager.convertPacingToWorkout(
                    pacing,
                    platform: platform,
                    options: options
                )
                
                // Push to device
                print("📤 Pushing workout to \(platform.displayName)...")
                let result = await deviceSyncManager.pushWorkout(workout, to: platform)
                results.append(result)
                
            } catch {
                results.append(SyncResult(
                    success: false,
                    platform: platform,
                    workoutId: nil,
                    workoutName: options.workoutName,
                    message: "Sync process failed",
                    syncInstructions: [],
                    estimatedSyncTime: nil,
                    error: error.localizedDescription
                ))
            }
        }
        
        self.syncResults = results
        
        // Log results
        for result in results {
            if result.success {
                print("✅ \(result.platform.displayName): \(result.message)")
            } else {
                print("❌ \(result.platform.displayName): \(result.error ?? "Unknown error")")
            }
        }
    }
    
    // MARK: - Export Functions
    
    /// Export complete race plan as CSV
    func exportRacePlanCSV() -> String {
        guard let pacing = pacingPlan,
              let energy = energyExpenditure else {
            return "No race plan available"
        }
        
        let headers = [
            "Segment", "Distance_km", "Gradient_%", "Target_Power_W", "Power_Zone",
            "Est_Time_min", "Calories", "Carbs_kcal", "Cumulative_Time_min",
            "Cumulative_Distance_km", "Strategy_Notes"
        ]
        
        var cumulativeTime: Double = 0
        var cumulativeDistance: Double = 0
        
        let rows = pacing.segments.enumerated().map { index, pacingSeg in
            cumulativeTime += pacingSeg.estimatedTimeMinutes
            cumulativeDistance += pacingSeg.distanceKm
            
            let energySeg = energy.segmentAnalysis[safe: index]
            
            return [
                String(index + 1),
                String(format: "%.2f", pacingSeg.distanceKm),
                String(format: "%.1f", pacingSeg.originalSegment.elevationGrade * 100),
                String(Int(pacingSeg.targetPower)),
                pacingSeg.powerZone.name,
                String(format: "%.1f", pacingSeg.estimatedTimeMinutes),
                String(Int(energySeg?.totalCalories ?? 0)),
                String(Int(energySeg?.carbsCalories ?? 0)),
                String(format: "%.1f", cumulativeTime),
                String(format: "%.2f", cumulativeDistance),
                pacingSeg.strategy
            ].joined(separator: ",")
        }
        
        return ([headers.joined(separator: ",")] + rows).joined(separator: "\n")
    }
    
    /// Generate printable race day summary
    func generateRaceDaySummary() -> String {
        guard let pacing = pacingPlan,
              let energy = energyExpenditure,
              let fueling = fuelingStrategy else {
            return "No race plan available"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        
        var summary = """
        RACE DAY SUMMARY
        ================
        Date: \(formatter.string(from: Date()))
        Route Distance: \(String(format: "%.1f", pacing.totalDistance)) km
        Estimated Time: \(formatDuration(pacing.totalTimeMinutes * 60))
        Estimated Arrival: \(formatter.string(from: pacing.estimatedArrival))
        
        POWER PLAN
        ===========
        Strategy: \(pacing.strategy.description)
        Average Power: \(Int(pacing.averagePower)) W
        Difficulty: \(pacing.difficulty.rawValue)
        Estimated TSS: \(Int(pacing.estimatedTSS))
        Intensity Factor: \(String(format: "%.2f", pacing.intensityFactor))
        
        ENERGY & FUELING
        ================
        Total Calories: \(Int(energy.totalCalories))
        Calories/Hour: \(Int(energy.caloriesPerHour))