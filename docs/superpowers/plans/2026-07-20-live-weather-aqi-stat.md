# Live Weather AQI Stat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show AQI as a fourth stat in the Live Weather hero card's stat grid, but only when air quality is above EPA "Good" (AQI > 50).

**Architecture:** Single-file SwiftUI change in `HeroWeatherCard.swift`. No new data plumbing — `WeatherViewModel.currentAirQuality: CurrentAirQuality?` is already populated on every refresh. Add a visibility bool driven by `EPAAirQualityCalculator.Category`'s existing `Comparable` conformance, switch the stat grid's column count between 3 and 4 based on that bool, and add a fourth `WeatherDetailItem` colored by EPA category.

**Tech Stack:** Swift, SwiftUI, iOS 26+. No new dependencies.

## Global Constraints
- Never reimplement AQI category/color logic locally — use `EPAAirQualityCalculator.Category` from `RideWeather Pro/Utilities/EPAAirQualityCalculator.swift` (per CLAUDE.md Air Quality convention).
- No changes to `AirQualityManager`, `WeatherViewModel`, or sourcing/fallback logic — this is UI-only.
- Do not modify the `.pbxproj` — no new files are being created, so this doesn't apply, but noted per CLAUDE.md workflow rules.
- Watch app / complications are out of scope — phone-only change.

---

### Task 1: Add AQI as a fourth stat item to the Live Weather hero card

**Files:**
- Modify: `RideWeather Pro/LiveWeather/HeroWeatherCard.swift:16-77` (the `body` of `HeroWeatherCard`)

**Interfaces:**
- Consumes: `viewModel.currentAirQuality: CurrentAirQuality?` (already on `WeatherViewModel`, `RideWeather Pro/WeatherView/WeatherViewModel.swift:46`). `CurrentAirQuality` has `let aqi: Int`, `let category: EPAAirQualityCalculator.Category` (`RideWeather Pro/Utilities/EPAAirQualityCalculator.swift:263`). `Category` is `Comparable`, ordered `good < moderate < unhealthySensitive < unhealthy < veryUnhealthy < hazardous`, with `.color: Color` (`EPAAirQualityCalculator.swift` Category extension).
- Produces: no new public interface — this is a leaf view change. `HeroWeatherCard`'s existing `body` continues to be the only consumer-facing surface.

There is no unit-testable logic here (pure SwiftUI + an already-tested `Comparable` conformance), so this task is verified by building for the simulator and visually checking the three AQI states from the spec, not by an XCTest. There is no XCTest UI target in this project (per CLAUDE.md, the only test harness is `scripts/aqi-harness`, which covers `EPAAirQualityCalculator`/`AirNowRouteAQISelector` pure logic, not views).

- [ ] **Step 1: Add the `showsAQI` computed property and switch the grid's column count**

Open `RideWeather Pro/LiveWeather/HeroWeatherCard.swift`. In `HeroWeatherCard`, add a computed property right after the `@State private var animateTemp = false` line (line 14):

```swift
    private var showsAQI: Bool {
        viewModel.currentAirQuality.map { $0.category > .good } ?? false
    }
```

Then change the `LazyVGrid` declaration (currently line 44):

```swift
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
```

to:

```swift
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: showsAQI ? 4 : 3), spacing: 12) {
```

- [ ] **Step 2: Add the AQI `WeatherDetailItem`**

In the same `LazyVGrid`, after the existing Humidity block (currently lines 60-67):

```swift
                if weather.humidity > 0 {
                    WeatherDetailItem(
                        icon: "humidity.fill",
                        label: "Humidity",
                        value: "\(weather.humidity)%",
                        color: .blue
                    )
                }
```

add:

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

- [ ] **Step 3: Build for the simulator**

Run:
```bash
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
```
Expected: `** BUILD SUCCEEDED **`. (A `No such module 'FitFileParser'` SourceKit warning, if any appears, is a known indexer artifact per CLAUDE.md — not a real failure; only the final `BUILD SUCCEEDED`/`BUILD FAILED` line matters.)

- [ ] **Step 4: Manually verify the "Good" (hidden) state**

Launch the app in the simulator on the Live Weather tab at a location where `currentAirQuality` is Good (AQI ≤ 50) or unavailable — most US locations most days. Confirm:
- The stat grid shows exactly 3 columns: Feels Like, Wind, Humidity.
- No AQI item, no layout shift versus current production behavior.

- [ ] **Step 5: Manually verify the "above Good" states**

There's no debug override for `currentAirQuality` in this codebase, so force the two remaining states with a temporary local edit — do **not** commit it:

In `HeroWeatherCard.swift`, temporarily replace the `showsAQI` body with `true` and hardcode a `CurrentAirQuality` for testing, e.g. inside `body` before the `VStack`:
```swift
    // TEMPORARY — do not commit
    private var debugAirQuality: CurrentAirQuality {
        CurrentAirQuality(aqi: 78, category: .moderate, dominantPollutant: .ozone, source: .airNow)
    }
```
and swap the two `viewModel.currentAirQuality` reads in Steps 1–2 for `debugAirQuality` (non-optional, so drop the `if let`/`.map` accordingly). Rebuild and confirm:
- 4 columns, AQI item shows `78` in yellow (moderate), no full-width warning banner (banner floor is 151).

Change `aqi: 78, category: .moderate` to `aqi: 165, category: .unhealthy` and rebuild. Confirm:
- 4 columns, AQI item shows `165` in red, **and** the existing full-width `AirQualityWarningBanner` also appears above the hero card — the two don't visually conflict or duplicate information oddly.

Then revert `HeroWeatherCard.swift` to the Step 1/Step 2 state (remove `debugAirQuality`, restore `viewModel.currentAirQuality` reads) before committing.

- [ ] **Step 6: Rebuild after reverting the debug override**

Run the same build command as Step 3. Expected: `** BUILD SUCCEEDED **`, confirming the file is back to the real (non-debug) state and still compiles.

- [ ] **Step 7: Commit**

```bash
git add "RideWeather Pro/LiveWeather/HeroWeatherCard.swift"
git commit -m "feat: show AQI as fourth Live Weather stat when above EPA Good"
```

---

## Self-Review Notes

- **Spec coverage:** visibility rule (Step 1), layout (Step 1), new stat item incl. icon/value/color (Step 2), out-of-scope items untouched (no AirQualityManager/WeatherViewModel edits in any step), all three manual test states from the spec's Testing section (Steps 4–5). All covered.
- **Placeholder scan:** no TBD/TODO; every step has literal code or an exact command.
- **Type consistency:** `CurrentAirQuality(aqi:category:dominantPollutant:source:)` matches the struct at `EPAAirQualityCalculator.swift:263` (`aqi: Int`, `category: Category`, `dominantPollutant: Pollutant`, `source: AirQualitySource = .openWeatherModel`); `.moderate`/`.unhealthy`/`.ozone`/`.airNow` are real cases from that same file. `showsAQI`, `WeatherDetailItem(icon:label:value:color:)` match the existing struct signature at `HeroWeatherCard.swift:137-142`.
