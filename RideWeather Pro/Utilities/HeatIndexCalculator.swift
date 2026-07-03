//
//  HeatIndexCalculator.swift
//  RideWeather Pro
//

import SwiftUI

/// NWS heat index (Rothfusz 1990 regression on Steadman 1979).
///
/// Unlike the provider "feels like" values (Apple's `apparentTemperature`,
/// OpenWeather's `feels_like`), this is the official National Weather Service
/// heat index, so it matches NWS heat advisories and grows much more steeply
/// with humidity. Computed locally from temperature + relative humidity so both
/// weather providers produce identical values.
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

        /// Short rider-facing guidance for the category.
        var ridingAdvice: String {
            switch self {
            case .caution: return "Fatigue possible — stay hydrated."
            case .extremeCaution: return "Heat cramps and exhaustion possible — ease the pace, drink often."
            case .danger: return "Heat exhaustion likely — shorten the ride, seek shade."
            case .extremeDanger: return "Heat stroke risk — riding not advised."
            }
        }
    }

    /// The result of a heat index calculation, in the requested unit system.
    struct Reading {
        let value: Double
        let category: Category
    }

    /// Heat index in the user's unit system, or nil when it doesn't apply
    /// (heat index below 80 °F). `temperature` must be in the given unit
    /// system; `humidity` is relative humidity in percent (0–100).
    static func reading(temperature: Double, humidity: Int, units: UnitSystem) -> Reading? {
        let tempF = units == .metric ? temperature * 9 / 5 + 32 : temperature
        let hiF = heatIndexF(temperatureF: tempF, relativeHumidity: Double(humidity))
        guard let category = Category(heatIndexF: hiF) else { return nil }
        let value = units == .metric ? (hiF - 32) * 5 / 9 : hiF
        return Reading(value: value, category: category)
    }

    /// Full NWS algorithm: Steadman's simple formula averaged with the
    /// temperature; when that average is 80 °F or higher, the Rothfusz
    /// regression with the low- and high-humidity adjustment terms.
    /// Valid for relative humidity in 0–100 %.
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
