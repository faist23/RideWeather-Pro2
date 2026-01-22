//
//  WatchSessionManager.swift
//  RideWeatherWatch Watch App
//

import Foundation
import WatchConnectivity
import SwiftUI
import Combine
import WatchKit // Ensure WatchKit is imported for haptics
import WidgetKit
@preconcurrency import UserNotifications

@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    // Raw data from phone
    @Published var lastContextUpdate: Date?
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
    
    // Load from UserDefaults on init
    @Published var lastPreciseRideDate: Date? = UserDefaults.standard.object(forKey: "watch_last_precise_date") as? Date
    
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
        // Track when we received this update
        self.lastContextUpdate = Date()
        
        print("⌚️ Processing context with \(context.keys.count) keys: \(context.keys.joined(separator: ", "))")
        
        // 1. Decode Training Load Summary
        if let loadData = context["trainingLoad"] as? Data {
            do {
                // Capture old value for comparison
                let oldTSB = self.loadSummary?.currentTSB
                
                let decoded = try JSONDecoder().decode(TrainingLoadSummary.self, from: loadData)
                self.loadSummary = decoded
                
                // HAPTIC LOGIC: Check if we just became "Fresh" (TSB > 10)
                if let old = oldTSB, old <= 10, decoded.currentTSB > 10 {
                    print("⌚️ TSB Crossed Threshold! Triggering Haptic.")
                    WKInterfaceDevice.current().play(.success)
                }
                
                print("✅ Decoded TrainingLoadSummary: TSB=\(decoded.currentTSB)")
            } catch {
                print("❌ Failed to decode TrainingLoadSummary: \(error)")
            }
        } else {
            // Only print warning if you expect this key to always be present
            // print("⚠️ No trainingLoad data in context")
        }
        
        // 2. Decode Readiness
        if let readinessData = context["readiness"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(PhysiologicalReadiness.self, from: readinessData)
                self.readinessData = decoded
                print("✅ Decoded Readiness: Score=\(decoded.readinessScore)")
            } catch {
                print("❌ Failed to decode Readiness: \(error)")
            }
        }
        
        // 3. Decode Wellness Summary
        if let wellnessData = context["wellness"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(WellnessSummary.self, from: wellnessData)
                self.wellnessSummary = decoded
                print("✅ Decoded WellnessSummary")
            } catch {
                print("❌ Failed to decode WellnessSummary: \(error)")
            }
        }
        
        // 4. Decode Current Wellness Metrics
        if let currentWellnessData = context["currentWellness"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(DailyWellnessMetrics.self, from: currentWellnessData)
                self.currentWellness = decoded
                
                // ✅ SAVE STEPS FOR WIDGET
                if let steps = decoded.steps {
                    let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
                    defaults?.set(steps, forKey: "widget_today_steps")
                    print("✅ Saved \(steps) steps for widget")
                }
                
                print("✅ Decoded Current Wellness")
            } catch {
                print("❌ Failed to decode Current Wellness: \(error)")
            }
        }
        
        // 5. Decode Training History
        if let historyData = context["trainingHistory"] as? Data {
            do {
                let decoded = try JSONDecoder().decode([DailyTrainingLoad].self, from: historyData)
                self.trainingHistory = decoded
                print("✅ Decoded Training History: \(decoded.count) days")
            } catch {
                print("❌ Failed to decode Training History: \(error)")
            }
        }
        
        // 6. Decode Wellness History
        if let wellnessHistoryData = context["wellnessHistory"] as? Data {
            do {
                let decoded = try JSONDecoder().decode([DailyWellnessMetrics].self, from: wellnessHistoryData)
                self.wellnessHistory = decoded
                print("✅ Decoded Wellness History: \(decoded.count) days")
            } catch {
                print("❌ Failed to decode Wellness History: \(error)")
            }
        }
        
        // 8. Decode Recovery Status (SYNCED FROM IPHONE)
        if let recoveryData = context["recovery"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(RecoveryStatus.self, from: recoveryData)
                self.recoveryStatus = decoded
                print("✅ Decoded Recovery Status: \(decoded.recoveryPercent)% (synced from iPhone)")
            } catch {
                print("❌ Failed to decode Recovery Status: \(error)")
            }
        }
        
        // 7. Decode Weather Alert
        if let weatherData = context["weatherAlert"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(WeatherAlert.self, from: weatherData)
                self.weatherAlert = decoded
                
                // Trigger a different haptic for severe weather
                if decoded.severity == .severe {
                    WKInterfaceDevice.current().play(.notification)
                }
                print("✅ Decoded Weather Alert: \(decoded.message)")
            } catch {
                print("❌ Failed to decode Weather Alert: \(error)")
            }
        } else {
            // Clear alert if missing (optional, depends on if nil means 'no alert')
            self.weatherAlert = nil
        }
        
        // 8. Save Weather Data for Widget
        // We don't need to decode it here; just pass the raw data to the Widget's storage
        if let weatherData = context["weatherSummary"] as? Data {
            let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
            defaults?.set(weatherData, forKey: "widget_weather_summary")
            print("⌚️ Received & Saved Weather Summary for Widget")
        }
        
        // 9. Decode AND Save Precise Timestamp (Fix for "19h")
        // Try Double (TimeInterval) first - safer
        if let timestamp = context["lastRidePreciseDate_ts"] as? TimeInterval {
            let preciseDate = Date(timeIntervalSinceReferenceDate: timestamp)
            self.lastPreciseRideDate = preciseDate
            UserDefaults.standard.set(preciseDate, forKey: "watch_last_precise_date")
            print("✅ Received Precise Timestamp: \(preciseDate.formatted(date: .omitted, time: .standard))")
        }
        // Fallback to legacy Date object
        else if let legacyDate = context["lastRidePreciseDate"] as? Date {
            self.lastPreciseRideDate = legacyDate
            UserDefaults.standard.set(legacyDate, forKey: "watch_last_precise_date")
            print("✅ Received Legacy Precise Date: \(legacyDate.formatted(date: .omitted, time: .standard))")
        } else {
            // print("⚠️ No precise ride date found in context")
        }
        
        // 10. Decode Recovery Status (SYNCED FROM IPHONE)
        if let recoveryData = context["recovery"] as? Data {
            do {
                let decoded = try JSONDecoder().decode(RecoveryStatus.self, from: recoveryData)
                self.recoveryStatus = decoded
                print("✅ Decoded Recovery Status: \(decoded.recoveryPercent)% (synced from iPhone)")
            } catch {
                print("❌ Failed to decode Recovery Status: \(error)")
            }
        }

        // Calculate derived data
        calculateDerivedData()
        
        // After decoding everything, update the shared storage for the widget
        saveDataForWidget()
        
        // Check if we should notify the user
        if let readiness = self.readinessData {
            checkAndSendReadinessNotification(score: readiness.readinessScore)
        }
        
        print("✅ Context processing complete. loadSummary=\(loadSummary != nil), readinessData=\(readinessData != nil)")
    }
    
    private func calculateDerivedData() {
/*        // Calculate Recovery Status
        if let wellness = currentWellness {
            let lastRideDaily = trainingHistory
                .filter { $0.rideCount > 0 }
                .sorted { $0.date > $1.date }
                .first?.date
            
            let bestWorkoutDate = self.lastPreciseRideDate ?? lastRideDaily
            
            // 🔎 SEARCHLIGHT 4: The Final Verdict
            print("\n🔎 DEBUG (Watch Calculation):")
            print("   - Stored Precise Date: \(self.lastPreciseRideDate?.formatted(date: .omitted, time: .standard) ?? "Nil")")
            print("   - Backup Daily Date: \(lastRideDaily?.formatted(date: .omitted, time: .standard) ?? "Nil")")
            print("   - DATE USED FOR CALC: \(bestWorkoutDate?.formatted(date: .omitted, time: .standard) ?? "Nil")")
            
            let currentHRV = readinessData?.latestHRV ?? Double(wellness.restingHeartRate ?? 60)
            let baselineHRV = readinessData?.averageHRV ?? currentHRV
            let currentRestingHR = readinessData?.latestRHR ?? Double(wellness.restingHeartRate ?? 60)
            let baselineRestingHR = readinessData?.averageRHR ?? currentRestingHR
            
            self.recoveryStatus = RecoveryStatus.calculate(
                lastWorkoutDate: bestWorkoutDate,
                currentHRV: currentHRV,
                baselineHRV: baselineHRV,
                currentRestingHR: currentRestingHR,
                baselineRestingHR: baselineRestingHR,
                wellness: wellness,
                weekHistory: wellnessHistory
            )
            print("✅ Calculated Recovery Status: \(recoveryStatus?.recoveryPercent ?? 0)%")
        }*/
        
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
    
    // Save data to App Group
    private func saveDataForWidget() {
        let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
        
        if let load = self.loadSummary {
            defaults?.set(load.currentTSB, forKey: "widget_tsb")
            defaults?.set(load.formStatus.rawValue, forKey: "widget_status")
            defaults?.set(load.currentCTL, forKey: "widget_ctl") // Using CTL as proxy for daily TSS if needed
        }
        
        if let readiness = self.readinessData {
            defaults?.set(readiness.readinessScore, forKey: "widget_readiness")
        }
        
        if let wellness = self.currentWellness {
            defaults?.set(wellness.steps ?? 0, forKey: "widget_today_steps")
        }

        // Save steps immediately
        if let steps = self.currentWellness?.steps {
            defaults?.set(steps, forKey: "widget_today_steps")
            print("⌚️ Saved steps to widget: \(steps)")
        }
        
        // Force the widget to refresh immediately
        WidgetCenter.shared.reloadAllTimelines()
        print("⌚️ Widget data saved & timeline reload requested")
    }
    
    // MARK: - Notification Logic
    
    private func checkAndSendReadinessNotification(score: Int) {
        // 1. Check if we already notified today
        // Use standard directly here
        let lastDate = UserDefaults.standard.object(forKey: "last_readiness_notification") as? Date ?? Date.distantPast
        
        if Calendar.current.isDateInToday(lastDate) {
            print("⌚️ Already sent notification today. Skipping.")
            return
        }
        
        // 2. Determine Message
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        switch score {
        case 85...100:
            content.title = "🚀 Ready to Go Hard!"
            content.body = "Readiness is \(score)%. Great day for intervals or a hard group ride."
        case 70..<85:
            content.title = "✅ Good to Go"
            content.body = "Readiness is \(score)%. You can handle some intensity today."
        case 50..<70:
            content.title = "⚠️ Moderate Fatigue"
            content.body = "Readiness is \(score)%. Keep it steady or aerobic."
        case 0..<50:
            content.title = "🛑 Rest Day Recommended"
            content.body = "Readiness is only \(score)%. Prioritize recovery."
        default:
            return
        }
        
        // 3. Create Request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        // Capture the title string (Sendable) instead of the content object (Non-Sendable)
        let logTitle = content.title
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
            } else {
                print("✅ Notification scheduled: \(logTitle)")
                
                // Access UserDefaults.standard directly inside the closure
                // instead of capturing a local variable.
                UserDefaults.standard.set(Date(), forKey: "last_readiness_notification")
            }
        }
    }
}
