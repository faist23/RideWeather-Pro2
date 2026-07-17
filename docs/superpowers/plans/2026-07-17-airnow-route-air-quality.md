# AirNow Route Air Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route forecast AQI comes from the official EPA AirNow feed (station data) with the existing OpenWeather model pipeline as fallback.

**Architecture:** A new `AirNowService` (WeatherService-style singleton, Foundation-only) fetches current observations and daily forecasts; a pure `AirNowRouteAQISelector` picks the max official AQI over the ride window; `WeatherViewModel.updateRouteAirQuality()` becomes an orchestrator that tries AirNow first and falls back to the extracted OpenWeather worst-hour path. `RouteAirQualitySummary` gains a `source` field.

**Tech Stack:** Swift (iOS 26+), AirNow REST API (`www.airnowapi.org/aq`), existing swiftc harness for pure logic.

**Spec:** `docs/superpowers/specs/2026-07-17-airnow-route-air-quality-design.md`

## Global Constraints

- Do not modify `.pbxproj` — synced folder groups auto-add new files under `RideWeather Pro/` (including `.plist` resources; `OpenWeather.plist` works the same way).
- No new SPM/CocoaPods dependencies. No force-unwraps (`!`).
- AirNow API key lives in `RideWeather Pro/AirNow.plist` under `AirNowApiKey` (value: `243D134D-8865-4863-8C8D-623ED20E468F`), loaded the same way `WeatherService` loads `OpenWeather.plist` — never hardcoded in Swift source.
- Air-quality failures must **never** block or fail the route forecast: AirNow miss → OpenWeather fallback; both miss → nil summary.
- Banner/chip UI, EPA calculator math, thresholds, and clearing sites are untouched by this plan.
- `AirNowService.swift` must stay Foundation-only (no SwiftUI import) so the swiftc harness can compile it.
- The working tree has unrelated uncommitted changes (including `CLAUDE.md`) — each task commits ONLY the files its commit step names.
- Verification: extend and run the swiftc harness at `<scratchpad>/aqi-harness/` (scratchpad root: `/private/tmp/claude-501/-Users-craigfaist-Desktop-weatherApp-rideweather-pro2/c0531788-4f58-46bf-9588-a34872d76203/scratchpad`), plus the app build:
  ```sh
  xcodebuild build -scheme "RideWeather Pro" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug
  ```
  SourceKit "Cannot find type …" editor diagnostics are known indexer artifacts in this repo; only the actual build result matters.

---

### Task 1: AirNow service, selector, and summary `source` field

**Files:**
- Create: `RideWeather Pro/AirNow.plist`
- Create: `RideWeather Pro/AirNowService.swift`
- Modify: `RideWeather Pro/Utilities/EPAAirQualityCalculator.swift` (add `AirQualitySource` + `source` field on `RouteAirQualitySummary`)
- Test: append to `<scratchpad>/aqi-harness/main.swift`; harness now compiles `AirNowService.swift` too

**Interfaces:**
- Consumes: `EPAAirQualityCalculator.Pollutant` (existing).
- Produces (Task 2 relies on these exact signatures):
  - `AirNowService.shared.fetchCurrentObservations(lat: Double, lon: Double) async throws -> [AirNowObservation]`
  - `AirNowService.shared.fetchForecast(lat: Double, lon: Double) async throws -> [AirNowForecastEntry]`
  - `AirNowRouteAQISelector.select(observations:forecasts:windowStart:windowEnd:now:calendar:) -> (aqi: Int, dominantPollutant: EPAAirQualityCalculator.Pollutant)?` (with `now: Date = Date()`, `calendar: Calendar = .current` defaults)
  - `AirNowObservation` / `AirNowForecastEntry` / `AirNowCategory` Codable structs (memberwise inits available)
  - `enum AirQualitySource { case airNow, openWeatherModel }` and `RouteAirQualitySummary.source: AirQualitySource` (a `var` defaulting to `.openWeatherModel`, so the existing memberwise construction in `WeatherViewModel` keeps compiling until Task 2 touches it)

- [ ] **Step 1: Create the plist**

Create `RideWeather Pro/AirNow.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AirNowApiKey</key>
	<string>243D134D-8865-4863-8C8D-623ED20E468F</string>
</dict>
</plist>
```

- [ ] **Step 2: Append failing selector tests to the harness**

Append to `<scratchpad>/aqi-harness/main.swift` (before the final `if failures > 0` block — move that block to stay last):

```swift
// MARK: - AirNowRouteAQISelector fixtures

let nyTZ = TimeZone(identifier: "America/New_York") ?? .current
var nyCal = Calendar(identifier: .gregorian)
nyCal.timeZone = nyTZ

func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
    guard let date = nyCal.date(from: c) else {
        print("FAIL fixture date \(y)-\(m)-\(d) \(h):\(min)"); failures += 1; return Date()
    }
    return date
}

func obs(_ p: String, _ aqi: Int) -> AirNowObservation {
    AirNowObservation(dateObserved: "2026-07-17", hourObserved: 11, localTimeZone: "EST",
                      reportingArea: "Columbus", stateCode: "OH", latitude: 39.989, longitude: -82.987,
                      parameterName: p, aqi: aqi, category: AirNowCategory(number: 5, name: "Very Unhealthy"))
}

func fcst(_ date: String, _ p: String, _ aqi: Int) -> AirNowForecastEntry {
    AirNowForecastEntry(dateIssue: "2026-07-17", dateForecast: date,
                        reportingArea: "Columbus", stateCode: "OH", latitude: 39.989, longitude: -82.987,
                        parameterName: p, aqi: aqi,
                        category: AirNowCategory(number: 2, name: "Moderate"),
                        actionDay: false, discussion: nil)
}

let now0717 = makeDate(2026, 7, 17, 12)

func expectSelect(_ name: String, _ result: (aqi: Int, dominantPollutant: EPAAirQualityCalculator.Pollutant)?,
                  aqi: Int?, pollutant: EPAAirQualityCalculator.Pollutant?) {
    switch (result, aqi) {
    case (nil, nil):
        print("pass \(name): nil as expected")
    case (let r?, let a?):
        if r.aqi == a && (pollutant == nil || r.dominantPollutant == pollutant) {
            print("pass \(name): aqi \(r.aqi) \(r.dominantPollutant)")
        } else {
            print("FAIL \(name): got (\(r.aqi), \(r.dominantPollutant)), expected (\(a), \(String(describing: pollutant)))")
            failures += 1
        }
    default:
        print("FAIL \(name): got \(String(describing: result)), expected aqi \(String(describing: aqi))")
        failures += 1
    }
}

// S1: ride starting 2h from now — observations included, max wins over today's forecast.
expectSelect("S1 obs beats forecast",
    AirNowRouteAQISelector.select(
        observations: [obs("PM2.5", 296), obs("O3", 47)],
        forecasts: [fcst("2026-07-17", "PM2.5", 201), fcst("2026-07-17", "O3", 51)],
        windowStart: makeDate(2026, 7, 17, 14), windowEnd: makeDate(2026, 7, 17, 17),
        now: now0717, calendar: nyCal),
    aqi: 296, pollutant: .pm25)

// S2: ride 2 days out — observations excluded (start > now + 3h), forecast for that date wins.
expectSelect("S2 future ride ignores current obs",
    AirNowRouteAQISelector.select(
        observations: [obs("PM2.5", 296)],
        forecasts: [fcst("2026-07-19", "PM2.5", 90), fcst("2026-07-19", "O3", 74), fcst("2026-07-17", "PM2.5", 201)],
        windowStart: makeDate(2026, 7, 19, 8), windowEnd: makeDate(2026, 7, 19, 11),
        now: now0717, calendar: nyCal),
    aqi: 90, pollutant: .pm25)

// S3: all matching forecast entries are AQI -1 and no eligible obs → nil (fallback).
expectSelect("S3 all -1 yields nil",
    AirNowRouteAQISelector.select(
        observations: [],
        forecasts: [fcst("2026-07-19", "PM2.5", -1), fcst("2026-07-19", "O3", -1)],
        windowStart: makeDate(2026, 7, 19, 8), windowEnd: makeDate(2026, 7, 19, 11),
        now: now0717, calendar: nyCal),
    aqi: nil, pollutant: nil)

// S4: DateForecast whitespace is tolerated.
expectSelect("S4 whitespace date matches",
    AirNowRouteAQISelector.select(
        observations: [],
        forecasts: [fcst(" 2026-07-19 ", "O3", 74)],
        windowStart: makeDate(2026, 7, 19, 8), windowEnd: makeDate(2026, 7, 19, 11),
        now: now0717, calendar: nyCal),
    aqi: 74, pollutant: .ozone)

// S5: ride beyond forecast horizon, no obs eligible → nil.
expectSelect("S5 beyond horizon nil",
    AirNowRouteAQISelector.select(
        observations: [obs("PM2.5", 296)],
        forecasts: [fcst("2026-07-17", "PM2.5", 201)],
        windowStart: makeDate(2026, 7, 25, 8), windowEnd: makeDate(2026, 7, 25, 11),
        now: now0717, calendar: nyCal),
    aqi: nil, pollutant: nil)

// S6: absurd AQI capped at 500.
expectSelect("S6 cap 500",
    AirNowRouteAQISelector.select(
        observations: [obs("PM2.5", 700)],
        forecasts: [],
        windowStart: makeDate(2026, 7, 17, 13), windowEnd: makeDate(2026, 7, 17, 15),
        now: now0717, calendar: nyCal),
    aqi: 500, pollutant: .pm25)

// S7: overnight window spans two calendar dates — both days' forecasts eligible.
expectSelect("S7 multi-day window",
    AirNowRouteAQISelector.select(
        observations: [],
        forecasts: [fcst("2026-07-18", "PM2.5", 81), fcst("2026-07-19", "O3", 90)],
        windowStart: makeDate(2026, 7, 18, 22), windowEnd: makeDate(2026, 7, 19, 2),
        now: now0717, calendar: nyCal),
    aqi: 90, pollutant: .ozone)

// S8: summary source field — defaults to the model source, explicit AirNow settable.
let defaultSource = RouteAirQualitySummary(aqi: 64, category: .moderate, dominantPollutant: .pm25,
                                           windowStart: Date(), windowEnd: Date())
assert(defaultSource.source == .openWeatherModel)
let airNowSource = RouteAirQualitySummary(aqi: 296, category: .veryUnhealthy, dominantPollutant: .pm25,
                                          windowStart: Date(), windowEnd: Date(), source: .airNow)
assert(airNowSource.source == .airNow)
print("pass S8 source field")
```

- [ ] **Step 3: Run harness to verify it fails**

```sh
cd "<scratchpad>/aqi-harness"
swiftc -o aqi-test main.swift \
  "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2/RideWeather Pro/Utilities/EPAAirQualityCalculator.swift" \
  "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2/RideWeather Pro/AirNowService.swift" && ./aqi-test
```

Expected: FAIL — `AirNowService.swift` does not exist / `AirNowRouteAQISelector` and `source:` unresolved.

- [ ] **Step 4: Add `AirQualitySource` and the `source` field**

In `RideWeather Pro/Utilities/EPAAirQualityCalculator.swift`, in the `// MARK: - Route summary` section, add above `RouteAirQualitySummary`:

```swift
/// Where a route air-quality summary came from: official EPA AirNow station
/// data, or the OpenWeather model pipeline (fallback — known to understate
/// smoke events).
enum AirQualitySource: Equatable {
    case airNow
    case openWeatherModel
}
```

And inside `RouteAirQualitySummary`, after `let windowEnd: Date`, add:

```swift
    var source: AirQualitySource = .openWeatherModel
```

(A `var` with a default keeps the field settable through the memberwise initializer while existing call sites compile unchanged.)

- [ ] **Step 5: Create the service**

Create `RideWeather Pro/AirNowService.swift`:

```swift
//
//  AirNowService.swift
//  RideWeather Pro
//

import Foundation

// MARK: - Models

struct AirNowObservation: Codable {
    let dateObserved: String
    let hourObserved: Int
    let localTimeZone: String
    let reportingArea: String
    let stateCode: String
    let latitude: Double
    let longitude: Double
    let parameterName: String
    let aqi: Int
    let category: AirNowCategory

    enum CodingKeys: String, CodingKey {
        case dateObserved = "DateObserved"
        case hourObserved = "HourObserved"
        case localTimeZone = "LocalTimeZone"
        case reportingArea = "ReportingArea"
        case stateCode = "StateCode"
        case latitude = "Latitude"
        case longitude = "Longitude"
        case parameterName = "ParameterName"
        case aqi = "AQI"
        case category = "Category"
    }
}

struct AirNowForecastEntry: Codable {
    let dateIssue: String
    let dateForecast: String
    let reportingArea: String
    let stateCode: String
    let latitude: Double
    let longitude: Double
    let parameterName: String
    let aqi: Int          // -1 means "not forecast" — filter before use
    let category: AirNowCategory
    let actionDay: Bool
    let discussion: String?

    enum CodingKeys: String, CodingKey {
        case dateIssue = "DateIssue"
        case dateForecast = "DateForecast"
        case reportingArea = "ReportingArea"
        case stateCode = "StateCode"
        case latitude = "Latitude"
        case longitude = "Longitude"
        case parameterName = "ParameterName"
        case aqi = "AQI"
        case category = "Category"
        case actionDay = "ActionDay"
        case discussion = "Discussion"
    }
}

struct AirNowCategory: Codable {
    let number: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case number = "Number"
        case name = "Name"
    }
}

// MARK: - Service

/// Official US EPA AirNow air quality: station-based NowCast observations and
/// daily per-pollutant AQI forecasts (~6 days). Station data captures smoke
/// events that model products (OpenWeather, CAMS) badly understate — during
/// the 2026-07-17 hazardous episode OpenWeather implied AQI 64 while AirNow
/// reported 296. US coverage only: an empty response means no reporting area
/// within range, and callers fall back to the OpenWeather pipeline.
final class AirNowService {
    static let shared = AirNowService()

    private var config: [String: String]?
    private var apiKey: String {
        return config?["AirNowApiKey"] ?? "INVALID_API"
    }
    private let baseURL = "https://www.airnowapi.org/aq"
    private let cache = NSCache<NSString, CachedAirNowData>()
    private let cacheMaxAge: TimeInterval = 1800 // 30 minutes

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    init() {
        loadConfig()
    }

    /// Current per-pollutant NowCast observations for the nearest reporting
    /// area (25-mile search radius). Empty when no US reporting area is near.
    func fetchCurrentObservations(lat: Double, lon: Double) async throws -> [AirNowObservation] {
        let cacheKey = "airnow_current_\(lat)_\(lon)" as NSString
        if let cached = cache.object(forKey: cacheKey),
           !cached.isExpired(maxAge: cacheMaxAge),
           let observations = cached.observations {
            return observations
        }

        guard let url = URL(string: "\(baseURL)/observation/latLong/current/?format=application/json&latitude=\(lat)&longitude=\(lon)&distance=25&API_KEY=\(apiKey)") else {
            throw URLError(.badURL)
        }

        let observations: [AirNowObservation] = try await fetchJSON(from: url)
        cache.setObject(CachedAirNowData(observations: observations, forecasts: nil), forKey: cacheKey)
        return observations
    }

    /// Daily per-pollutant AQI forecast (~6 days) for the nearest reporting
    /// area. Entries with `aqi == -1` carry no forecast value.
    func fetchForecast(lat: Double, lon: Double) async throws -> [AirNowForecastEntry] {
        let cacheKey = "airnow_forecast_\(lat)_\(lon)" as NSString
        if let cached = cache.object(forKey: cacheKey),
           !cached.isExpired(maxAge: cacheMaxAge),
           let forecasts = cached.forecasts {
            return forecasts
        }

        guard let url = URL(string: "\(baseURL)/forecast/latLong/?format=application/json&latitude=\(lat)&longitude=\(lon)&distance=25&API_KEY=\(apiKey)") else {
            throw URLError(.badURL)
        }

        let forecasts: [AirNowForecastEntry] = try await fetchJSON(from: url)
        cache.setObject(CachedAirNowData(observations: nil, forecasts: forecasts), forKey: cacheKey)
        return forecasts
    }

    // MARK: - Private helpers

    private func fetchJSON<T: Decodable>(from url: URL) async throws -> T {
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "AirNow", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 AirNowService: AirNow.plist not found or incorrectly formatted — AirNow disabled, OpenWeather fallback will be used.")
            config = nil
            return
        }
        config = dict
        if config?["AirNowApiKey"] == nil {
            print("🚨 AirNowService WARNING: AirNowApiKey missing in AirNow.plist!")
        }
    }
}

private final class CachedAirNowData {
    let observations: [AirNowObservation]?
    let forecasts: [AirNowForecastEntry]?
    let timestamp: Date

    init(observations: [AirNowObservation]?, forecasts: [AirNowForecastEntry]?) {
        self.observations = observations
        self.forecasts = forecasts
        self.timestamp = Date()
    }

    func isExpired(maxAge: TimeInterval) -> Bool {
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}

// MARK: - Route window selection

/// Picks the official AQI for a planned ride window from AirNow data:
/// daily forecast entries for the window's calendar dates, plus current
/// observations when the ride starts within 3 hours (or is underway).
/// The worst (max) AQI wins, per EPA convention.
enum AirNowRouteAQISelector {

    static func select(
        observations: [AirNowObservation],
        forecasts: [AirNowForecastEntry],
        windowStart: Date,
        windowEnd: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (aqi: Int, dominantPollutant: EPAAirQualityCalculator.Pollutant)? {
        let start = min(windowStart, windowEnd)
        let end = max(windowStart, windowEnd)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var windowDayStrings: Set<String> = [formatter.string(from: end)]
        var cursor = start
        while cursor <= end {
            windowDayStrings.insert(formatter.string(from: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        var candidates: [(aqi: Int, parameterName: String)] = []

        for entry in forecasts where entry.aqi >= 0 {
            let day = entry.dateForecast.trimmingCharacters(in: .whitespacesAndNewlines)
            if windowDayStrings.contains(day) {
                candidates.append((entry.aqi, entry.parameterName))
            }
        }

        // Include live observations for rides starting soon (or underway):
        // NowCast reflects conditions the daily forecast may lag behind.
        if start <= now.addingTimeInterval(3 * 3600) {
            for observation in observations where observation.aqi >= 0 {
                candidates.append((observation.aqi, observation.parameterName))
            }
        }

        guard let worst = candidates.max(by: { $0.aqi < $1.aqi }) else { return nil }
        return (min(worst.aqi, 500), pollutant(from: worst.parameterName))
    }

    private static func pollutant(from name: String) -> EPAAirQualityCalculator.Pollutant {
        switch name.trimmingCharacters(in: .whitespaces).uppercased() {
        case "PM2.5": return .pm25
        case "PM10": return .pm10
        case "O3", "OZONE": return .ozone
        case "NO2": return .no2
        case "SO2": return .so2
        case "CO": return .co
        // Unknown parameters still count toward the AQI; the label (not
        // currently rendered) defaults to the most common driver.
        default: return .pm25
        }
    }
}
```

- [ ] **Step 6: Run harness to verify it passes**

Same command as Step 3. Expected: all previous tests plus S1–S8 print `pass`, final `ALL PASS`, exit 0. Fix the implementation (not fixtures) on failure.

- [ ] **Step 7: Build the app**

```sh
cd "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2"
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add "RideWeather Pro/AirNow.plist" "RideWeather Pro/AirNowService.swift" "RideWeather Pro/Utilities/EPAAirQualityCalculator.swift"
git commit -m "feat: AirNow service, route-window AQI selector, summary source field

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: AirNow-first orchestration in WeatherViewModel

**Files:**
- Modify: `RideWeather Pro/WeatherView/WeatherRepository.swift` (passthroughs after the `fetchAirPollutionForecast` passthrough)
- Modify: `RideWeather Pro/WeatherView/WeatherViewModel.swift` (replace `updateRouteAirQuality()` with orchestrator + two extracted methods)

**Interfaces:**
- Consumes (from Task 1): `AirNowService.shared.fetchCurrentObservations(lat:lon:)`, `AirNowService.shared.fetchForecast(lat:lon:)`, `AirNowRouteAQISelector.select(observations:forecasts:windowStart:windowEnd:)` (default `now`/`calendar`), `AirQualitySource`, `RouteAirQualitySummary(… source:)`. Existing: `weatherRepo`, `rideDate`, `routePoints`, `weatherDataForRoute`, `EPAAirQualityCalculator`.
- Produces: no new public surface; `routeAirQuality` now carries `.airNow` or `.openWeatherModel` source.

- [ ] **Step 1: Add repository passthroughs**

In `RideWeather Pro/WeatherView/WeatherRepository.swift`, directly after the `fetchAirPollutionForecast` passthrough, add:

```swift
    // AirNow (official US EPA station data) - delegates to service layer
    func fetchAirNowObservations(lat: Double, lon: Double) async throws -> [AirNowObservation] {
        return try await AirNowService.shared.fetchCurrentObservations(lat: lat, lon: lon)
    }

    func fetchAirNowForecast(lat: Double, lon: Double) async throws -> [AirNowForecastEntry] {
        return try await AirNowService.shared.fetchForecast(lat: lat, lon: lon)
    }
```

- [ ] **Step 2: Replace `updateRouteAirQuality()` with the orchestrator**

In `RideWeather Pro/WeatherView/WeatherViewModel.swift`, replace the entire existing `updateRouteAirQuality()` method (from its `/// Fetches the pollution forecast…` doc comment through its closing brace) with the following three methods. The third method's body is the old method's body with three mechanical changes: the guards move to the orchestrator (coordinate/finishETA become parameters), assignments to `routeAirQuality` become `return`s, and the summary construction gains `source: .openWeatherModel`.

```swift
    /// Route air quality: official AirNow (US EPA station) data first, with
    /// the OpenWeather model pipeline as fallback — model products can
    /// understate smoke events by an order of magnitude. Failures never
    /// block the route forecast (summary just stays nil).
    private func updateRouteAirQuality() async {
        routeAirQuality = nil
        guard let startCoordinate = routePoints.first ?? weatherDataForRoute.first?.coordinate,
              let finishETA = weatherDataForRoute.last?.eta else { return }

        if let airNowSummary = await airNowRouteAirQuality(coordinate: startCoordinate, finishETA: finishETA) {
            routeAirQuality = airNowSummary
            return
        }
        routeAirQuality = await openWeatherRouteAirQuality(coordinate: startCoordinate, finishETA: finishETA)
    }

    /// Worst official AirNow AQI over the ride window, or nil when AirNow
    /// has no coverage (non-US, outage, or ride beyond its daily forecast).
    private func airNowRouteAirQuality(coordinate: CLLocationCoordinate2D, finishETA: Date) async -> RouteAirQualitySummary? {
        do {
            async let observationsFetch = weatherRepo.fetchAirNowObservations(
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
            async let forecastFetch = weatherRepo.fetchAirNowForecast(
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
            let (observations, forecasts) = try await (observationsFetch, forecastFetch)

            guard let selected = AirNowRouteAQISelector.select(
                observations: observations,
                forecasts: forecasts,
                windowStart: rideDate,
                windowEnd: finishETA
            ) else { return nil }

            return RouteAirQualitySummary(
                aqi: selected.aqi,
                category: EPAAirQualityCalculator.Category(aqi: selected.aqi),
                dominantPollutant: selected.dominantPollutant,
                windowStart: rideDate,
                windowEnd: finishETA,
                source: .airNow
            )
        } catch {
            print("⚠️ AirNow unavailable, using OpenWeather fallback: \(error)")
            return nil
        }
    }

    /// Fallback: worst-hour EPA AQI computed from OpenWeather's modeled
    /// pollution forecast at the route start (understates smoke events).
    private func openWeatherRouteAirQuality(coordinate: CLLocationCoordinate2D, finishETA: Date) async -> RouteAirQualitySummary? {
        do {
            let forecast = try await weatherRepo.fetchAirPollutionForecast(
                lat: coordinate.latitude,
                lon: coordinate.longitude
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
                    return nil
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
            
            guard let worst = readings.max(by: { $0.aqi < $1.aqi }) else { return nil }
            
            return RouteAirQualitySummary(
                aqi: worst.aqi,
                category: worst.category,
                dominantPollutant: worst.dominantPollutant,
                windowStart: rideDate,
                windowEnd: finishETA,
                source: .openWeatherModel
            )
        } catch {
            print("⚠️ Route air quality unavailable: \(error)")
            return nil
        }
    }
```

- [ ] **Step 3: Build the app**

```sh
cd "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2"
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Re-run the harness (regression)**

```sh
cd "<scratchpad>/aqi-harness"
swiftc -o aqi-test main.swift \
  "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2/RideWeather Pro/Utilities/EPAAirQualityCalculator.swift" \
  "/Users/craigfaist/Desktop/weatherApp/rideweather-pro2/RideWeather Pro/AirNowService.swift" && ./aqi-test
```

Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add "RideWeather Pro/WeatherView/WeatherRepository.swift" "RideWeather Pro/WeatherView/WeatherViewModel.swift"
git commit -m "feat: route AQI uses official AirNow data with OpenWeather fallback

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Spec coverage self-check

- AirNow endpoints/models/quirks (whitespace, `-1`, empty array, PascalCase keys, `distance=25`) → Task 1.
- Selection rules (window dates, +3 h observation inclusion, max, cap, unknown parameter) → Task 1 selector + fixtures S1–S8.
- Key in `AirNow.plist`, WeatherService-style loading, never hardcoded in source → Task 1.
- `source` field, non-breaking default → Task 1 (S8).
- Repository passthroughs, orchestrator, verbatim-extracted OpenWeather fallback, never-blocks guarantee → Task 2.
- UI/calculator/clearing untouched → no task touches them (the `source` addition compiles UI unchanged).
- Live end-to-end check (expect ≈ 296+ Very Unhealthy instead of 64 today) → user-performed after merge, as before.
