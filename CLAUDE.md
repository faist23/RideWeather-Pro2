# CLAUDE.md — RideWeather Pro

## Project Overview
RideWeather Pro is a multi-platform Apple ecosystem application (iOS, watchOS, and widgets/complications) built to provide cyclists with route forecasting, pacing insights, and wellness tracking. It integrates with major fitness platforms (Strava, Garmin, Wahoo) and uses Supabase for backend services.

## Core Technologies
- **Target Platforms:** iOS 26+ and watchOS 26+
- **UI Framework:** SwiftUI (Primary for iOS and watchOS)
- **Language:** Swift (Modern Swift features, Concurrency)
- **Architecture:** MVVM (Model-View-ViewModel) paired with centralized Service/Manager singletons.
- **Backend:** Supabase (PostgreSQL, Edge Functions via Deno/TypeScript).
- **Key Frameworks:** HealthKit, CoreLocation, WeatherKit / OpenWeather.

## Build & Verify
- **Scheme:** `RideWeather Pro` (other schemes: `RideWeatherWatch Watch App`, `RideWeatherComplicationsExtension`).
- **Build for simulator:**
  ```sh
  xcodebuild build -scheme "RideWeather Pro" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug
  ```
- A `No such module 'FitFileParser'` (or similar SPM module) error from SourceKit is an indexer artifact only — the SPM build resolves these packages and compiles fine.
- Ride analysis (CdA, wind impact, weather correlation) is recomputed fresh on every import; results are not cached.
- **Watch targets:** xcodebuild's simulator destination matching is intermittently broken on this machine (`Unable to find a destination` even for devices it just listed, with `DVTBuildVersion` warnings). Build watch targets directly instead:
  ```sh
  xcodebuild -project "RideWeather Pro.xcodeproj" -target "RideWeatherWatch Watch App" \
    -sdk watchsimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
  ```
  (same for `RideWeatherComplicationsExtension`). Target-style builds write artifacts to `./build/` (git-ignored); delete it afterward.

## Architectural Guidelines

### Swift & SwiftUI
1. **Modern State Management:** Given the iOS 26+/watchOS 26+ targets, rely heavily on the modern `@Observable` macro for state management instead of older `ObservableObject`/`@Published` paradigms. Use `@Environment` and `@Bindable` appropriately.
2. **Modern Concurrency:** Use `async/await`, `Task`, and `actor` for all asynchronous operations and data race safety. Avoid completion handlers.
3. **MVVM Pattern:** Keep Views as declarative as possible. Place business logic, state mutation, and API calls inside corresponding ViewModels.
4. **Services & Managers:** Use centralized managers (e.g., `LocationManager`, `WellnessManager`, `GarminService`) for cross-cutting concerns, hardware APIs, and third-party API communication. Inject these into ViewModels or Views via Environment where appropriate.
5. **Platform Preprocessor Macros:** When writing code shared between iOS and watchOS, use `#if os(iOS)` and `#if os(watchOS)` appropriately to prevent compilation errors.

### Supabase Edge Functions
1. **Runtime:** Deno / TypeScript.
2. **Style:** Use modern TypeScript, explicit typing for request/response payloads, and standard Deno HTTP modules.
3. **Secrets:** Never hardcode API keys. Rely on Supabase Vault or environment variables (`Deno.env.get`).
4. **AI insights:** The app never calls api.anthropic.com directly — `AIInsightsManager` goes through the `ai-insight` edge function (model/schema pinned server-side; key in the `ANTHROPIC_API_KEY` secret).
5. **Deploy:** CLI is authenticated and linked — `supabase functions deploy <name>`; secrets via `supabase secrets set KEY=value` (takes effect without redeploy).

## Domain Conventions

### Large-Blob Persistence
Never store large Codable arrays in UserDefaults — iOS rejects defaults domains ≥ 4 MB (savedRideAnalyses once hit 4.9 MB). Use the file-backed stores: `JSONFileStorage` (generic, handles one-time UserDefaults migration), `TrainingLoadStorage`, `WellnessStorage`. Hold them as `static let` so migration runs once per launch.

### Heat Index
- Always use the shared NWS calculator (`RideWeather Pro/Utilities/HeatIndexCalculator.swift`); the watch target keeps a °F-only copy (`RideWeatherWatch Watch App/HeatIndexCalculator.swift`) that must stay in sync. Never reimplement the formula locally — a private "simple" copy in ride analysis once understated a 105 °F heat index as 91 °F.
- UI convention (app-wide): show the heat index **in place of** feels-like when it applies (≥ 80 °F NWS floor), tinted by the NWS category color (`Category.color`: yellow/orange/red/purple). Below the floor, show feels-like. Complications, watch app, ride analysis, and route forecast all follow this rule.
- Cross-target payloads (watch summary, complications) carry `heatIndex` in display units plus `heatIndexSeverity` (stable rank 1–4).

### Air Quality
- **Sourcing:** official EPA **AirNow** station data first, OpenWeather pollution model as fallback — model products understate smoke events by an order of magnitude (a real AQI-434 episode read as 64 from OpenWeather's model). Never "fix" anything by trusting model AQI more. All sourcing logic lives in `AirQualityManager` (`RideWeather Pro/AirQualityManager.swift`); don't re-add it to view models.
- **EPA math:** `EPAAirQualityCalculator` (US EPA 0–500 scale, 2024 PM2.5 breakpoints, µg/m³→ppm/ppb gas conversion). The watch keeps a copy of the category bands/colors (`RideWeatherWatch Watch App/WatchAirQuality.swift`) that must stay in sync — same convention as the watch `HeatIndexCalculator`.
- **Wire format:** cross-target payloads (`SharedWeatherSummary`, three must-match copies: watch, complications, phone) carry `aqi` plus `aqiSeverity` as a **stable rank 1–6** (`Category.severityRank` = rawValue + 1 — never send the rawValue, `good` is 0 locally but 1 on the wire).
- **UI convention:** show the real EPA number at every level; warning treatment (banner/chips) only at Unhealthy+ via the shared `EPAAirQualityCalculator.warningBannerFloor` (151) — never a literal threshold. Category colors are the official EPA hues; `veryUnhealthy`/`hazardous` use dark EPA purple/maroon (iOS system `.purple` is too light for white text).
- **Tests:** the AQ regression suite is `scripts/aqi-harness/run.sh` (standalone swiftc — there is no iOS test target). Run it whenever touching `EPAAirQualityCalculator` or `AirNowRouteAQISelector`.
- **Keys:** AirNow API key in `AirNow.plist` (`AirNowApiKey`), one copy each in the phone and watch folders; the plists are gitignored-but-tracked like the other config plists.

### Humidity Units
Two conventions coexist — convert once at the boundary and never divide twice:
- **0–1 fraction:** WeatherKit (`humidity`), `HistoricalWeatherPoint.humidity`, `PowerRouteSegment.averageHumidity`, `PowerPhysicsEngine.calculateAirDensity(relativeHumidity:)`.
- **Percent (0–100):** OpenWeather API, `DisplayWeatherModel.humidity` (Int), `HeatIndexCalculator.reading(humidity:)` / `heatIndexF(relativeHumidity:)`.

### Cross-Device Settings Sync
- App groups do **not** sync between iPhone and Watch; settings travel in the WCSession application context (`PhoneSessionManager`) and are re-stored in the watch-side app group.
- Wire values must be stable tokens (e.g. `WeatherProvider.syncToken`: `"apple"`/`"openweather"`), never derived from display `rawValue`s — `"Apple Weather".lowercased()` once silently switched the watch to the wrong provider.

### Ride Analysis Weather
- Weather sampling prefers the head unit's recorded ambient temperature (FIT `temperature` field, Strava `temp` stream, Garmin `airTemperatureCelcius` sample field — misspelled upstream) over WeatherKit's gridded historical values, which can lag actual surface heating by several degrees; WeatherKit remains the fallback and the source for wind/humidity/pressure.

### Gradient Units
- `TerrainSegment.gradient` (ride analysis and pacing comparison) is a **percent** (e.g. `13.4` for a 13.4% grade), never a 0–1 fraction. Display it without multiplying by 100, and write comparison thresholds in percent (`> 3`, not `> 0.03`) — a double-scaled display once showed a 13.4% grade as "1336.2%", and fraction-style thresholds silently sent every segment through the climb-physics branch.
- Route pacing (`PacingEngine`) grades are 0–1 fractions and are multiplied by 100 at display; don't move values between the two pipelines without converting.

## Coding Standards
1. **Naming:** Use standard Swift `camelCase` for variables/functions and `PascalCase` for types/classes/structs. Use descriptive names over abbreviations.
2. **Error Handling:** Avoid force-unwrapping (`!`). Handle optionality gracefully using `if let` or `guard let`. Propagate errors using `throws` or `Result` types where UI feedback is necessary.
3. **File Structure:**
   - Ensure new SwiftUI views are placed in their respective feature folders (e.g., `LiveWeather/`, `RoutePacing/`).
   - Keep files focused. If a file exceeds 300-400 lines, consider breaking out sub-views or moving logic into a ViewModel/Helper.
4. **Documentation:** Add brief documentation comments (`///`) to public methods, complex algorithms (like pacing and power physics engines), and model properties.

## Workflow Rules
1. **Strict Platform Matching:** If the user states they like how a feature works on one platform (e.g., iOS) and requests that another platform (e.g., watchOS) match it, **do not alter the platform the user said they liked.** Only modify the target platform to match the requested behavior.
2. **Do not modify `.pbxproj` directly.** The project uses synced folder groups (`PBXFileSystemSynchronizedRootGroup`), so new files created under `RideWeather Pro/` (or the watch/complications folders) are added to their target automatically — no manual Xcode step needed.
3. **Dependencies:** Do not introduce new Swift Package Manager dependencies or CocoaPods without explicit permission.
4. **Testing:** When modifying logic in the `RouteAnalytics`, `RideAnalysis`, or `RoutePacing` engines, ensure edge cases are accounted for, as these directly affect rider safety and performance calculations.
