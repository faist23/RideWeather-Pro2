# Live Weather: tap AQI stat to explain AQI

## Problem
The Live Weather hero card now shows an AQI stat (when above EPA "Good"), but the number and its color mean nothing to a user who doesn't already know the EPA AQI scale. There's no way to learn what "99" or the yellow/orange/red tint represents.

## Goal
Make the AQI stat item tappable. Tapping it presents an explanation sheet: what AQI is, the user's current reading in context, and a legend of all six EPA categories with their colors, numeric ranges, and rider guidance.

## Design

### Trigger (HeroWeatherCard)
Only the AQI `WeatherDetailItem` becomes tappable — the other three stats (Feels Like, Wind, Humidity) stay static, matching today's behavior. To signal interactivity, the AQI tile gets a small `info.circle` badge; a `.onTapGesture` sets `@State private var showingAQIExplanation = true`, and a `.sheet(isPresented:)` presents `AQIExplanationView(current:)`.

This follows the app's existing pattern exactly: `TrainingLoadView` uses `@State private var showingExplanation` + `.sheet` + a dedicated `TrainingLoadExplanationView` with a reusable row component (`MetricExplanation`).

### New view: AQIExplanationView
Lives in `RideWeather Pro/RouteAnalytics/AirQualityViews.swift` — that file's header already declares it the shared home for AQI UI used by both Live Weather and Route Forecast, so the explanation is discoverable for later reuse (not building that reuse now).

A `NavigationStack` + `ScrollView` (matching `TrainingLoadExplanationView`'s structure):
1. **Header:** title "Air Quality Index" + one-paragraph plain-language explanation of what AQI is (EPA 0–500 scale measuring pollutant levels; higher = worse for outdoor exercise).
2. **Current reading callout:** the user's actual AQI number, EPA category name, and category color, shown prominently (e.g. "99 — Moderate" tinted the category color) with that category's `riderGuidance`. Only shown when a current reading is passed in.
3. **Legend:** all six EPA categories (Good → Hazardous), each row showing a color swatch, the numeric range, the category name, and its rider guidance. A reusable `AQICategoryRow` sub-view (local to the file), analogous to `MetricExplanation`.
4. A short source note ("Based on the US EPA Air Quality Index") — no new data, purely static copy.

`AQIExplanationView` takes `let current: CurrentAirQuality?` so the callout reflects live conditions; the legend is category-driven and always complete.

### Category metadata (EPAAirQualityCalculator.Category)
Add one computed property, `rangeDescription: String`, returning the numeric band per category (`"0–50"`, `"51–100"`, `"101–150"`, `"151–200"`, `"201–300"`, `"301–500"`). This keeps the band boundaries co-located with the existing `init(aqi:)` thresholds (single source of truth), rather than hardcoding ranges in the view. Reuses the existing `.color`, `.displayName`, and `.riderGuidance` — no reimplementation of category logic.

### Iteration over categories
`Category` is already `Int`-backed and `CaseIterable` is not yet declared. Add `CaseIterable` conformance so the legend can iterate `Category.allCases` in order (good → hazardous). This is a safe, additive conformance.

## Out of scope
- No changes to AQI sourcing, `AirQualityManager`, `WeatherViewModel`, or the warning banner.
- The warning banner and hourly chips are not made tappable in this change (only the hero-card stat). Could reuse `AQIExplanationView` later.
- Watch app / complications untouched — phone-only.
- No analytics/telemetry on the tap.

## Testing
- AQI logic already covered by `scripts/aqi-harness/run.sh`; the new `rangeDescription`/`CaseIterable` additions are pure and can get a small assertion there (each category's range string is non-empty and `allCases.count == 6`, in category order).
- UI (tappability, sheet presentation, legend rendering, current-reading callout) verified manually in the simulator — no XCTest UI target exists. Verify: tapping the AQI stat opens the sheet; the callout matches the on-card number/color; all six legend rows render with correct colors and ranges; sheet dismisses.
