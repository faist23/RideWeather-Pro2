# Gemini CLI Project Instructions for RideWeather Pro

## Project Overview
RideWeather Pro is a multi-platform Apple ecosystem application (iOS, watchOS, and widgets/complications) built to provide cyclists with route forecasting, pacing insights, and wellness tracking. It integrates with major fitness platforms (Strava, Garmin, Wahoo) and uses Supabase for backend services.

## Core Technologies
- **Target Platforms:** iOS 26+ and watchOS 26+
- **UI Framework:** SwiftUI (Primary for iOS and watchOS)
- **Language:** Swift (Modern Swift features, Concurrency)
- **Architecture:** MVVM (Model-View-ViewModel) paired with centralized Service/Manager singletons.
- **Backend:** Supabase (PostgreSQL, Edge Functions via Deno/TypeScript).
- **Key Frameworks:** HealthKit, CoreLocation, WeatherKit / OpenWeather.

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

## Coding Standards
1. **Naming:** Use standard Swift `camelCase` for variables/functions and `PascalCase` for types/classes/structs. Use descriptive names over abbreviations.
2. **Error Handling:** Avoid force-unwrapping (`!`). Handle optionality gracefully using `if let` or `guard let`. Propagate errors using `throws` or `Result` types where UI feedback is necessary.
3. **File Structure:** 
   - Ensure new SwiftUI views are placed in their respective feature folders (e.g., `LiveWeather/`, `RoutePacing/`).
   - Keep files focused. If a file exceeds 300-400 lines, consider breaking out sub-views or moving logic into a ViewModel/Helper.
4. **Documentation:** Add brief documentation comments (`///`) to public methods, complex algorithms (like pacing and power physics engines), and model properties.

## Workflow Rules
1. **Strict Platform Matching:** If the user states they like how a feature works on one platform (e.g., iOS) and requests that another platform (e.g., watchOS) match it, **do not alter the platform the user said they liked.** Only modify the target platform to match the requested behavior.
2. **Do not modify `.pbxproj` directly:** If new files need to be added, explicitly mention that they must be added to the Xcode project manually by the user, or rely on Xcode's automatic tracking if the project format supports it.
3. **Dependencies:** Do not introduce new Swift Package Manager dependencies or CocoaPods without explicit permission.
4. **Testing:** When modifying logic in the `RouteAnalytics`, `RideAnalysis`, or `RoutePacing` engines, ensure edge cases are accounted for, as these directly affect rider safety and performance calculations.