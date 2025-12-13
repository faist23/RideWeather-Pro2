//
//  UIState.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//

import Foundation

enum UIState: Equatable {
    case loading
    case loaded
    case error(String)
    case parsing(Double)

    static func == (lhs: UIState, rhs: UIState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.loaded, .loaded):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        case (.parsing(let a), .parsing(let b)):
            return abs(a - b) < 0.001
        default: return false
        }
    }
}
