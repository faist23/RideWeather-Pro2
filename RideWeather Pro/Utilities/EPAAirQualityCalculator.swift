//
//  EPAAirQualityCalculator.swift
//  RideWeather Pro
//

import SwiftUI

/// US EPA Air Quality Index (0–500) computed from raw pollutant
/// concentrations, using the official EPA breakpoint tables (including the
/// 2024 revised PM2.5 breakpoints).
///
/// OpenWeather's own `aqi` field is a coarse 1–5 scale; this calculator
/// exists so the app can show the familiar EPA number ("434 – Hazardous")
/// that matches US air-quality warnings — for either weather provider, since
/// pollution data always comes from OpenWeather (WeatherKit has none).
///
/// Approximation: EPA breakpoints are defined over averaging periods
/// (24 h PM, 8 h O₃/CO, 1 h NO₂/SO₂). Like most consumer apps we apply
/// instantaneous hourly concentrations against them — good enough for a
/// go/no-go riding signal, not a regulatory NowCast implementation.
enum EPAAirQualityCalculator {

    struct Reading: Equatable {
        let aqi: Int              // 0–500, capped
        let category: Category
        let dominantPollutant: Pollutant
    }

    enum Pollutant: String {
        case pm25 = "PM2.5"
        case pm10 = "PM10"
        case ozone = "Ozone"
        case no2 = "NO₂"
        case so2 = "SO₂"
        case co = "CO"
    }

    /// EPA AQI categories with the standard EPA color convention.
    enum Category: Int, Comparable {
        case good
        case moderate
        case unhealthySensitive
        case unhealthy
        case veryUnhealthy
        case hazardous

        init(aqi: Int) {
            switch aqi {
            case ..<51: self = .good
            case ..<101: self = .moderate
            case ..<151: self = .unhealthySensitive
            case ..<201: self = .unhealthy
            case ..<301: self = .veryUnhealthy
            default: self = .hazardous
            }
        }

        static func < (lhs: Category, rhs: Category) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var displayName: String {
            switch self {
            case .good: return "Good"
            case .moderate: return "Moderate"
            case .unhealthySensitive: return "Unhealthy for Sensitive Groups"
            case .unhealthy: return "Unhealthy"
            case .veryUnhealthy: return "Very Unhealthy"
            case .hazardous: return "Hazardous"
            }
        }

        var color: Color {
            switch self {
            case .good: return .green
            case .moderate: return .yellow
            case .unhealthySensitive: return .orange
            case .unhealthy: return .red
            case .veryUnhealthy: return .purple
            case .hazardous: return Color(red: 126/255, green: 0/255, blue: 35/255) // EPA maroon
            }
        }

        /// Short rider-facing guidance for the category.
        var riderGuidance: String {
            switch self {
            case .good: return "Air quality is good for riding."
            case .moderate: return "Acceptable — unusually sensitive riders should watch for symptoms."
            case .unhealthySensitive: return "Sensitive riders should shorten or ease the ride."
            case .unhealthy: return "Consider rescheduling — cut intensity and duration."
            case .veryUnhealthy: return "Rescheduling strongly recommended — health risk for all riders."
            case .hazardous: return "Outdoor exercise not advised."
            }
        }
    }

    // MARK: - Computation

    /// EPA AQI from OpenWeather-style concentrations, all in µg/m³.
    /// Negative inputs clamp to 0; the result caps at 500. The reported AQI
    /// is the worst pollutant's sub-index, per EPA convention.
    static func reading(pm25: Double, pm10: Double, o3: Double, no2: Double, so2: Double, co: Double) -> Reading {
        // Gas breakpoints are in ppm/ppb; convert from µg/m³ at 25 °C, 1 atm:
        // ppb = µg/m³ × 24.45 / molecular weight.
        let o3Ppm = max(o3, 0) * 24.45 / 48.00 / 1000
        let no2Ppb = max(no2, 0) * 24.45 / 46.01
        let so2Ppb = max(so2, 0) * 24.45 / 64.07
        let coPpm = max(co, 0) * 24.45 / 28.01 / 1000

        // Truncate to each table's precision (EPA rule); truncation also
        // closes the gaps between breakpoint rows (e.g. 9.0 → 9.1).
        let subIndices: [(Pollutant, Int?)] = [
            (.pm25, subIndex(truncate(max(pm25, 0), decimals: 1), in: Self.pm25Breakpoints)),
            (.pm10, subIndex(truncate(max(pm10, 0), decimals: 0), in: Self.pm10Breakpoints)),
            (.ozone, subIndex(truncate(o3Ppm, decimals: 3), in: Self.o3Breakpoints)),
            (.no2, subIndex(truncate(no2Ppb, decimals: 0), in: Self.no2Breakpoints)),
            (.so2, subIndex(truncate(so2Ppb, decimals: 0), in: Self.so2Breakpoints)),
            (.co, subIndex(truncate(coPpm, decimals: 1), in: Self.coBreakpoints)),
        ]

        var worstPollutant = Pollutant.pm25
        var worstIndex = 0
        for (pollutant, index) in subIndices {
            if let index, index > worstIndex {
                worstIndex = index
                worstPollutant = pollutant
            }
        }

        let aqi = min(worstIndex, 500)
        return Reading(aqi: aqi, category: Category(aqi: aqi), dominantPollutant: worstPollutant)
    }

    // MARK: - Breakpoint tables

    private struct Breakpoint {
        let cLow: Double
        let cHigh: Double
        let iLow: Double
        let iHigh: Double
    }

    /// Linear interpolation within the row containing `c`; concentrations
    /// above the top row peg to the 500 ceiling.
    private static func subIndex(_ c: Double, in table: [Breakpoint]) -> Int? {
        for row in table where c >= row.cLow && c <= row.cHigh {
            let value = (row.iHigh - row.iLow) / (row.cHigh - row.cLow) * (c - row.cLow) + row.iLow
            return Int(value.rounded())
        }
        if let top = table.last, c > top.cHigh {
            return 500
        }
        return nil
    }

    private static func truncate(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10.0, Double(decimals))
        return (value * factor).rounded(.down) / factor
    }

    // PM2.5, µg/m³ — 2024 revised table.
    private static let pm25Breakpoints = [
        Breakpoint(cLow: 0.0, cHigh: 9.0, iLow: 0, iHigh: 50),
        Breakpoint(cLow: 9.1, cHigh: 35.4, iLow: 51, iHigh: 100),
        Breakpoint(cLow: 35.5, cHigh: 55.4, iLow: 101, iHigh: 150),
        Breakpoint(cLow: 55.5, cHigh: 125.4, iLow: 151, iHigh: 200),
        Breakpoint(cLow: 125.5, cHigh: 225.4, iLow: 201, iHigh: 300),
        Breakpoint(cLow: 225.5, cHigh: 325.4, iLow: 301, iHigh: 500),
    ]

    // PM10, µg/m³.
    private static let pm10Breakpoints = [
        Breakpoint(cLow: 0, cHigh: 54, iLow: 0, iHigh: 50),
        Breakpoint(cLow: 55, cHigh: 154, iLow: 51, iHigh: 100),
        Breakpoint(cLow: 155, cHigh: 254, iLow: 101, iHigh: 150),
        Breakpoint(cLow: 255, cHigh: 354, iLow: 151, iHigh: 200),
        Breakpoint(cLow: 355, cHigh: 424, iLow: 201, iHigh: 300),
        Breakpoint(cLow: 425, cHigh: 604, iLow: 301, iHigh: 500),
    ]

    // O₃, ppm. 8-hour table through 300; 1-hour rows above (documented
    // approximation for instantaneous readings).
    private static let o3Breakpoints = [
        Breakpoint(cLow: 0.000, cHigh: 0.054, iLow: 0, iHigh: 50),
        Breakpoint(cLow: 0.055, cHigh: 0.070, iLow: 51, iHigh: 100),
        Breakpoint(cLow: 0.071, cHigh: 0.085, iLow: 101, iHigh: 150),
        Breakpoint(cLow: 0.086, cHigh: 0.105, iLow: 151, iHigh: 200),
        Breakpoint(cLow: 0.106, cHigh: 0.200, iLow: 201, iHigh: 300),
        Breakpoint(cLow: 0.201, cHigh: 0.604, iLow: 301, iHigh: 500),
    ]

    // NO₂, ppb (1-hour).
    private static let no2Breakpoints = [
        Breakpoint(cLow: 0, cHigh: 53, iLow: 0, iHigh: 50),
        Breakpoint(cLow: 54, cHigh: 100, iLow: 51, iHigh: 100),
        Breakpoint(cLow: 101, cHigh: 360, iLow: 101, iHigh: 150),
        Breakpoint(cLow: 361, cHigh: 649, iLow: 151, iHigh: 200),
        Breakpoint(cLow: 650, cHigh: 1249, iLow: 201, iHigh: 300),
        Breakpoint(cLow: 1250, cHigh: 2049, iLow: 301, iHigh: 500),
    ]

    // SO₂, ppb (1-hour; 24-hour rows above 300).
    private static let so2Breakpoints = [
        Breakpoint(cLow: 0, cHigh: 35, iLow: 0, iHigh: 50),
        Breakpoint(cLow: 36, cHigh: 75, iLow: 51, iHigh: 100),
        Breakpoint(cLow: 76, cHigh: 185, iLow: 101, iHigh: 150),
        Breakpoint(cLow: 186, cHigh: 304, iLow: 151, iHigh: 200),
        Breakpoint(cLow: 305, cHigh: 604, iLow: 201, iHigh: 300),
        Breakpoint(cLow: 605, cHigh: 1004, iLow: 301, iHigh: 500),
    ]

    // CO, ppm (8-hour).
    private static let coBreakpoints = [
        Breakpoint(cLow: 0.0, cHigh: 4.4, iLow: 0, iHigh: 50),
        Breakpoint(cLow: 4.5, cHigh: 9.4, iLow: 51, iHigh: 100),
        Breakpoint(cLow: 9.5, cHigh: 12.4, iLow: 101, iHigh: 150),
        Breakpoint(cLow: 12.5, cHigh: 15.4, iLow: 151, iHigh: 200),
        Breakpoint(cLow: 15.5, cHigh: 30.4, iLow: 201, iHigh: 300),
        Breakpoint(cLow: 30.5, cHigh: 50.4, iLow: 301, iHigh: 500),
    ]
}

// MARK: - Route summary

/// Worst-hour EPA air quality over a planned ride's time window.
struct RouteAirQualitySummary: Equatable {
    let aqi: Int
    let category: EPAAirQualityCalculator.Category
    let dominantPollutant: EPAAirQualityCalculator.Pollutant
    let windowStart: Date
    let windowEnd: Date

    /// Warning banner appears at Unhealthy (EPA ≥ 151) or worse.
    var showsWarningBanner: Bool { aqi >= 151 }
}
