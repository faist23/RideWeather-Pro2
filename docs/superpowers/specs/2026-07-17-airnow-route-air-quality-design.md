# AirNow Route Air Quality (with OpenWeather Fallback) — Design

**Date:** 2026-07-17
**Status:** Approved
**Builds on:** `2026-07-17-route-forecast-air-quality-design.md` (merged at `0f0890c`)

## Problem

The route forecast's AQI comes from OpenWeather's air-pollution product, a model output that badly understates real smoke events: during an official AQI-434 hazardous episode (Columbus OH, 2026-07-17), OpenWeather reported PM2.5 ≈ 16 µg/m³ → app showed AQI 64, while station-based providers (Apple 413, AccuWeather 304, tomorrow.io 381) and the official EPA AirNow feed (PM2.5 AQI 296 at time of testing) reflected reality. Verified by direct API queries — the app's computation was correct; the input data was wrong.

## Decision (made with user)

Use **AirNow (US EPA)** as the primary source for route air quality — it is the official station-based feed the user's public warnings come from — and keep the existing OpenWeather worst-hour pipeline as the fallback (non-US locations, AirNow outages, rides beyond AirNow's forecast horizon).

## Verified API facts (queried 2026-07-17 with the app's key)

- **Current observations:** `GET https://www.airnowapi.org/aq/observation/latLong/current/?format=application/json&latitude=<lat>&longitude=<lon>&distance=25&API_KEY=<key>` → JSON array; each entry: `DateObserved` (string `"yyyy-MM-dd"`, may carry stray whitespace — trim), `HourObserved` (Int), `LocalTimeZone`, `ReportingArea`, `StateCode`, `Latitude`/`Longitude` (Double), `ParameterName` (`"O3"`, `"PM2.5"`, `"PM10"`, occasionally `"NO2"`/`"SO2"`/`"CO"`), `AQI` (Int), `Category` (`{Number, Name}`). One entry per pollutant; overall AQI is the max.
- **Forecast:** `GET https://www.airnowapi.org/aq/forecast/latLong/?format=application/json&latitude=<lat>&longitude=<lon>&distance=25&API_KEY=<key>` → JSON array of daily per-pollutant entries ~6 days out: `DateIssue`, `DateForecast` (`"yyyy-MM-dd"`, trim), `ParameterName`, `AQI` (Int, **can be -1 meaning "not forecast" — must be filtered**), `Category`, `ActionDay` (Bool), `Discussion` (long text, repeated per entry).
- Empty array = no reporting area within `distance` (e.g., outside the US) → fallback trigger.
- Categories are the same EPA bands the app already implements; deriving category from the AQI number via `EPAAirQualityCalculator.Category(aqi:)` keeps one source of truth.

## Architecture

### 1. `AirNowService` (new, `RideWeather Pro/AirNowService.swift`)

Singleton in the `WeatherService` style. Foundation-only (no SwiftUI) so it compiles in the swiftc harness.

- Key from new `RideWeather Pro/AirNow.plist`, key name `AirNowApiKey` (mirrors `OpenWeather.plist`/`OpenWeatherApiKey`). The user's key is added to this plist.
- `fetchCurrentObservations(lat:lon:) async throws -> [AirNowObservation]`
- `fetchForecast(lat:lon:) async throws -> [AirNowForecastEntry]`
- Codable models exactly matching the payloads above (custom CodingKeys for PascalCase). `distance=25` fixed.
- NSCache, 30-minute expiry, keys `airnow_current_<lat>_<lon>` / `airnow_forecast_<lat>_<lon>`.

### 2. Selection logic (pure, harness-tested)

`AirNowRouteAQISelector` (enum with static method, same file):

`select(observations:forecasts:windowStart:windowEnd:now:calendar:) -> (aqi: Int, dominantPollutant: EPAAirQualityCalculator.Pollutant)?`

- **Window dates:** the set of calendar days (device calendar) touched by `[windowStart, windowEnd]`.
- **Candidates:** forecast entries with trimmed `DateForecast` on a window date and `AQI >= 0`; plus all current observations (`AQI >= 0`) when `windowStart <= now + 3 h` (covers "riding now/soon" including windows already underway).
- **Result:** the max-AQI candidate (capped at 500). Dominant pollutant mapped from `ParameterName` (`"PM2.5"→.pm25`, `"PM10"→.pm10`, `"O3"→.ozone`, `"NO2"→.no2`, `"SO2"→.so2`, `"CO"→.co`, case-insensitive); an unknown name still counts toward the AQI and falls back to `.pm25` for the label (label is not currently rendered).
- **Empty candidates → nil** (caller falls back to OpenWeather).

### 3. Integration (`WeatherViewModel` + `WeatherRepository`)

- `WeatherRepository` gains passthroughs `fetchAirNowObservations(lat:lon:)` / `fetchAirNowForecast(lat:lon:)` delegating to `AirNowService.shared`, keeping the view model's dependency surface unchanged.
- `RouteAirQualitySummary` gains `source: AirQualitySource` (`enum AirQualitySource { case airNow, openWeatherModel }`, defined alongside the summary in `EPAAirQualityCalculator.swift`). UI is unchanged; the field enables future labeling.
- `updateRouteAirQuality()` becomes an orchestrator:
  1. Fetch AirNow observations + forecast concurrently for the route start coordinate; run the selector over the ride window.
  2. Hit → publish summary with `source: .airNow`, category via `Category(aqi:)`.
  3. Miss (empty/`nil`/thrown error) → run the existing OpenWeather worst-hour path, extracted verbatim into `openWeatherRouteAirQuality() async -> RouteAirQualitySummary?`, publishing with `source: .openWeatherModel`.
  4. Any failure anywhere still never blocks the route forecast (summary nil).

### 4. Unchanged / out of scope

- Banner, chip, thresholds, EPA calculator math, clearing sites — untouched.
- Follow-ups (not this change): surface AirNow's `Discussion`/`ActionDay` in the UI; use AirNow for the Live Weather card; source label in the chip.

## Error handling

- AirNow HTTP errors, decode failures, empty arrays, all-`-1` forecasts → silent fallback to OpenWeather path (log only). OpenWeather failure after AirNow miss → nil summary, as today.
- Defensive clamping: ignore negative AQI, cap at 500.

## Testing / verification

Extend the existing swiftc harness (compiles `EPAAirQualityCalculator.swift` + `AirNowService.swift`):
- Forecast entry on ride date wins over lower current observation; max across pollutants.
- `AQI = -1` entries excluded (an all-`-1` day yields nil → fallback).
- Current observations included only when `windowStart <= now + 3 h`; a ride 2 days out uses that date's forecast only.
- Ride date beyond forecast horizon with no observations → nil.
- Date matching tolerates whitespace in `DateForecast` (`"2026-07-18 "`).
- `RouteAirQualitySummary` construction updated for the new `source` field.
- App build via xcodebuild; live end-to-end check by the user (today's event: expect ≈ 296+ Very Unhealthy/Hazardous from AirNow instead of 64).
