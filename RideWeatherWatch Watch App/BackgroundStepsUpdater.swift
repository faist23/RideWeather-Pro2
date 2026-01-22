//
//  BackgroundStepsUpdater.swift
//  RideWeatherWatch Watch App
//

import Foundation
import HealthKit
import WidgetKit
import CoreLocation

@MainActor
class BackgroundStepsUpdater: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundStepsUpdater()
    private let healthStore = HKHealthStore()
    private let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
    private var backgroundTask: Task<Void, Never>?
    private let locationManager = CLLocationManager()
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startBackgroundUpdates() {
        // Request HealthKit authorization first
        Task {
            await requestHealthKitAuthorization()
            
            // Cancel any existing task
            backgroundTask?.cancel()
            
            // Start periodic updates every 15 minutes
            backgroundTask = Task {
                while !Task.isCancelled {
                    await updateSteps()
                    
                    // Wait 15 minutes before next update
                    try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                }
            }
            
            print("🔄 Background steps updater started")
        }
    }

    private func requestHealthKitAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit not available")
            return
        }
        
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let typesToRead: Set<HKObjectType> = [stepsType]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            print("✅ HealthKit authorized for background updates")
        } catch {
            print("❌ HealthKit authorization failed: \(error)")
        }
    }
    
    func stopBackgroundUpdates() {
        backgroundTask?.cancel()
        backgroundTask = nil
        print("⏹️ Background steps updater stopped")
    }
    
    private func updateSteps() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit not available")
            return
        }
        
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        // Query today's steps
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )
        
        let steps = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("❌ Steps query failed: \(error)")
                    continuation.resume(returning: 0)
                    return
                }
                
                let steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                continuation.resume(returning: steps)
            }
            
            healthStore.execute(query)
        }
        
        // Save to shared storage
        defaults?.set(steps, forKey: "widget_today_steps")
        
        // Force widget refresh
        WidgetCenter.shared.reloadAllTimelines()
        
        print("📊 Background updated steps: \(steps)")
    }
    
    // CLLocationManagerDelegate
    @objc func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            
            defaults?.set(location.coordinate.latitude, forKey: "user_latitude")
            defaults?.set(location.coordinate.longitude, forKey: "user_longitude")
            defaults?.synchronize()
            
            print("⌚️ Watch saved its own location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }
    
    @objc func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error)")
    }
}
