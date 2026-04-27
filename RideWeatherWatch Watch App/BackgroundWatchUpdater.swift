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
class BackgroundWatchUpdater: NSObject {
    static let shared = BackgroundWatchUpdater()
    private let healthStore = HKHealthStore()
    private let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")

    private override init() {
        super.init()
    }

    func startBackgroundUpdates() {
        Task {
            await requestHealthKitAuthorization()
            scheduleNextBackgroundRefresh(success: true)
            print("🔄 Background watch updater initialized")
        }
    }

    // MARK: - Scheduling

    func scheduleNextBackgroundRefresh(success: Bool = true) {
        // Back off to 30 min on failure so a down API doesn't burn the daily budget.
        let interval: TimeInterval = success ? 15 * 60 : 30 * 60
        let nextRefreshDate = Date().addingTimeInterval(interval)

        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: nextRefreshDate,
            userInfo: nil
        ) { error in
            if let error = error {
                print("❌ Failed to schedule background refresh: \(error.localizedDescription)")
            } else {
                print("📅 Next background refresh in \(success ? 15 : 30) min")
            }
        }
    }

    // MARK: - Background Task Entry Point

    func handleBackgroundTask() async {
        print("🛠 Handling background app refresh")
        defaults?.set(Date(), forKey: "last_background_refresh")

        var success = false
        // defer guarantees scheduling even if the task is killed mid-flight.
        defer { scheduleNextBackgroundRefresh(success: success) }

        await updateSteps()
        success = await updateWeather()
    }

    // MARK: - Weather

    private func updateWeather() async -> Bool {
        // Always try a fresh one-shot location fix first (8-second budget).
        // Falls back to cached App Group coordinates on timeout or GPS failure.
        let freshLocation = await WatchLocationManager.shared.requestLocationAsync(timeout: 8.0)

        let coordinate: CLLocationCoordinate2D
        if let loc = freshLocation {
            coordinate = loc.coordinate
            print("⌚️ Background: Fresh location \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
        } else {
            let lat = defaults?.double(forKey: "user_latitude") ?? 0
            let lon = defaults?.double(forKey: "user_longitude") ?? 0
            guard lat != 0 && lon != 0 else {
                print("⚠️ Background: No location available — skipping weather update")
                return false
            }
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            print("⌚️ Background: Location timeout, using cached \(lat), \(lon)")
        }

        do {
            let result = try await WatchWeatherService.shared.fetchWeather(for: coordinate)
            print("⌚️ Background: Fetch complete. Alerts: \(result.alerts.count)")

            let summary = SharedWeatherSummary.make(from: result.data, alert: result.alerts.first, hourly: result.hourly, nextHourSummary: result.nextHourSummary)

            let prunedSummary = WatchSessionManager.shared.prunePastHours(summary)

            if let data = try? JSONEncoder().encode(prunedSummary) {
                defaults?.set(data, forKey: "widget_weather_summary")
                defaults?.synchronize()
            }

            WatchSessionManager.shared.weatherSummary = prunedSummary
            WatchSessionManager.shared.updateWeatherAlerts(result.alerts)
            WidgetCenter.shared.reloadAllTimelines()

            print("✅ Background: All systems synced.")
            return true
        } catch {
            print("❌ Background: Weather update failed: \(error)")
            return false
        }
    }

    // MARK: - HealthKit

    private func requestHealthKitAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepsType])
        } catch {
            print("❌ HealthKit authorization failed: \(error)")
        }
    }

    private func updateSteps() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

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
                continuation.resume(returning: Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0))
            }
            healthStore.execute(query)
        }

        defaults?.set(steps, forKey: "widget_today_steps")
        defaults?.synchronize()
        print("📊 Background: Updated steps: \(steps)")
    }
}
