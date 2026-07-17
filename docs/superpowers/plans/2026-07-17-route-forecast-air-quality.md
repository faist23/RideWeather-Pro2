# Route Forecast Air Quality Warning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The route forecast computes the US EPA AQI (0–500) for the ride's time window from OpenWeather's pollution forecast and shows a warning banner at Unhealthy+ levels plus an always-visible AQI chip.

**Architecture:** A pure `EPAAirQualityCalculator` utility (mirroring `HeatIndexCalculator`) converts OpenWeather pollutant concentrations to the EPA index. `WeatherViewModel.calculateAndFetchWeather()` fetches the pollution forecast once at the route start, evaluates the ride window's worst hour, and publishes a `RouteAirQualitySummary`. Two small SwiftUI views render it in the analysis dashboard.

**Tech Stack:** Swift / SwiftUI (iOS 26+), OpenWeather `/air_pollution/forecast` REST endpoint, existing `WeatherService` NSCache-based caching.

**Spec:** `docs/superpowers/specs/2026-07-17-route-forecast-air-quality-design.md`

## Global Constraints

- Do not modify `.pbxproj` — synced folder groups auto-add new files under `RideWeather Pro/`.
- No new SPM/CocoaPods dependencies.
- No force-unwraps (`!`); handle optionals with `guard let`/`if let`.
- Never hardcode API keys — `WeatherService` already reads the OpenWeather key; reuse it.
- AQI always comes from OpenWeather regardless of the selected weather provider (WeatherKit has no air-quality data).
- Pollution fetch failure must **never** block or fail the route forecast — nil summary, log, move on.
- There is no iOS unit-test target; Task 1's calculator is verified via a standalone `swiftc` harness in the scratchpad; Tasks 2–4 are verified by building the `RideWeather Pro` scheme:
  ```sh
  xcodebuild build -scheme "RideWeather Pro" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug
  ```
  A `No such module 'FitFileParser'` error from SourceKit is an indexer artifact only; the build itself resolves SPM fine.
- Scratchpad directory for harness files: `/private/tmp/claude-501/-Users-craigfaist-Desktop-weatherApp-rideweather-pro2/c0531788-4f58-46bf-9588-a34872d76203/scratchpad`

---

### Task 1: EPA AQI calculator

**Files:**
- Create: `RideWeather Pro/Utilities/EPAAirQualityCalculator.swift`
- Test: `<scratchpad>/aqi-harness/main.swift` (standalone `swiftc` harness; not part of the app)

**Interfaces:**
- Consumes: nothing (pure Foundation/SwiftUI).
- Produces:
  - `EPAAirQualityCalculator.reading(pm25:pm10:o3:no2:so2:co:) -> Reading` — all parameters `Double` in µg/m³ (OpenWeather's units).
  - `EPAAirQualityCalculator.Reading` — `aqi: Int` (0–500), `category: Category`, `dominantPollutant: Pollutant`.
  - `EPAAirQualityCalculator.Category` — `Int`-raw-value, `Comparable` enum: `.good/.moderate/.unhealthySensitive/.unhealthy/.veryUnhealthy/.hazardous` with `displayName: String`, `color: Color`, `riderGuidance: String`, `init(aqi: Int)`.
  - `EPAAirQualityCalculator.Pollutant` — `String`-raw-value enum: `.pm25/.pm10/.ozone/.no2/.so2/.co`.
  - `RouteAirQualitySummary` — `aqi: Int`, `category`, `dominantPollutant`, `windowStart: Date`, `windowEnd: Date`, `showsWarningBanner: Bool` (true when `aqi >= 151`). Lives in the same file.

- [ ] **Step 1: Write the failing harness**

Create `<scratchpad>/aqi-harness/main.swift`:

```swift
// Standalone verification harness for EPAAirQualityCalculator.
// Compile together with the app's calculator file via swiftc.

import Foundation

var failures = 0

func expect(_ name: String, aqi actual: Int, toBe expected: Int) {
    if actual != expected {
        print("FAIL \(name): aqi \(actual), expected \(expected)")
        failures += 1
    } else {
        print("pass \(name): aqi \(actual)")
    }
}

func expect(_ name: String, aqi actual: Int, in range: ClosedRange<Int>) {
    if !range.contains(actual) {
        print("FAIL \(name): aqi \(actual), expected \(range)")
        failures += 1
    } else {
        print("pass \(name): aqi \(actual)")
    }
}

func reading(pm25: Double = 0, pm10: Double = 0, o3: Double = 0,
             no2: Double = 0, so2: Double = 0, co: Double = 0) -> EPAAirQualityCalculator.Reading {
    EPAAirQualityCalculator.reading(pm25: pm25, pm10: pm10, o3: o3, no2: no2, so2: so2, co: co)
}

// 1. 2024 PM2.5 Good/Moderate boundary: 9.0 µg/m³ is exactly AQI 50.
let r1 = reading(pm25: 9.0)
expect("pm25 9.0 boundary", aqi: r1.aqi, toBe: 50)
assert(r1.category == .good, "expected .good, got \(r1.category)")

// 2. PM2.5 moderate ceiling: 35.4 µg/m³ → AQI 100.
let r2 = reading(pm25: 35.4)
expect("pm25 35.4 ceiling", aqi: r2.aqi, toBe: 100)
assert(r2.category == .moderate, "expected .moderate, got \(r2.category)")

// 3. Hazardous smoke event (mirrors the real AQI-434 day): 300 µg/m³ PM2.5.
let r3 = reading(pm25: 300.0)
expect("pm25 300 hazardous", aqi: r3.aqi, toBe: 449)
assert(r3.category == .hazardous, "expected .hazardous, got \(r3.category)")
assert(r3.dominantPollutant == .pm25)

// 4. Gas unit conversion: 200 µg/m³ O₃ ≈ 0.101 ppm → Unhealthy (~190).
let r4 = reading(o3: 200.0)
expect("o3 200 µg/m³ conversion", aqi: r4.aqi, in: 185...195)
assert(r4.category == .unhealthy, "expected .unhealthy, got \(r4.category)")
assert(r4.dominantPollutant == .ozone)

// 5. Max-of-subindices: high PM2.5 dominates modest other pollutants.
let r5 = reading(pm25: 150.0, pm10: 30.0, o3: 50.0)
expect("max of subindices", aqi: r5.aqi, toBe: 225)
assert(r5.dominantPollutant == .pm25)

// 6. Clean air → 0 / Good.
let r6 = reading()
expect("all zero", aqi: r6.aqi, toBe: 0)
assert(r6.category == .good)

// 7. Negative concentrations clamp to 0.
let r7 = reading(pm25: -5.0, o3: -1.0)
expect("negative clamps", aqi: r7.aqi, toBe: 0)

// 8. Absurd concentration caps at 500.
let r8 = reading(pm25: 5000.0)
expect("cap at 500", aqi: r8.aqi, toBe: 500)
assert(r8.category == .hazardous)

// 9. Banner threshold on the summary type.
let hazardous = RouteAirQualitySummary(aqi: 434, category: .hazardous, dominantPollutant: .pm25,
                                       windowStart: Date(), windowEnd: Date())
let moderate = RouteAirQualitySummary(aqi: 80, category: .moderate, dominantPollutant: .pm25,
                                      windowStart: Date(), windowEnd: Date())
assert(hazardous.showsWarningBanner)
assert(!moderate.showsWarningBanner)

// 10. Category ordering is Comparable.
assert(EPAAirQualityCalculator.Category.good < .hazardous)

if failures > 0 { print("\(failures) FAILURES"); exit(1) }
print("ALL PASS")
```

- [ ] **Step 2: Run harness to verify it fails**

```sh
cd "<scratchpad>/aqi-harness"
swiftc -o aqi-test main.swift "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2/RideWeather Pro/Utilities/EPAAirQualityCalculator.swift" && ./aqi-test
```

Expected: FAIL — compile error, `EPAAirQualityCalculator.swift` does not exist yet.

- [ ] **Step 3: Write the calculator**

Create `RideWeather Pro/Utilities/EPAAirQualityCalculator.swift`:

```swift
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
```

- [ ] **Step 4: Run harness to verify it passes**

```sh
cd "<scratchpad>/aqi-harness"
swiftc -o aqi-test main.swift "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2/RideWeather Pro/Utilities/EPAAirQualityCalculator.swift" && ./aqi-test
```

Expected: all `pass` lines, final line `ALL PASS`, exit 0. If any `FAIL` prints, fix the calculator (not the fixture) — the fixtures are derived from the EPA tables by hand.

- [ ] **Step 5: Verify the file also compiles inside the app**

```sh
cd "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2"
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
```

Expected: `BUILD SUCCEEDED` (synced folder groups pick the new file up automatically).

- [ ] **Step 6: Commit**

```bash
git add "RideWeather Pro/Utilities/EPAAirQualityCalculator.swift"
git commit -m "feat: EPA AQI calculator from OpenWeather pollutant concentrations

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Air-pollution forecast fetch (service + repository)

**Files:**
- Modify: `RideWeather Pro/WeatherService.swift` (insert after `fetchAirPollution`, which ends near line 185)
- Modify: `RideWeather Pro/WeatherView/WeatherRepository.swift` (insert after the existing `fetchAirPollution` passthrough at lines 80–83)

**Interfaces:**
- Consumes: existing `AirPollutionResponse` Codable models (`OpenWeatherAPIModels.swift:425+` — `list: [AirPollutionData]`, each with `dt: TimeInterval`, `main.aqi`, `components: PollutionComponents`; the forecast endpoint returns the identical shape with ~96 hourly entries). Existing private cache helpers `getCachedAirPollution(key:)` / `cacheAirPollution(key:airPollution:)`.
- Produces: `WeatherRepository.fetchAirPollutionForecast(lat: Double, lon: Double) async throws -> AirPollutionResponse` (Task 3 calls this).

- [ ] **Step 1: Add the service method**

In `RideWeather Pro/WeatherService.swift`, directly after the closing brace of `fetchAirPollution` (line 185), add:

```swift
    /// Hourly air-pollution forecast (~4 days out). Same response shape as
    /// the current-conditions endpoint, with one entry per forecast hour.
    func fetchAirPollutionForecast(lat: Double, lon: Double) async throws -> AirPollutionResponse {
        let cacheKey = "air_pollution_forecast_\(lat)_\(lon)"
        
        // Check cache first
        if let cachedData = await getCachedAirPollution(key: cacheKey),
           !cachedData.isExpired(maxAge: 3600) { // 1 hour cache
            return cachedData.airPollution
        }
        
        guard let url = URL(string: "\(baseWeatherURL)/air_pollution/forecast?lat=\(lat)&lon=\(lon)&appid=\(apiKey)") else {
            throw URLError(.badURL)
        }
        
        let response: AirPollutionResponse = try await fetchData(from: url)
        
        // Cache the result
        await cacheAirPollution(key: cacheKey, airPollution: response)
        
        return response
    }
```

- [ ] **Step 2: Add the repository passthrough**

In `RideWeather Pro/WeatherView/WeatherRepository.swift`, directly after the existing `fetchAirPollution` passthrough (line 83), add:

```swift
    // Air pollution forecast - delegates to service layer
    func fetchAirPollutionForecast(lat: Double, lon: Double) async throws -> AirPollutionResponse {
        return try await service.fetchAirPollutionForecast(lat: lat, lon: lon)
    }
```

- [ ] **Step 3: Build to verify**

```sh
cd "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2"
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add "RideWeather Pro/WeatherService.swift" "RideWeather Pro/WeatherView/WeatherRepository.swift"
git commit -m "feat: fetch OpenWeather hourly air-pollution forecast

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Route air-quality summary in WeatherViewModel

**Files:**
- Modify: `RideWeather Pro/WeatherView/WeatherViewModel.swift` (property near line 44; clear sites at lines ~252, ~513, ~943; new method after `calculateAndFetchWeather`)

**Interfaces:**
- Consumes: `WeatherRepository.fetchAirPollutionForecast(lat:lon:)` (Task 2), `EPAAirQualityCalculator.reading(...)` and `RouteAirQualitySummary` (Task 1), existing `weatherRepo`, `routePoints`, `rideDate`, `weatherDataForRoute` (sorted by distance; each point has `eta: Date`).
- Produces: `@Published var routeAirQuality: RouteAirQualitySummary?` (Task 4 reads this from the environment view model).

- [ ] **Step 1: Add the published property**

In `WeatherViewModel.swift`, after `@Published var weatherDataForRoute: [RouteWeatherPoint] = []` (line 44), add:

```swift
    @Published var routeAirQuality: RouteAirQualitySummary? = nil
```

- [ ] **Step 2: Clear it wherever route weather is cleared**

Three sites, each adding one line right after the `weatherDataForRoute` reset:

In `importRoute(from:)` (line ~252):
```swift
            weatherDataForRoute = []
            routeAirQuality = nil
```

In `calculateAndFetchWeather()` (line ~513):
```swift
        weatherDataForRoute = []
        routeAirQuality = nil
```

In `clearRoute()` (line ~943):
```swift
        weatherDataForRoute.removeAll()
        routeAirQuality = nil
```

- [ ] **Step 3: Compute the summary after route weather resolves**

In `calculateAndFetchWeather()`, after `self.uiState = .loaded` and before `await runDepartureTimeOptimization()` (line ~575), add:

```swift
        await updateRouteAirQuality()
```

Then add this method directly after the closing brace of `calculateAndFetchWeather()`:

```swift
    /// Fetches the pollution forecast at the route start and publishes the
    /// worst-hour EPA AQI over the ride window (departure → last point ETA).
    /// Air quality is regional, so one fetch covers the route; failures never
    /// block the forecast (summary just stays nil).
    private func updateRouteAirQuality() async {
        routeAirQuality = nil
        guard let startCoordinate = routePoints.first ?? weatherDataForRoute.first?.coordinate,
              let finishETA = weatherDataForRoute.last?.eta else { return }
        
        do {
            let forecast = try await weatherRepo.fetchAirPollutionForecast(
                lat: startCoordinate.latitude,
                lon: startCoordinate.longitude
            )
            
            // Pad by half an hour each side so the hourly entries bracketing
            // departure and finish are included.
            let windowStart = rideDate.addingTimeInterval(-1800).timeIntervalSince1970
            let windowEnd = finishETA.addingTimeInterval(1800).timeIntervalSince1970
            var entries = forecast.list.filter { $0.dt >= windowStart && $0.dt <= windowEnd }
            
            if entries.isEmpty {
                // Short ride inside a single forecast hour: use the nearest
                // entry if the ride is within the forecast horizon at all.
                let departure = rideDate.timeIntervalSince1970
                if let nearest = forecast.list.min(by: { abs($0.dt - departure) < abs($1.dt - departure) }),
                   abs(nearest.dt - departure) <= 3600 {
                    entries = [nearest]
                } else {
                    // Ride is beyond the ~4-day pollution forecast horizon —
                    // show nothing rather than stale current conditions.
                    return
                }
            }
            
            let readings = entries.map { entry in
                EPAAirQualityCalculator.reading(
                    pm25: entry.components.pm2_5,
                    pm10: entry.components.pm10,
                    o3: entry.components.o3,
                    no2: entry.components.no2,
                    so2: entry.components.so2,
                    co: entry.components.co
                )
            }
            
            guard let worst = readings.max(by: { $0.aqi < $1.aqi }) else { return }
            
            routeAirQuality = RouteAirQualitySummary(
                aqi: worst.aqi,
                category: worst.category,
                dominantPollutant: worst.dominantPollutant,
                windowStart: rideDate,
                windowEnd: finishETA
            )
        } catch {
            print("⚠️ Route air quality unavailable: \(error)")
        }
    }
```

- [ ] **Step 4: Build to verify**

```sh
cd "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2"
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add "RideWeather Pro/WeatherView/WeatherViewModel.swift"
git commit -m "feat: compute worst-hour EPA AQI for the planned ride window

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Banner and chip in the route analysis dashboard

**Files:**
- Create: `RideWeather Pro/RouteAnalytics/AirQualityViews.swift`
- Modify: `RideWeather Pro/RouteAnalytics/OptimizedUIComponents.swift` (`analysisContentView`, LazyVStack at lines ~179–186)

**Interfaces:**
- Consumes: `viewModel.routeAirQuality: RouteAirQualitySummary?` (Task 3), `RouteAirQualitySummary.showsWarningBanner`, `category.color/.displayName/.riderGuidance` (Task 1).
- Produces: `AirQualityWarningBanner(summary:)` and `AirQualityChipRow(summary:)` views.

- [ ] **Step 1: Create the views**

Create `RideWeather Pro/RouteAnalytics/AirQualityViews.swift`:

```swift
//
//  AirQualityViews.swift
//  RideWeather Pro
//
//  Route-forecast air quality UI: hazard banner + always-on summary chip.
//

import SwiftUI

/// Full-width warning banner shown when the ride window's AQI is
/// Unhealthy (≥ 151) or worse. Category colors at this level (red, purple,
/// EPA maroon) all carry white text.
struct AirQualityWarningBanner: View {
    let summary: RouteAirQualitySummary
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Air Quality: \(summary.aqi) – \(summary.category.displayName)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(summary.category.riderGuidance)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(summary.category.color, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Capsule chip matching the SunTimesRow style, visible at every AQI level.
struct AirQualityChipRow: View {
    let summary: RouteAirQualitySummary
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "aqi.medium")
                .font(.caption)
                .foregroundStyle(summary.category.color)
            
            Text("Air Quality: \(summary.aqi) – \(summary.category.displayName)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Wire into the analysis dashboard**

In `RideWeather Pro/RouteAnalytics/OptimizedUIComponents.swift`, `analysisContentView`, change the top of the `LazyVStack` (lines 179–186):

```swift
                LazyVStack(spacing: 20) {
                    if let airQuality = viewModel.routeAirQuality, airQuality.showsWarningBanner {
                        AirQualityWarningBanner(summary: airQuality)
                    }
                    
                    RouteInfoCardView(viewModel: viewModel)
                    
                    // Allows users to quickly check if their start time works with daylight
                    SunTimesRow(daylight: analysis.daylightAnalysis)
                    
                    if let airQuality = viewModel.routeAirQuality {
                        AirQualityChipRow(summary: airQuality)
                    }
                    
                    RouteSummaryCard.forForecast(viewModel: viewModel)
```

(The rest of the LazyVStack is unchanged.)

- [ ] **Step 3: Build to verify**

```sh
cd "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2"
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: End-to-end check in the simulator**

Run the app in the iPhone 17 Pro simulator, import any route on the Plan tab, and generate a forecast. Expected: the `AirQualityChipRow` capsule appears under the sunrise/sunset row showing the live EPA number and category (e.g. "Air Quality: 42 – Good" on a clean day). To visually confirm the banner path without hazardous air, temporarily hardcode `routeAirQuality = RouteAirQualitySummary(aqi: 434, category: .hazardous, dominantPollutant: .pm25, windowStart: Date(), windowEnd: Date())` at the end of `updateRouteAirQuality()`, observe the maroon banner ("Air Quality: 434 – Hazardous / Outdoor exercise not advised."), then **revert the hardcode** before committing (`git diff` must show no leftover fixture).

- [ ] **Step 5: Commit**

```bash
git add "RideWeather Pro/RouteAnalytics/AirQualityViews.swift" "RideWeather Pro/RouteAnalytics/OptimizedUIComponents.swift"
git commit -m "feat: air quality warning banner and chip in route forecast

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Spec coverage self-check

- EPA 0–500 scale from pollutant concentrations, 2024 PM2.5 table, unit conversion, truncation, max-of-subindices, clamping/capping → Task 1.
- Forecast endpoint at ride time, route-start fetch, ride-window worst hour, nearest-entry fallback, beyond-horizon → nil, failure never blocks → Tasks 2–3.
- Banner ≥ 151 + always-visible chip, WeatherAlert-style coloring, "Outdoor exercise not advised." at Hazardous → Tasks 1 (copy) and 4 (views).
- Provider-independence → inherent (OpenWeather service used unconditionally, per existing pattern).
- Clearing on import/reset/re-fetch → Task 3 Step 2.
- Non-goals (per-point AQI, watch payloads, Live Weather EPA display, optimizer weighting) → intentionally absent.
