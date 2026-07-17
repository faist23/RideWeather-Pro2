# Route Forecast Air Quality Warning — Design

**Date:** 2026-07-17
**Status:** Approved (pending user review of this written spec)

## Problem

The Route Forecast has zero air-quality awareness. During a hazardous air event (e.g. US EPA AQI 434, where every public-health authority advises against outdoor exercise), the route forecast happily presents wind, temperature, and pacing data with no indication that riding at all is inadvisable.

The Live Weather screen already shows air quality, but only OpenWeather's coarse 1–5 index ("Very Poor"), only for current conditions at the user's location, and nothing about it reaches the route planning flow.

## Decisions (made with user)

1. **Scale:** Display the **US EPA AQI (0–500)** with EPA category names ("434 – Hazardous"), computed from OpenWeather's pollutant concentrations. Matches official warnings and news reports.
2. **Timing:** Evaluate AQI **at the scheduled ride time**, using OpenWeather's air-pollution *forecast* endpoint (hourly, ~4-day horizon), across the ride window (departure → last route point's ETA). Worst hour wins.
3. **UX:** **Banner + summary chip.** A warning banner appears in the route analysis when AQI ≥ 151 (Unhealthy or worse); an AQI chip appears among the route summary metrics at *all* levels so air quality is always visible.
4. **Provider:** AQI always comes from OpenWeather regardless of the selected weather provider — WeatherKit offers no air-quality data. This matches the existing Live Weather behavior.
5. **Granularity:** One pollution fetch at the **route start coordinate**. Air quality is regional; per-point fetches (8× calls) add cost and plumbing for no signal on typical routes. Per-point AQI is an explicit non-goal for now.

## Architecture

### 1. `EPAAirQualityCalculator` (new, `RideWeather Pro/Utilities/EPAAirQualityCalculator.swift`)

Shared, pure utility following the `HeatIndexCalculator` convention (enum/struct with static methods, no state, `///` docs).

- **Input:** `PollutionComponents` (OpenWeather, all µg/m³).
- **Output:** `EPAAirQuality` value: `aqi: Int` (0–500, capped at 500), `dominantPollutant`, `category`.
- **Method:** For each pollutant with an EPA breakpoint table — PM2.5, PM10, O₃, NO₂, SO₂, CO — compute the sub-index by linear interpolation within the EPA breakpoint tables; the reported AQI is the **max** sub-index.
- **Unit conversion (bug-prone, be explicit):** OpenWeather reports gases in µg/m³, but EPA breakpoints use ppm (O₃, CO) and ppb (NO₂, SO₂). Convert at 25 °C / 1 atm: `ppb = µg/m³ × 24.45 / MW` with MW O₃ = 48.00, NO₂ = 46.01, SO₂ = 64.07, CO = 28.01. PM2.5 and PM10 stay in µg/m³.
- **Breakpoints:** Use the current EPA tables, including the **2024 revised PM2.5 breakpoints** (Good ≤ 9.0 µg/m³, …, Hazardous ≥ 225.5 µg/m³).
- **Approximation note (documented in code):** EPA breakpoints are defined over averaging periods (24 h PM, 8 h O₃/CO, 1 h NO₂/SO₂); we apply instantaneous hourly concentrations against them, as most consumer apps do. Good enough for a go/no-go riding signal; not a regulatory NowCast implementation.
- **`Category` enum:** `good` (0–50, green), `moderate` (51–100, yellow), `unhealthySensitive` (101–150, orange), `unhealthy` (151–200, red), `veryUnhealthy` (201–300, purple), `hazardous` (301+, maroon). Each carries `displayName`, `color`, and `riderGuidance` text; `hazardous` guidance is "Outdoor exercise not advised." `unhealthy`/`veryUnhealthy` advise shortening or rescheduling the ride; lower categories are informational.

### 2. Pollution forecast fetch

- **`WeatherService.fetchAirPollutionForecast(lat:lon:) async throws -> AirPollutionResponse`** (new): GET `/air_pollution/forecast`. The existing `AirPollutionResponse` Codable models already match the forecast payload (`list[]` of `dt` + `main.aqi` + `components`) — no new models. Cache like the existing `fetchAirPollution` (same cache mechanism, key `air_pollution_forecast_<lat>_<lon>`).
- **`WeatherRepository.fetchAirPollutionForecast(lat:lon:)`** passthrough, mirroring the existing `fetchAirPollution` passthrough.

### 3. `WeatherViewModel` integration

- New published property: `routeAirQuality: RouteAirQualitySummary?` where the summary holds `aqi: Int`, `category`, `dominantPollutant`, and the evaluated window.
- In `calculateAndFetchWeather()`, after route weather points resolve successfully: fetch the pollution forecast at the **first route point's coordinate**, select hourly entries whose `dt` falls in `[departure, lastPointETA]` (inclusive, padded to the containing hours; if the window is inside a single hour, the nearest entry). Compute EPA AQI per selected entry via the calculator; keep the worst hour as the summary.
- **Coverage edge cases:**
  - Ride starts now / in the past hour: the forecast list's first entries cover "now" — no separate current-pollution call needed.
  - Ride window entirely beyond the forecast horizon (~4 days): **no summary (nil)** — do not substitute current pollution for a far-future ride. (Refined from the discussed "fall back to current" — current data for a 5-day-out ride would mislead; in practice the route forecast's hourly weather horizon already keeps rides within the pollution forecast's range.)
  - Fetch failure: summary is nil; **never** blocks or fails the route forecast. Log and move on.
- Clear `routeAirQuality` wherever `weatherDataForRoute` is cleared/reset (route import, reset, re-fetch start).

### 4. UI

Both elements live in the route analysis flow (`OptimizedUnifiedRouteAnalyticsDashboard` and the route summary metrics area):

- **Warning banner** (AQI ≥ 151 only): shown at the top of the analysis dashboard. Visual language follows the existing `WeatherAlert` banner styling: category color background, warning icon, title "Air Quality: 434 – Hazardous", subtitle = category `riderGuidance`. Uses the calculator's category color (maroon for hazardous, matching EPA convention) with legible text color, same approach as `WeatherAlert.textColor`.
- **Summary chip** (always when summary exists): AQI number + category name, tinted with the category color, placed alongside the other route summary metrics. Nil summary → chip absent (no "Unknown" placeholder).

## Error handling

- Pollution fetch failures are silent for the user (nil summary, no chip/banner) but logged. Route forecast generation is never blocked by air-quality problems.
- Calculator must handle zero/negative/absurd concentrations gracefully: clamp negatives to 0, cap AQI at 500 ("500+" not required; cap is fine).

## Testing / verification

- The calculator is pure Foundation logic — verify against known EPA breakpoint fixtures before wiring UI:
  - PM2.5 = 9.0 µg/m³ → AQI 50 (Good/Moderate boundary, 2024 table).
  - PM2.5 = 35.4 µg/m³ → AQI 100.
  - PM2.5 ≈ 300 µg/m³ → AQI in the low-400s, Hazardous (mirrors the user's real 434 event).
  - Gas conversion sanity: O₃ 100 ppb ≈ 196 µg/m³ round-trips through the MW conversion.
  - Max-of-subindices: high PM2.5 + low everything else → PM2.5 dominates.
- There is no iOS unit-test target; the plan should verify the calculator via a standalone `swiftc` harness in the scratchpad (the file must not import UIKit-only symbols at compute level; `Color` lives on the Category extension so keep the core computation Foundation-only or split accordingly).
- End-to-end: build for iPhone simulator, load a route, confirm chip renders; banner path can be forced by temporarily injecting a hazardous fixture during verification.

## Non-goals (follow-ups, not this change)

- Per-point AQI along the route.
- Watch / complications payloads carrying AQI.
- Switching Live Weather's 1–5 display to the EPA number (the new calculator makes this easy later).
- Departure-time optimizer weighing AQI.
