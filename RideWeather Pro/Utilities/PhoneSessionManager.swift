//
//  PhoneSessionManager.swift
//  RideWeather Pro
//

import Foundation
import WatchConnectivity
import UIKit

class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()
    
    // Cache the latest alert so we don't lose it when sending other updates
    private var currentAlert: WeatherAlert?
    
    // CRITICAL: Store references to the data sources
    private var trainingLoadSummary: TrainingLoadSummary?
    private var wellnessSummary: WellnessSummary?
    private var currentWellness: DailyWellnessMetrics?
    private var readinessData: PhysiologicalReadiness?
    private var recoveryStatus: RecoveryStatus? // ADD THIS
    
    // Queue for serializing access
    private let syncQueue = DispatchQueue(label: "com.ridepro.phonesession", qos: .userInitiated)
    
    override private init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - Public API (Thread-Safe)
    
    /// Call this when TrainingLoadSummary is updated
    func updateTrainingLoad(_ summary: TrainingLoadSummary) {
        syncQueue.async { [weak self] in
            self?.trainingLoadSummary = summary
            print("📱 Cached TrainingLoadSummary: TSB=\(summary.currentTSB)")
            self?.pushFullContext()
        }
    }
    
    /// Call this when WellnessSummary is updated
    func updateWellness(_ summary: WellnessSummary, current: DailyWellnessMetrics?) {
        syncQueue.async { [weak self] in
            self?.wellnessSummary = summary
            self?.currentWellness = current
            print("📱 Cached WellnessSummary")
            self?.pushFullContext()
        }
    }
    
    /// Call this when Readiness is updated
    func updateReadiness(_ readiness: PhysiologicalReadiness) {
        syncQueue.async { [weak self] in
            self?.readinessData = readiness
            print("📱 Cached Readiness: \(readiness.readinessScore)")
            self?.pushFullContext()
        }
    }
    
    /// Call this when Recovery Status is updated
    func updateRecovery(_ recovery: RecoveryStatus) {
        syncQueue.async { [weak self] in
            self?.recoveryStatus = recovery
            print("📱 Cached Recovery: \(recovery.recoveryPercent)%")
            self?.pushFullContext()
        }
    }
    
    /// Called when Training Load changes (legacy - still needed for history)
    func sendUpdate() {
        syncQueue.async { [weak self] in
            // Auto-fetch the latest summaries if not already cached
            Task { @MainActor in
                if self?.trainingLoadSummary == nil {
                    let summary = TrainingLoadManager.shared.getCurrentSummary()
                    self?.trainingLoadSummary = summary
                }
                if self?.wellnessSummary == nil || self?.currentWellness == nil {
                    let summary = WellnessManager.shared.currentSummary
                    let current = WellnessManager.shared.dailyMetrics.first { Calendar.current.isDateInToday($0.date) }
                    self?.wellnessSummary = summary
                    self?.currentWellness = current
                }
                if self?.readinessData == nil, let healthKit = HealthKitManager.shared {
                    self?.readinessData = healthKit.readiness
                }
                
                // Now push on background queue
                self?.syncQueue.async {
                    self?.pushFullContext()
                }
            }
        }
    }
    
    /// Called when Weather Alert changes
    func updateAlert(_ alert: WeatherAlert?) {
        syncQueue.async { [weak self] in
            self?.currentAlert = alert
            self?.pushFullContext()
        }
    }
    
    // MARK: - Emergency Manual Sync (Call this to force a full sync)
    
    /// Fetches data from managers and sends to Watch - use when automatic updates aren't working
    func forceFullSync(
        trainingLoadSummary: TrainingLoadSummary?,
        wellnessSummary: WellnessSummary?,
        currentWellness: DailyWellnessMetrics?,
        readiness: PhysiologicalReadiness?
    ) {
        syncQueue.async { [weak self] in
            print("🔄 FORCE SYNC called")
            
            if let summary = trainingLoadSummary {
                self?.trainingLoadSummary = summary
                print("   ✅ Got TrainingLoadSummary: TSB=\(summary.currentTSB)")
            } else {
                print("   ⚠️ No TrainingLoadSummary provided")
            }
            
            if let summary = wellnessSummary {
                self?.wellnessSummary = summary
                print("   ✅ Got WellnessSummary")
            } else {
                print("   ⚠️ No WellnessSummary provided")
            }
            
            if let current = currentWellness {
                self?.currentWellness = current
                print("   ✅ Got Current Wellness")
            } else {
                print("   ⚠️ No Current Wellness provided")
            }
            
            if let readiness = readiness {
                self?.readinessData = readiness
                print("   ✅ Got Readiness: \(readiness.readinessScore)")
            } else {
                print("   ⚠️ No Readiness provided")
            }
            
            self?.pushFullContext()
        }
    }
    
    // MARK: - The Master Sync Function (Must be called from syncQueue)
    
    /// Gathers ALL data (Training, Wellness, Weather, Date, Alerts) and sends one complete package.
    private func pushFullContext() {
        guard WCSession.default.activationState == .activated else {
            print("⚠️ WCSession not activated, skipping sync")
            return
        }
        
        do {
            var context: [String: Any] = [:]
            var keyCount = 0
            
            // 1. Training Load Summary (CACHED)
            if let summary = trainingLoadSummary {
                context["trainingLoad"] = try JSONEncoder().encode(summary)
                print("📱 Encoded TrainingLoadSummary: TSB=\(summary.currentTSB)")
                keyCount += 1
            } else {
                print("⚠️ No TrainingLoadSummary cached - call updateTrainingLoad() first")
            }
            
            // 2. Training Load History (RAW)
            let trainingHistory = TrainingLoadManager.shared.getHistory(days: 90)
            context["trainingHistory"] = try JSONEncoder().encode(trainingHistory)
            print("📱 Encoded Training History: \(trainingHistory.count) days")
            keyCount += 1
            
            // 3. Wellness Summary (CACHED)
            if let summary = wellnessSummary {
                context["wellness"] = try JSONEncoder().encode(summary)
                print("📱 Encoded WellnessSummary")
                keyCount += 1
            } else {
                print("⚠️ No WellnessSummary cached - call updateWellness() first")
            }
            
            // 4. Current Wellness (CACHED)
            if let current = currentWellness {
                context["currentWellness"] = try JSONEncoder().encode(current)
                print("📱 Encoded Current Wellness")
                keyCount += 1
            } else {
                print("⚠️ No current wellness cached")
            }
            
            // 5. Wellness History (RAW) - Must access on MainActor
            Task { @MainActor in
                do {
                    let wellnessHistory = WellnessManager.shared.getHistory(days: 30)
                    var contextCopy = context
                    contextCopy["wellnessHistory"] = try JSONEncoder().encode(wellnessHistory)
                    print("📱 Encoded Wellness History: \(wellnessHistory.count) days")
                    
                    // Continue building context...
                    self.finishPushContext(contextCopy, keyCount: keyCount + 1)
                } catch {
                    print("❌ Error encoding wellness history: \(error)")
                }
            }
        } catch {
            print("❌ WCSession Error: \(error)")
        }
    }
    
    private func finishPushContext(_ context: [String: Any], keyCount: Int) {
        var mutableContext = context
        var finalKeyCount = keyCount
        
        do {
            // 6. Readiness Data (CACHED)
            if let readiness = readinessData {
                mutableContext["readiness"] = try JSONEncoder().encode(readiness)
                print("📱 Encoded Readiness: Score=\(readiness.readinessScore)")
                finalKeyCount += 1
            } else {
                print("⚠️ No Readiness data cached - call updateReadiness() first")
            }
            
            // 7. Recovery Status (CACHED)
            if let recovery = recoveryStatus {
                mutableContext["recovery"] = try JSONEncoder().encode(recovery)
                print("📱 Encoded Recovery: \(recovery.recoveryPercent)%")
                finalKeyCount += 1
            } else {
                print("⚠️ No Recovery status cached - call updateRecovery() first")
            }
            
            // 8. Weather Summary (Widget)
            if let weatherData = UserDefaultsManager.shared.loadWeatherSummary() {
                mutableContext["weatherSummary"] = try JSONEncoder().encode(weatherData)
                print("📱 Encoded Weather Summary")
                finalKeyCount += 1
            }
            
            // 9. Weather Alert (Cached)
            if let alert = currentAlert {
                mutableContext["weatherAlert"] = try JSONEncoder().encode(alert)
                print("📱 Encoded Weather Alert")
                finalKeyCount += 1
            }
            
            // 10. Precise Last Ride Date
            if let lastRide = UserDefaults.standard.object(forKey: "last_ride_precise_date") as? Date {
                mutableContext["lastRidePreciseDate_ts"] = lastRide.timeIntervalSinceReferenceDate
                print("📱 Sending Timestamp: \(lastRide.timeIntervalSinceReferenceDate) (\(lastRide.formatted(date: .omitted, time: .standard)))")
                finalKeyCount += 1
            }

            // 11. User settings the watch needs — app groups don't sync
            // between iPhone and Watch, so these must travel in the context
            let settings = UserDefaultsManager.shared.loadSettings()
            mutableContext["unitsSetting"] = settings.units.rawValue
            mutableContext["weatherProviderSetting"] = settings.weatherProvider.syncToken
            finalKeyCount += 2

            // Send the combined package
            try WCSession.default.updateApplicationContext(mutableContext)
            print("✅ WCSession: Sent \(finalKeyCount) keys to Watch")
            print("   Keys: \(mutableContext.keys.sorted().joined(separator: ", "))")
            
        } catch {
            print("❌ WCSession Error: \(error)")
        }
    }
    
    // MARK: - WCSessionDelegate Boilerplate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("❌ WCSession activation error: \(error)")
        } else {
            print("✅ WCSession activated: \(activationState.rawValue)")
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("⚠️ WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("⚠️ WCSession deactivated, reactivating...")
        WCSession.default.activate()
    }
}

// MARK: - Extensions

extension HealthKitManager {
    static var shared: HealthKitManager? {
        return _sharedInstance
    }
    
    private static var _sharedInstance: HealthKitManager?
    
    static func setShared(_ instance: HealthKitManager) {
        _sharedInstance = instance
    }
}

extension TrainingLoadManager {
    func getHistory(days: Int) -> [DailyTrainingLoad] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!
        return loadAllDailyLoads().filter { $0.date >= startDate }.sorted { $0.date < $1.date }
    }
}

extension WellnessManager {
    func getTodayMetrics() -> DailyWellnessMetrics? {
        let calendar = Calendar.current
        return dailyMetrics.first { calendar.isDateInToday($0.date) }
    }
    
    func getHistory(days: Int) -> [DailyWellnessMetrics] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!
        return dailyMetrics.filter { $0.date >= startDate }.sorted { $0.date < $1.date }
    }
}
