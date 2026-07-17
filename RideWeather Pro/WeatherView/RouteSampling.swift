//
//  RouteSampling.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation

/// Index-based route sampling for the route-forecast weather fetch.
///
/// Sample points are chosen by index and carry their exact along-route
/// cumulative distance from a single polyline walk. This replaces the old
/// two-step approach (coordinate list → geometric re-matching against the
/// polyline), which had two silent failure modes: a coordinate-based dedupe
/// deleted the finish of loop routes (Strava saved loops repeat the start
/// coordinate exactly, capping a 42-mile loop at ~36 in analysis), and the
/// bounding-box segment matching could place a waypoint where the route
/// merely passes near it.
enum RouteSampler {

    struct SamplePoint {
        let coordinate: CLLocationCoordinate2D
        /// Meters from the route start, measured along the polyline (scaled
        /// to the provider's total when one is supplied).
        let distance: Double
    }

    /// Evenly index-samples up to `maxCount` points — always including the
    /// first and last, even when they share a coordinate (loops do) — with
    /// exact cumulative distances. When `authoritativeTotal` is provided
    /// (e.g. Strava's own measured route distance), per-point distances are
    /// scaled so the final point matches it exactly: chord-summing a GPS
    /// trace always slightly undershoots the true ridden distance.
    static func samplePoints(
        from route: [CLLocationCoordinate2D],
        maxCount: Int = 8,
        authoritativeTotal: Double? = nil
    ) -> [SamplePoint] {
        guard !route.isEmpty, maxCount > 1 else {
            return route.first.map { [SamplePoint(coordinate: $0, distance: 0)] } ?? []
        }

        // One walk over the polyline for cumulative distances.
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(route.count)
        for i in 1..<route.count {
            let previous = CLLocation(latitude: route[i - 1].latitude, longitude: route[i - 1].longitude)
            let current = CLLocation(latitude: route[i].latitude, longitude: route[i].longitude)
            cumulative.append(cumulative[i - 1] + current.distance(from: previous))
        }

        let polylineTotal = cumulative[cumulative.count - 1]
        let scale: Double
        if let authoritativeTotal, authoritativeTotal > 0, polylineTotal > 0 {
            scale = authoritativeTotal / polylineTotal
        } else {
            scale = 1
        }

        let indices: [Int]
        if route.count <= maxCount {
            indices = Array(route.indices)
        } else {
            let step = Double(route.count - 1) / Double(maxCount - 1)
            // Distinct indices only (rounding can collide on short routes);
            // never dedupe by coordinate — loops legitimately repeat them.
            var seen = Set<Int>()
            indices = (0..<maxCount)
                .map { Int((Double($0) * step).rounded()) }
                .filter { seen.insert($0).inserted }
        }

        return indices.map { SamplePoint(coordinate: route[$0], distance: cumulative[$0] * scale) }
    }
}
