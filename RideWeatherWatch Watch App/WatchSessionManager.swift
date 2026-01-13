//
//  WatchSessionManager.swift
//  RideWeatherWatch Watch App
//

import Foundation
import WatchConnectivity
import SwiftUI
import Combine

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    // Raw data from phone
    @Published var loadSummary: TrainingLoadSummary?
    @Published var wellnessSummary: WellnessSummary?
    @Published var currentWellness: DailyWellnessMetrics?
    @Published var readinessData: PhysiologicalReadiness?
    @Published var trainingHistory: [DailyTrainingLoad] = []
    @Published var wellnessHistory: [DailyWellnessMetrics] = []
    @Published var weatherAlert: WeatherAlert?
    
    // Computed properties for watch views
    @Published var recoveryStatus: RecoveryStatus?
    @Published var weeklyProgress: WeeklyProgress?
    @Published var weeklyStats: WeeklyStats?
    
    private var sessionActivated = false
    
    override private init() {
        super.init()
        setupWatchConnectivity()
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            print("⌚️ WCSession not supported on this device")
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        session.activate()
        
        print("⌚️ WCSession activation requested")
    }
}

// MARK: - WCSessionDelegate (non-isolated)
extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            print("⌚️ Watch session activated: \(activationState.rawValue)")
            
            if let error = error {
                print("⌚️ Activation error: \(error.localizedDescription)")
                return
            }
            
            if activationState == .activated {
                self.sessionActivated = true
                
                // ✅ CRITICAL: Process any existing context immediately
                if !session.receivedApplicationContext.isEmpty {
                    print("⌚️ Found existing context on activation, processing...")
                    self.processContext(session.receivedApplicationContext)
                } else {
                    print("⌚️ No existing context found")
                }
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            print("⌚️ Received new application context")
            processContext(applicationContext)
        }
    }
    
    private func processContext(_ context: [String: Any]) {
        print("⌚️ Processing context with \(context.keys.count) keys: \(context.keys.joined(separator: ", "))")
        
        // Decode Training Load Summary
        if let loadData = context["trainingLoad"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(TrainingLoadSummary.self, from: loadData)
                self.loadSummary = decoded
                print("✅ Decoded TrainingLoadSummary: TSB=\(decoded.currentTSB)")
            } catch {
                print("❌ Failed to decode TrainingLoadSummary: \(error)")
            }
        } else {
            print("⚠️ No trainingLoad data in context")
        }
        
        // Decode Readiness
        if let readinessData = context["readiness"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(PhysiologicalReadiness.self, from: readinessData)
                self.readinessData = decoded
                print("✅ Decoded Readiness: Score=\(decoded.readinessScore)")
            } catch {
                print("❌ Failed to decode Readiness: \(error)")
            }
        } else {
            print("⚠️ No readiness data in context")
        }
        
        // Decode Wellness Summary
        if let wellnessData = context["wellness"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(WellnessSummary.self, from: wellnessData)
                self.wellnessSummary = decoded
                print("✅ Decoded WellnessSummary")
            } catch {
                print("❌ Failed to decode WellnessSummary: \(error)")
            }
        }
        
        // Decode Current Wellness Metrics
        if let currentWellnessData = context["currentWellness"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(DailyWellnessMetrics.self, from: currentWellnessData)
                self.currentWellness = decoded
                print("✅ Decoded Current Wellness")
            } catch {
                print("❌ Failed to decode Current Wellness: \(error)")
            }
        }
        
        // Decode Training History
        if let historyData = context["trainingHistory"] as? Data {
            do {
                let decoded = try JSONDecoder().decode([DailyTrainingLoad].self, from: historyData)
                self.trainingHistory = decoded
                print("✅ Decoded Training History: \(decoded.count) days")
            } catch {
                print("❌ Failed to decode Training History: \(error)")
            }
        }
        
        // Decode Wellness History
        if let wellnessHistoryData = context["wellnessHistory"] as? Data {
            do {
                let decoded = try JSONDecoder().decode([DailyWellnessMetrics].self, from: wellnessHistoryData)
                self.wellnessHistory = decoded
                print("✅ Decoded Wellness History: \(decoded.count) days")
            } catch {
                print("❌ Failed to decode Wellness History: \(error)")
            }
        }
        
        // Decode Weather Alert
        if let weatherData = context["weatherAlert"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(WeatherAlert.self, from: weatherData)
                self.weatherAlert = decoded
                print("✅ Decoded Weather Alert")
            } catch {
                print("❌ Failed to decode Weather Alert: \(error)")
            }
        }
        
        // Calculate derived data
        calculateDerivedData()
        
        print("✅ Context processing complete. loadSummary=\(loadSummary != nil), readinessData=\(readinessData != nil)")
    }
    
    private func calculateDerivedData() {
        // Calculate Recovery Status
        if let wellness = currentWellness {
            let lastRide = trainingHistory
                .filter { $0.rideCount > 0 }
                .sorted { $0.date > $1.date }
                .first?.date
            
            let currentHRV = readinessData?.latestHRV ?? Double(wellness.restingHeartRate ?? 60)
            let baselineHRV = readinessData?.averageHRV ?? currentHRV
            let currentRestingHR = readinessData?.latestRHR ?? Double(wellness.restingHeartRate ?? 60)
            let baselineRestingHR = readinessData?.averageRHR ?? currentRestingHR
            
            self.recoveryStatus = RecoveryStatus.calculate(
                lastRideDate: lastRide,
                currentHRV: currentHRV,
                baselineHRV: baselineHRV,
                currentRestingHR: currentRestingHR,
                baselineRestingHR: baselineRestingHR,
                wellness: wellness,
                weekHistory: wellnessHistory
            )
            print("✅ Calculated Recovery Status: \(recoveryStatus?.recoveryPercent ?? 0)%")
        }
        
        // Calculate Weekly Progress
        if let load = loadSummary {
            self.weeklyProgress = WeeklyProgress.calculate(
                current: load,
                history: trainingHistory
            )
            print("✅ Calculated Weekly Progress")
        }
        
        // Calculate Weekly Stats
        if !trainingHistory.isEmpty {
            self.weeklyStats = WeeklyStats.calculate(from: trainingHistory)
            print("✅ Calculated Weekly Stats: \(weeklyStats?.rideCount ?? 0) rides")
        }
    }
}
