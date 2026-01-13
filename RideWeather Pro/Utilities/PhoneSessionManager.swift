//
//  PhoneSessionManager.swift
//  RideWeather Pro
//

import Foundation
import WatchConnectivity

class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            DispatchQueue.main.async {
                self.sendUpdate()
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    
    // MARK: - Send to Watch
    
    func sendUpdate() {
        guard WCSession.default.activationState == .activated else {
            print("⚠️ Cannot send: WCSession is not activated")
            return
        }
        
        guard let loadSummary = TrainingLoadManager.shared.getCurrentSummary() else {
            print("⚠️ Cannot send: No Training Load Summary available")
            return
        }
        
        // ✅ ADD THIS: Check if we have readiness data
        if HealthKitManager.shared?.readiness.readinessScore == 0 {
            print("⚠️ Warning: Readiness score is 0 - may not have fetched yet")
        }
        
        print("📱 Sending to watch: TSB=\(loadSummary.currentTSB), Readiness=\(HealthKitManager.shared?.readiness.readinessScore ?? 0)")
        
        do {
            var context: [String: Any] = [:]
            
            // 1. Training Load
            context["trainingLoad"] = try JSONEncoder().encode(loadSummary)
            
            // 2. Wellness
            if let wellness = WellnessManager.shared.currentSummary {
                context["wellness"] = try JSONEncoder().encode(wellness)
            }
            
            // 3. Today's Wellness
            if let today = WellnessManager.shared.getTodayMetrics() {
                context["currentWellness"] = try JSONEncoder().encode(today)
            }
            
            // 4. Readiness (YOUR EXISTING DATA!)
            if let readiness = HealthKitManager.shared?.readiness {
                context["readiness"] = try JSONEncoder().encode(readiness)
            }
            
            // 5. History
            context["trainingHistory"] = try JSONEncoder().encode(TrainingLoadManager.shared.getHistory(days: 90))
            context["wellnessHistory"] = try JSONEncoder().encode(WellnessManager.shared.getHistory(days: 30))
            
            try WCSession.default.updateApplicationContext(context)
            print("✅ Sent data to Watch")
            
        } catch {
            print("❌ Watch sync error: \(error)")
        }
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
        let manager = TrainingLoadManager.shared
        return manager.loadAllDailyLoads().filter { $0.date >= startDate }.sorted { $0.date < $1.date }
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
