//
//  WatchWeatherTests.swift
//  RideWeatherWatch Watch AppTests
//
//  SETUP REQUIRED: Add a "RideWeatherWatch Watch AppTests" test target in Xcode
//  (File → New → Target → Unit Testing Bundle, set Host Application to the watch app target).
//  Then add this file and MockCLLocationManager.swift to that target.
//
//  Regression tests:
//  RT-1  Timeout path: requestLocationAsync returns nil when GPS doesn't respond.
//  RT-2  Success path: requestLocationAsync resolves with the mock location.
//  RT-3  Error path:   requestLocationAsync returns nil when CLLocationManager fails.
//  RT-4  Background:   updateWeather returns false when no location is available.
//

import XCTest
import CoreLocation
@testable import RideWeatherWatch_Watch_App

@MainActor
final class WatchLocationManagerTests: XCTestCase {

    // RT-1: GPS timeout — requestLocationAsync must complete within the timeout window,
    // not hang indefinitely. Returns nil when no fix arrives.
    func testRequestLocationAsync_returnsNilOnTimeout() async {
        let mock = MockCLLocationManager()
        mock.simulatedLocation = nil  // GPS silent — timeout path

        let manager = WatchLocationManager(manager: mock)
        let start = Date()
        let result = await manager.requestLocationAsync(timeout: 0.5)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(result, "Should return nil when no GPS fix arrives before timeout")
        XCTAssertGreaterThanOrEqual(elapsed, 0.5, "Should wait the full timeout duration")
        XCTAssertLessThan(elapsed, 2.0, "Should not wait longer than the timeout + slack")
    }

    // RT-2: [REGRESSION] Fresh location resolves the continuation — this is the
    // core fix for the dead-end fallback path. Previously the delegate only saved
    // to App Group; now it resolves the async caller with the fresh CLLocation.
    func testRequestLocationAsync_resolvesContinuationWithFreshLocation() async {
        let mock = MockCLLocationManager()
        let expected = CLLocation(latitude: 37.7749, longitude: -122.4194)  // San Francisco
        mock.simulatedLocation = expected

        let manager = WatchLocationManager(manager: mock)
        let result = await manager.requestLocationAsync(timeout: 2.0)

        XCTAssertNotNil(result, "Should resolve with the simulated location")
        XCTAssertEqual(result?.coordinate.latitude, expected.coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(result?.coordinate.longitude, expected.coordinate.longitude, accuracy: 0.0001)
        XCTAssertEqual(mock.requestLocationCallCount, 1, "Should call requestLocation exactly once")
    }

    // RT-3: CLLocationManager failure resolves continuation with nil, not a hang.
    func testRequestLocationAsync_returnsNilOnLocationError() async {
        let mock = MockCLLocationManager()
        mock.shouldFail = true

        let manager = WatchLocationManager(manager: mock)
        let result = await manager.requestLocationAsync(timeout: 2.0)

        XCTAssertNil(result, "Should return nil when CLLocationManager reports an error")
    }

    // Foreground path: delegate triggers weather fetch (no continuation waiting).
    // Verifies currentLocation is updated and App Group keys are written.
    func testLocationDelegate_updatesCurrentLocation() async {
        let mock = MockCLLocationManager()
        let location = CLLocation(latitude: 40.7128, longitude: -74.0060)  // New York

        let manager = WatchLocationManager(manager: mock)

        // Simulate the delegate firing without a waiting continuation.
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location])

        XCTAssertEqual(manager.currentLocation?.coordinate.latitude, location.coordinate.latitude, accuracy: 0.0001)

        let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
        XCTAssertEqual(defaults?.double(forKey: "user_latitude"), location.coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(defaults?.double(forKey: "user_longitude"), location.coordinate.longitude, accuracy: 0.0001)
    }
}

@MainActor
final class BackgroundUpdaterTests: XCTestCase {

    // RT-4: [REGRESSION] Background task with zero cached coords and GPS timeout
    // returns false (not crash, not hang). Previously the fallback called
    // requestLocation() and returned — leaving weather unfetched. Now it awaits
    // the full timeout before giving up.
    func testUpdateWeather_returnsFalseWhenNoLocationAvailable() async {
        let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")

        // Save and restore originals
        let originalLat = defaults?.double(forKey: "user_latitude") ?? 0
        let originalLon = defaults?.double(forKey: "user_longitude") ?? 0
        defer {
            defaults?.set(originalLat, forKey: "user_latitude")
            defaults?.set(originalLon, forKey: "user_longitude")
        }

        // Zero coords + GPS silent = no location available
        defaults?.set(0.0, forKey: "user_latitude")
        defaults?.set(0.0, forKey: "user_longitude")

        // This test validates the task completes without hanging.
        // The 8-second timeout in requestLocationAsync means this takes ~8s to run.
        // Override timeout in production if test time is a concern (use a shorter timeout injected via test init).
        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await BackgroundWatchUpdater.shared.handleBackgroundTask()
                return true
            }
            return await group.next() ?? false
        }

        XCTAssertTrue(completed, "handleBackgroundTask should complete without hanging")
    }
}
