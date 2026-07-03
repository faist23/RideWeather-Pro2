//
//  HeatIndexCalculator.swift
//  RideWeatherWatch Watch App
//
//  Watch-target copy of the NWS heat index calculator in
//  RideWeather Pro/Utilities/HeatIndexCalculator.swift — keep the
//  algorithm and category bands in sync with the iOS version.
//

import SwiftUI

/// NWS heat index (Rothfusz 1990 regression on Steadman 1979).
/// The watch's own weather fetch is always Fahrenheit, so this copy
/// exposes a °F-only convenience instead of the iOS unit-aware one.
enum HeatIndexCalculator {

    /// NWS heat advisory categories.
    enum Category {
        case caution        // 80–90 °F
        case extremeCaution // 90–103 °F
        case danger         // 103–125 °F
        case extremeDanger  // 125 °F +

        /// Category for a heat index in °F, or nil below the 80 °F floor.
        init?(heatIndexF: Double) {
            switch heatIndexF {
            case ..<80: return nil
            case ..<90: self = .caution
            case ..<103: self = .extremeCaution
            case ..<125: self = .danger
            default: self = .extremeDanger
            }
        }

        /// Stable rank (1–4) matching the iOS side's payload encoding.
        var severityRank: Int {
            switch self {
            case .caution: return 1
            case .extremeCaution: return 2
            case .danger: return 3
            case .extremeDanger: return 4
            }
        }

        init?(severityRank: Int) {
            switch severityRank {
            case 1: self = .caution
            case 2: self = .extremeCaution
            case 3: self = .danger
            case 4: self = .extremeDanger
            default: return nil
            }
        }

        var label: String {
            switch self {
            case .caution: return "Caution"
            case .extremeCaution: return "Extreme Caution"
            case .danger: return "Danger"
            case .extremeDanger: return "Extreme Danger"
            }
        }

        var color: Color {
            switch self {
            case .caution: return .yellow
            case .extremeCaution: return .orange
            case .danger: return .red
            case .extremeDanger: return .purple
            }
        }
    }

    /// The result of a heat index calculation, in °F.
    struct Reading {
        let value: Double
        let category: Category
    }

    /// Heat index for a °F temperature and relative humidity in percent,
    /// or nil when it doesn't apply (heat index below 80 °F).
    static func reading(temperatureF: Double, humidity: Int) -> Reading? {
        let hiF = heatIndexF(temperatureF: temperatureF, relativeHumidity: Double(humidity))
        guard let category = Category(heatIndexF: hiF) else { return nil }
        return Reading(value: hiF, category: category)
    }

    /// Full NWS algorithm: Steadman's simple formula averaged with the
    /// temperature; when that average is 80 °F or higher, the Rothfusz
    /// regression with the low- and high-humidity adjustment terms.
    static func heatIndexF(temperatureF: Double, relativeHumidity: Double) -> Double {
        let T = temperatureF
        let RH = min(max(relativeHumidity, 0), 100)

        let simple = 0.5 * (T + 61.0 + (T - 68.0) * 1.2 + RH * 0.094)
        let averaged = (simple + T) / 2

        guard averaged >= 80.0 else { return averaged }

        var hi = -42.379
            + 2.04901523 * T
            + 10.14333127 * RH
            - 0.22475541 * T * RH
            - 6.83783e-3 * T * T
            - 5.481717e-2 * RH * RH
            + 1.22874e-3 * T * T * RH
            + 8.5282e-4 * T * RH * RH
            - 1.99e-6 * T * T * RH * RH

        if RH < 13, T >= 80, T <= 112 {
            hi -= ((13 - RH) / 4) * ((17 - abs(T - 95)) / 17).squareRoot()
        } else if RH > 85, T >= 80, T <= 87 {
            hi += ((RH - 85) / 10) * ((87 - T) / 5)
        }

        return hi
    }
}
