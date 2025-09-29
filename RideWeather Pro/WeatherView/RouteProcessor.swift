//
//  RouteProcessor.swift
//

import Foundation
import CoreLocation

actor RouteProcessor {
    func selectKeyPoints(from points: [CLLocationCoordinate2D], maxPoints: Int) async -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var keyPoints = [points.first!]
        let halfwayIndex = points.count / 2
        let halfwayPoint = points[halfwayIndex]

        if maxPoints >= 3 {
            let remainingSlots = maxPoints - 3
            if remainingSlots > 0 {
                let before = remainingSlots / 2
                if before > 0 {
                    let stepBefore = Double(halfwayIndex-1)/Double(before+1)
                    for i in 1...before {
                        let idx = Int(round(Double(i)*stepBefore))
                        if idx > 0 && idx < halfwayIndex { keyPoints.append(points[idx]) }
                    }
                }
                keyPoints.append(halfwayPoint)
                let after = remainingSlots - before
                if after > 0 {
                    let stepAfter = Double(points.count-1-halfwayIndex)/Double(after+1)
                    for i in 1...after {
                        let idx = halfwayIndex+Int(round(Double(i)*stepAfter))
                        if idx < points.count-1 { keyPoints.append(points[idx]) }
                    }
                }
            } else { keyPoints.append(halfwayPoint) }
        }
        keyPoints.append(points.last!)
        return keyPoints.sorted {
            guard let i1 = points.firstIndex(of: $0), let i2 = points.firstIndex(of: $1) else { return false }
            return i1 < i2
        }
    }

    func calculateETAs(for points: [CLLocationCoordinate2D], rideDate: Date, avgSpeed: Double) async -> [(coordinate: CLLocationCoordinate2D, distance: Double, eta: Date)] {
        guard !points.isEmpty else { return [] }
        var results: [(CLLocationCoordinate2D, Double, Date)] = []
        var cumulative: Double = 0
        var prev = CLLocation(latitude: points.first!.latitude, longitude: points.first!.longitude)

        results.append((points.first!, 0, rideDate))

        for i in 1..<points.count {
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let segment = curr.distance(from: prev)
            cumulative += segment
            let eta = results.last!.2.addingTimeInterval(segment/avgSpeed)
            results.append((points[i], cumulative, eta))
            prev = curr
        }
        return results
    }
}
