//
//  BackgroundWatchUpdater.swift
//  RideWeatherWatch Watch App
//

import Foundation
import HealthKit
import WidgetKit
import CoreLocation
import WatchKit

@MainActor
class BackgroundWatchUpdater: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundWatchUpdater()
    private let healthStore = HKHealthStore()
    private let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
    private let locationManager = CLLocationManager()
    
    private override init() {
        super.init()
        locationManager.delegate = self
        // No auto-request here to avoid spamming
    }
    
    func startBackgroundUpdates() {
        // Request HealthKit authorization first
        Task {
            await requestHealthKitAuthorization()
            
            // Schedule the first refresh
            scheduleNextBackgroundRefresh()
            
            print("🔄 Background watch updater initialized via WKBackgroundTask")
        }
    }
    
    func scheduleNextBackgroundRefresh() {
        let nextRefreshDate = Date().addingTimeInterval(15 * 60) // 15 minutes
        
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: nextRefreshDate,
            userInfo: nil
        ) { error in
            if let error = error {
                print("❌ Failed to schedule background refresh: \(error.localizedDescription)")
            } else {
                print("📅 Next background refresh scheduled for \(nextRefreshDate.formatted(date: .omitted, time: .shortened))")
            }
        }
    }
    
    func handleBackgroundTask() async {
        print("🛠 Handling background app refresh")
        
        // Perform updates
        await updateSteps()
        await updateWeather()
        
        // Schedule the next one
        scheduleNextBackgroundRefresh()
    }

    private func updateWeather() async {
        // Use the watch's last saved location
        let lat = defaults?.double(forKey: "user_latitude") ?? 0
        let lon = defaults?.double(forKey: "user_longitude") ?? 0
        
        guard lat != 0 && lon != 0 else {
            print("⚠️ Skipping background weather update: No location saved in App Group")
            // Try to trigger a one-shot location update for next time
            locationManager.requestLocation()
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        
        do {
            print("⌚️ Background: Fetching weather for \(lat), \(lon)...")
            let result = try await WatchWeatherService.shared.fetchWeather(for: coordinate)
            print("⌚️ Background: Fetch complete. Provider: \(defaults?.string(forKey: "appSettings.weatherProvider") ?? "apple"), Alerts: \(result.alerts.count)")
            
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

            // NEW: Prune past hours immediately
            let prunedSummary = WatchSessionManager.shared.prunePastHours(summary)

            if let data = try? JSONEncoder().encode(prunedSummary) {
                defaults?.set(data, forKey: "widget_weather_summary")
                defaults?.synchronize()
                print("✅ Background: Weather summary saved to App Group (Alert Severity: \(result.alerts.first?.severity.rawValue ?? "none"))")
            }

            // Update the live session
            WatchSessionManager.shared.weatherSummary = prunedSummary
            WatchSessionManager.shared.updateWeatherAlerts(result.alerts)
            
            // Force widget refresh
            WidgetCenter.shared.reloadAllTimelines()
            print("✅ Background: All systems synced. Next refresh in 15 mins.")
        } catch {
            print("❌ Background: Weather update failed: \(error)")
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
        defaults?.synchronize()
        
        print("📊 Background: Updated steps: \(steps)")
    }
    
    // CLLocationManagerDelegate
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
        defaults?.set(location.coordinate.latitude, forKey: "user_latitude")
        defaults?.set(location.coordinate.longitude, forKey: "user_longitude")
        defaults?.synchronize()
        
        print("⌚️ Watch saved updated location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error)")
    }
}
