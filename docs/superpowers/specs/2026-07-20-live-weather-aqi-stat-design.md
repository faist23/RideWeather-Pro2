# Live Weather: AQI as a fourth current-conditions stat

## Problem
The Live Weather tab's hero card shows three stats below the temperature — Feels Like, Wind, Humidity — in `HeroWeatherCard.swift`. Air quality currently has no indicator on this card until it crosses the Unhealthy threshold (AQI ≥ 151), where a full-width `AirQualityWarningBanner` appears. The Moderate range (AQI 51–150) is invisible on Live Weather even though it's already computed (`viewModel.currentAirQuality`).

## Goal
Add AQI as a fourth stat item in the hero card's stat grid, shown only when air quality is above EPA "Good" (AQI > 50), i.e. `category > .good`.

## Design

### Data
No new data plumbing. `WeatherViewModel.currentAirQuality: CurrentAirQuality?` (`EPAAirQualityCalculator.swift`) is already populated on every Live Weather refresh and already backs the warning banner and `WeatherInsightsCard`.

### Visibility rule
```swift
let showsAQI = viewModel.currentAirQuality.map { $0.category > .good } ?? false
```
`EPAAirQualityCalculator.Category` is already `Comparable` (ordered `good < moderate < unhealthySensitive < unhealthy < veryUnhealthy < hazardous`), so this reads directly as "above Good."

### Layout
`HeroWeatherCard`'s `LazyVGrid` column count changes from a hardcoded `3` to `showsAQI ? 4 : 3`, so all visible stats stay in a single row. No wrapping/empty-slot case.

### New stat item
Inserted after Humidity, before the existing heat-index banner:
```swift
if showsAQI, let airQuality = viewModel.currentAirQuality {
    WeatherDetailItem(
        icon: "aqi.medium",
        label: "AQI",
        value: "\(airQuality.aqi)",
        color: airQuality.category.color
    )
}
```
- Icon `"aqi.medium"` matches the existing convention in `AirQualityChipRow` (route forecast).
- Value is the raw EPA 0–500 number, no suffix — matches the warning banner and chip.
- Color is `airQuality.category.color` (EPA hue), not a fixed color like the other three items — the stat escalates visually with severity, consistent with the warning banner.

### Out of scope
- No changes to `AirQualityManager`, `WeatherViewModel`, sourcing/fallback logic, or the existing warning banner.
- No tap/detail interaction on the new stat — matches the other three items, which are also static.
- Watch app / complications are untouched — this is Live Weather (phone) only.

## Testing
Manual verification in simulator across three AQI states (requires either live AirNow data for a smoky/moderate location, or a temporary local override while testing):
1. Good (≤50): grid shows 3 columns, no AQI item, unchanged from today.
2. Moderate/Unhealthy-for-Sensitive/Unhealthy (51–200): grid shows 4 columns, AQI item present with matching category color, no full-width banner below Unhealthy (151).
3. Very Unhealthy/Hazardous (≥151): grid shows 4 columns, AQI item present, and the existing full-width warning banner also shows above the card — no conflict between the two.

No new unit-testable logic (pure UI + an existing `Comparable` conformance), so no additions to `scripts/aqi-harness`.
