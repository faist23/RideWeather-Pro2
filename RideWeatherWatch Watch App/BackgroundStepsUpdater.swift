//
//  BackgroundStepsUpdater.swift
//  RideWeatherWatch Watch App
//

import Foundation
import HealthKit
import WidgetKit
import CoreLocation

@MainActor
class BackgroundWatchUpdater: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundWatchUpdater()
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
                    // Update steps
                    await updateSteps()
                    
                    // Update weather
                    await updateWeather()
                    
                    // Wait 15 minutes before next update
                    try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                }
            }
            
            print("🔄 Background watch updater started (Steps + Weather)")
        }
    }

    private func updateWeather() async {
        // Use the watch's own location or the last saved location
        let lat = defaults?.double(forKey: "user_latitude") ?? 0
        let lon = defaults?.double(forKey: "user_longitude") ?? 0
        
        guard lat != 0 && lon != 0 else {
            print("⚠️ Skipping weather update: No location available")
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        
        do {
            let result = try await WatchWeatherService.shared.fetchWeather(for: coordinate)
            
            // Map to SharedWeatherSummary (matching Phone's structure for widget/detail view)
            let summary = SharedWeatherSummary(
                temperature: Int(result.data.temperature),
                feelsLike: Int(result.data.feelsLike),
                conditionIcon: result.data.condition,
                windSpeed: Int(result.data.windSpeed),
                windDirection: "N", // Direction mapping not available here, but icon/speed are
                pop: 0, // Fallback
                generatedAt: Date(),
                alertSeverity: result.alerts.first?.severity.rawValue,
                hourlyForecast: result.hourly,
                nextHourSummary: result.nextHourSummary
            )
            
            if let data = try? JSONEncoder().encode(summary) {
                defaults?.set(data, forKey: "widget_weather_summary")
                print("✅ Background weather updated successfully")
            }
            
            // Update UI
            WatchSessionManager.shared.updateWeatherAlerts(result.alerts)
            
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("❌ Background weather update failed: \(error)")
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
