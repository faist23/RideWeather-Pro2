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
    
    override private init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - Public API
    
    /// Called when Training Load changes
    func sendUpdate() {
        pushFullContext()
    }
    
    /// Called when Weather Alert changes
    func updateAlert(_ alert: WeatherAlert?) {
        self.currentAlert = alert // Save to memory
        pushFullContext()         // Send everything including the new alert
    }
    
    // MARK: - The Master Sync Function
    
    /// Gathers ALL data (Training, Wellness, Weather, Date, Alerts) and sends one complete package.
    private func pushFullContext() {
        guard WCSession.default.activationState == .activated else { return }
        
        do {
            var context: [String: Any] = [:]
            
            // 1. Training Load History
            context["trainingHistory"] = try JSONEncoder().encode(TrainingLoadManager.shared.getHistory(days: 90))
            
            // 2. Wellness History
            context["wellnessHistory"] = try JSONEncoder().encode(WellnessManager.shared.getHistory(days: 30))
            
            // 3. Weather Summary (Widget)
            if let weatherData = UserDefaultsManager.shared.loadWeatherSummary() {
                context["weatherSummary"] = try JSONEncoder().encode(weatherData)
            }
            
            // 4. Weather Alert (Use cached or nil)
            if let alert = currentAlert {
                context["weatherAlert"] = try JSONEncoder().encode(alert)
            }
            
            // 5. Precise Last Ride Date (Send as TimeInterval to be 100% safe)
            if let lastRide = UserDefaults.standard.object(forKey: "last_ride_precise_date") as? Date {
                // Sending as Double avoids any Date type-casting issues across the bridge
                context["lastRidePreciseDate_ts"] = lastRide.timeIntervalSinceReferenceDate
                print("📱 Sending Timestamp: \(lastRide.timeIntervalSinceReferenceDate) (\(lastRide.formatted(date: .omitted, time: .standard)))")
            }
            
            // Send the combined package
            try WCSession.default.updateApplicationContext(context)
            print("✅ WCSession: Sent full context update.")
            
        } catch {
            print("❌ WCSession Error: \(error)")
        }
    }
    
    // MARK: - WCSessionDelegate Boilerplate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
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
