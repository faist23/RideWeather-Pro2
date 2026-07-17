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


// C1: current-conditions reuse — empty forecasts + zero-length window at
// `now` reduces the selector to "max of current observations".
let nowC1 = makeDate(2026, 7, 17, 12)
expectSelect("C1 current conditions via selector",
    AirNowRouteAQISelector.select(
        observations: [obs("PM2.5", 236), obs("O3", 47), obs("PM10", -1)],
        forecasts: [],
        windowStart: nowC1, windowEnd: nowC1,
        now: nowC1, calendar: nyCal),
    aqi: 236, pollutant: .pm25)

// C2: CurrentAirQuality banner threshold and source default.
let liveHigh = CurrentAirQuality(aqi: 236, category: .veryUnhealthy, dominantPollutant: .pm25, source: .airNow)
assert(liveHigh.showsWarningBanner && liveHigh.source == .airNow)
let liveLow = CurrentAirQuality(aqi: 64, category: .moderate, dominantPollutant: .pm25)
assert(!liveLow.showsWarningBanner && liveLow.source == .openWeatherModel)
print("pass C2 CurrentAirQuality threshold/source")

if failures > 0 { print("\(failures) FAILURES"); exit(1) }
print("ALL PASS")
