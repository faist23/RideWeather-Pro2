//
//  ViewHelpers.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//


import SwiftUI

// A key to track the scroll position of a ScrollView
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// An extension to clamp a number within a specific range
extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
