# AQI Explanation Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping the Live Weather AQI stat opens a sheet explaining what AQI is, showing the current reading in context, and a legend of all six EPA categories with colors, ranges, and rider guidance.

**Architecture:** Two units. First, additive metadata on the existing `EPAAirQualityCalculator.Category` (`CaseIterable` + a `rangeDescription` string) so a legend can iterate categories and show numeric bands without duplicating threshold logic — testable via the standalone AQI harness. Second, a new `AQIExplanationView` sheet (+ a private `AQICategoryRow`) in the shared `AirQualityViews.swift`, presented from a tap on the AQI stat in `HeroWeatherCard`. Reuses the category's existing `.color`/`.displayName`/`.riderGuidance` — no reimplementation.

**Tech Stack:** Swift, SwiftUI, iOS 26+. Standalone `swiftc` harness for the pure-logic additions. No new dependencies.

## Global Constraints
- Never reimplement AQI category/color/guidance logic — reuse `EPAAirQualityCalculator.Category`'s existing `.color`, `.displayName`, `.riderGuidance` (`RideWeather Pro/Utilities/EPAAirQualityCalculator.swift`). The new `rangeDescription` must reflect the SAME thresholds as `Category.init(aqi:)` (single source of truth): good ..<51, moderate ..<101, unhealthySensitive ..<151, unhealthy ..<201, veryUnhealthy ..<301, hazardous default.
- Use the en-dash `–` (U+2013) in range strings, matching the existing `"Air Quality: N – Category"` convention in `AirQualityViews.swift`.
- No changes to `AirQualityManager`, `WeatherViewModel`, AQI sourcing, or the cross-target wire format (`severityRank`).
- Watch app / complications are out of scope — phone-only.
- Run `scripts/aqi-harness/run.sh` after any change to `EPAAirQualityCalculator.swift` (project convention; there is no iOS test target).
- Do not modify `.pbxproj` — no new files require it (synced folder groups); `AirQualityViews.swift` is an existing tracked file.

---

### Task 1: Category legend metadata + harness coverage

**Files:**
- Modify: `RideWeather Pro/Utilities/EPAAirQualityCalculator.swift:39-104` (the `Category` enum)
- Test: `scripts/aqi-harness/main.swift` (append assertions before the final `if failures > 0` block)

**Interfaces:**
- Consumes: nothing new.
- Produces: `EPAAirQualityCalculator.Category` conforms to `CaseIterable` (so `Category.allCases` yields `[.good, .moderate, .unhealthySensitive, .unhealthy, .veryUnhealthy, .hazardous]` in that order — guaranteed by the sequential `Int` raw values), and gains `var rangeDescription: String` returning the numeric band (`"0–50"`, `"51–100"`, `"101–150"`, `"151–200"`, `"201–300"`, `"301–500"`). Task 2 consumes both.

- [ ] **Step 1: Add the failing harness assertions (RED)**

In `scripts/aqi-harness/main.swift`, find the final two lines:

```swift
if failures > 0 { print("\(failures) FAILURES"); exit(1) }
print("ALL PASS")
```

Insert this block immediately **before** them:

```swift
// Category legend metadata (drives the AQI explanation sheet).
let allCategories = EPAAirQualityCalculator.Category.allCases
if allCategories == [.good, .moderate, .unhealthySensitive, .unhealthy, .veryUnhealthy, .hazardous] {
    print("pass C1 category order (\(allCategories.count) cases)")
} else {
    print("FAIL C1 category order: \(allCategories)"); failures += 1
}

let expectedRanges: [(EPAAirQualityCalculator.Category, String)] = [
    (.good, "0–50"),
    (.moderate, "51–100"),
    (.unhealthySensitive, "101–150"),
    (.unhealthy, "151–200"),
    (.veryUnhealthy, "201–300"),
    (.hazardous, "301–500"),
]
var rangeFailures = 0
for (cat, expected) in expectedRanges where cat.rangeDescription != expected {
    print("FAIL C2 range \(cat): \(cat.rangeDescription) vs \(expected)")
    rangeFailures += 1
}
if rangeFailures == 0 { print("pass C2 category ranges") } else { failures += rangeFailures }
```

- [ ] **Step 2: Run the harness to verify it fails to compile (RED)**

Run: `scripts/aqi-harness/run.sh`
Expected: a **compile error**, because `Category` does not yet conform to `CaseIterable` (`allCases` undefined) and `rangeDescription` does not exist. This is the expected RED state — a compile failure here proves the assertions actually exercise the new API.

- [ ] **Step 3: Add `CaseIterable` conformance and `rangeDescription` (GREEN)**

In `RideWeather Pro/Utilities/EPAAirQualityCalculator.swift`, change the enum declaration line:

```swift
    enum Category: Int, Comparable {
```

to:

```swift
    enum Category: Int, Comparable, CaseIterable {
```

Then, inside the enum, immediately after the closing brace of the `riderGuidance` computed property (right before the enum's own closing `}` at line 104), add:

```swift

        /// Numeric AQI band for this category, mirroring `init(aqi:)`'s
        /// thresholds. Used by the explanation-sheet legend so the ranges
        /// can never drift from the category boundaries.
        var rangeDescription: String {
            switch self {
            case .good: return "0–50"
            case .moderate: return "51–100"
            case .unhealthySensitive: return "101–150"
            case .unhealthy: return "151–200"
            case .veryUnhealthy: return "201–300"
            case .hazardous: return "301–500"
            }
        }
```

- [ ] **Step 4: Run the harness to verify it passes (GREEN)**

Run: `scripts/aqi-harness/run.sh`
Expected: output includes `pass C1 category order (6 cases)` and `pass C2 category ranges`, ending in `ALL PASS` (exit 0). The pre-existing tests must all still pass.

- [ ] **Step 5: Commit**

```bash
git add "RideWeather Pro/Utilities/EPAAirQualityCalculator.swift" scripts/aqi-harness/main.swift
git commit -m "feat: EPA AQI Category gains CaseIterable + rangeDescription for legend"
```

---

### Task 2: AQIExplanationView sheet + HeroWeatherCard tap trigger

**Files:**
- Modify: `RideWeather Pro/RouteAnalytics/AirQualityViews.swift` (append the new view + row at end of file)
- Modify: `RideWeather Pro/LiveWeather/HeroWeatherCard.swift` (add tap + sheet to the AQI stat)

**Interfaces:**
- Consumes from Task 1: `EPAAirQualityCalculator.Category.allCases` and `Category.rangeDescription`. Also the existing `CurrentAirQuality` struct (`RideWeather Pro/Utilities/EPAAirQualityCalculator.swift:263` — `let aqi: Int`, `let category: EPAAirQualityCalculator.Category`) and `Category.color`/`.displayName`/`.riderGuidance`.
- Produces: `AQIExplanationView(current: CurrentAirQuality?)` — a `View` presentable as a sheet. No other consumer.

This is a UI change with no XCTest UI target in the project, so it is verified by building and manually driving the sheet in the simulator (Steps 4–6), not by an automated test.

- [ ] **Step 1: Add `AQIExplanationView` and `AQICategoryRow` to AirQualityViews.swift**

At the **end** of `RideWeather Pro/RouteAnalytics/AirQualityViews.swift` (after the closing `}` of `AirQualityChipRow`, line 62), append:

```swift

/// Explains the EPA Air Quality Index: what it measures, the rider's current
/// reading in context, and the full six-category legend (color, numeric range,
/// riding guidance). Presented as a sheet from the Live Weather AQI stat.
struct AQIExplanationView: View {
    /// The user's current reading, shown as a highlighted callout. Nil hides
    /// the callout — the legend below is always complete.
    let current: CurrentAirQuality?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Air Quality Index")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("The AQI is the US EPA's 0–500 scale for how polluted the air is. Higher numbers mean more pollution and more risk during outdoor exercise. The color shows the category at a glance.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let current {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RIGHT NOW")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                Text("\(current.aqi)")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundColor(current.category.color)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(current.category.displayName)
                                        .font(.headline)
                                        .foregroundColor(current.category.color)
                                    Text(current.category.riderGuidance)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(current.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Categories")
                            .font(.headline)

                        ForEach(EPAAirQualityCalculator.Category.allCases, id: \.self) { category in
                            AQICategoryRow(category: category)
                        }
                    }

                    Text("Based on the US EPA Air Quality Index. Readings come from official AirNow monitoring stations when available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Air Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One row of the AQI legend: color swatch, category name, numeric range,
/// and riding guidance. File-private helper for `AQIExplanationView`.
private struct AQICategoryRow: View {
    let category: EPAAirQualityCalculator.Category

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(category.color)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(category.rangeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(category.riderGuidance)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
```

- [ ] **Step 2: Add the sheet state to HeroWeatherCard**

In `RideWeather Pro/LiveWeather/HeroWeatherCard.swift`, find:

```swift
    @State private var animateTemp = false

    private var showsAQI: Bool {
```

and insert a new state line so it reads:

```swift
    @State private var animateTemp = false
    @State private var showingAQIExplanation = false

    private var showsAQI: Bool {
```

- [ ] **Step 3: Make the AQI stat tappable and present the sheet**

In the same file, find the AQI stat block inside the grid:

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

Replace it with (adds an info badge to signal interactivity, makes the whole tile tappable):

```swift
                if showsAQI, let airQuality = viewModel.currentAirQuality {
                    WeatherDetailItem(
                        icon: "aqi.medium",
                        label: "AQI",
                        value: "\(airQuality.aqi)",
                        color: airQuality.category.color
                    )
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showingAQIExplanation = true }
                }
```

Then find the card's modifier chain that begins:

```swift
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
```

and insert the sheet immediately **before** `.padding(16)`:

```swift
        .sheet(isPresented: $showingAQIExplanation) {
            AQIExplanationView(current: viewModel.currentAirQuality)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
```

- [ ] **Step 4: Build for the simulator**

Run:
```bash
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug
```
Expected: `** BUILD SUCCEEDED **`. (SourceKit `Cannot find type …` diagnostics in the editor are a known indexer artifact per CLAUDE.md; only the final build line is authoritative.)

- [ ] **Step 5: Manually verify the tap → sheet flow in the simulator**

The AQI stat only shows when AQI > 50, and simulator air is often Good, so force a visible above-Good reading with a temporary local edit (do **not** commit it). In `HeroWeatherCard.swift`, temporarily replace the `showsAQI` body with `true` and add a debug value, then point the stat + sheet at it:

```swift
    // TEMPORARY — do not commit
    private var debugAirQuality: CurrentAirQuality {
        CurrentAirQuality(aqi: 99, category: .moderate, dominantPollutant: .ozone, source: .airNow)
    }
    private var showsAQI: Bool { true }
```
and in the AQI stat block and the `.sheet`, use `debugAirQuality` in place of `viewModel.currentAirQuality` (the stat's `if showsAQI, let airQuality = viewModel.currentAirQuality` becomes `if showsAQI { let airQuality = debugAirQuality; … }`, and the sheet becomes `AQIExplanationView(current: debugAirQuality)`).

Rebuild, install, launch on the iPhone 17 Pro simulator (boot it, `xcrun simctl install`, `xcrun simctl launch`), grant location, and screenshot (`xcrun simctl io <udid> screenshot`). Then, using `cliclick` against the Simulator window (or the Simulator UI), tap the AQI tile and screenshot the presented sheet. Confirm:
- The AQI tile shows a faint `info.circle` badge and "99".
- Tapping it presents the sheet.
- The "RIGHT NOW" callout shows "99" and "Moderate" in the moderate (yellow) color, with the moderate rider guidance.
- The legend lists all six categories in order (Good → Hazardous), each with a colored swatch, the correct range (`0–50` … `301–500`), name, and guidance.
- "Done" dismisses the sheet.

- [ ] **Step 6: Revert the debug override and rebuild clean**

Revert the temporary edit so `HeroWeatherCard.swift` contains only the Step 2–3 changes:
```bash
git diff "RideWeather Pro/LiveWeather/HeroWeatherCard.swift"
```
Confirm the diff shows only the real changes (state var, `.overlay`/`.contentShape`/`.onTapGesture`, `.sheet`) and no `debugAirQuality`/`showsAQI { true }`. Then rebuild:
```bash
xcodebuild build -scheme "RideWeather Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add "RideWeather Pro/RouteAnalytics/AirQualityViews.swift" "RideWeather Pro/LiveWeather/HeroWeatherCard.swift"
git commit -m "feat: tap Live Weather AQI stat to open EPA AQI explanation sheet"
```

---

## Self-Review Notes

- **Spec coverage:** trigger on AQI stat only + info badge (Task 2 Step 3); `AQIExplanationView` with intro, current-reading callout, six-category legend, source note (Task 2 Step 1); `rangeDescription` co-located with thresholds + `CaseIterable` for ordered iteration (Task 1); harness assertion for the pure additions (Task 1 Steps 1–4); out-of-scope items untouched (no AirQualityManager/WeatherViewModel/wire-format edits in any step). All covered.
- **Placeholder scan:** no TBD/TODO; every step carries literal code or an exact command.
- **Type consistency:** `CurrentAirQuality(aqi:category:dominantPollutant:source:)` matches the struct at `EPAAirQualityCalculator.swift:263`; `Category.allCases`/`.rangeDescription`/`.color`/`.displayName`/`.riderGuidance` all exist after Task 1 (`allCases`/`rangeDescription`) or already (`color`/`displayName`/`riderGuidance`). `AQIExplanationView(current:)` signature is identical in its definition (Task 2 Step 1) and both call sites (Task 2 Step 3, and the debug variant in Step 5).
