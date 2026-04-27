//
//  MockCLLocationManager.swift
//  RideWeatherWatch Watch App
//
//  Test-only subclass of CLLocationManager.
//  Used by WatchWeatherTests to inject controlled location behavior
//  without requiring GPS hardware.
//
//  Usage:
//    let mock = MockCLLocationManager()
//    mock.simulatedLocation = CLLocation(latitude: 37.33, longitude: -122.03)
//    let manager = WatchLocationManager(manager: mock)
//

import CoreLocation
import Foundation

#if DEBUG
class MockCLLocationManager: CLLocationManager {
    var requestLocationCallCount = 0
    var requestWhenInUseCallCount = 0

    /// Set before calling requestLocation(). If non-nil, the delegate receives
    /// didUpdateLocations synchronously on the next run loop tick.
    var simulatedLocation: CLLocation?

    /// If true, the delegate receives didFailWithError instead.
    var shouldFail = false

    override func requestLocation() {
        requestLocationCallCount += 1
        guard !shouldFail else {
            DispatchQueue.main.async {
                self.delegate?.locationManager?(self, didFailWithError: MockLocationError.simulatedFailure)
            }
            return
        }
        if let location = simulatedLocation {
            DispatchQueue.main.async {
                self.delegate?.locationManager?(self, didUpdateLocations: [location])
            }
        }
        // If simulatedLocation is nil, the delegate never fires — simulates a timeout.
    }

    override func requestWhenInUseAuthorization() {
        requestWhenInUseCallCount += 1
    }
}

enum MockLocationError: Error {
    case simulatedFailure
}
#endif
