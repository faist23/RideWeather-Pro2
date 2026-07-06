# TODOS

## Heat Index Accuracy & Coverage (July 2026)

### ~~Complications: heat index replaces feels-like~~ DONE
Smart Ride Stats and Ride Weather complications show "HI" (NWS-severity-colored where families render color) in place of "FL"/"Feels" when the heat index applies. Widget-side `SharedWeatherSummary`/`ForecastHour` now decode the `heatIndex`/`heatIndexSeverity` fields the watch app already wrote.

---

### ~~Ride analysis: broken heat index math~~ DONE
Deleted the private `calculateSimpleHeatIndex` (humidity double-divided to ~0, never escalated to Rothfusz — reported 91°F when true HI was 105°F). Analysis now uses the shared NWS `HeatIndexCalculator`; air density also gets the correct 0–1 humidity fraction.

---

### ~~Ride analysis: inaccurate temperatures~~ DONE
Weather samples prefer the head unit's recorded temperature (FIT `temperature` field, Strava `temp` stream; median within ±5 min, implausible values rejected) over WeatherKit's gridded historical temps, which ran ~6°F cool on a hot morning. WeatherKit remains fallback + source for wind/humidity/pressure.

---

### ~~Ride analysis UI: show heat index~~ DONE
"Conditions During Ride" card gains a Peak Heat Index stat and per-point "HI" readings in the Weather Timeline, colored by NWS band, plus category riding advice.

---

### ~~Pacing plan: heat degradation + readiness bug~~ DONE
PacingEngine degrades segment power targets 0.5% per °F of heat index above 75°F (cap 25%), ramping half→full weight over the first hour of hot exposure; adds a heat warning with NWS category. Also fixed `readinessAdjustedPower` being computed but never applied.

---

### ~~Watch app: wrong weather provider~~ DONE
Phone synced `"apple weather"` (lowercased display rawValue); watch matched on `"apple"` and silently fetched OpenWeather. Producers now send `WeatherProvider.syncToken`; watch readers contains-match so the stale stored value resolves immediately.

---

### ~~Route forecast: heat index on graph, map pins, detail sheet~~ DONE
Scrub graph plots one thermal series (HI where it applies, feels-like otherwise) so the popover matches the line; heat-territory points colored by NWS band; y-axis scales to the swapped series. Map annotations and the detail sheet chip follow the same rule.

---

## Watch App — Post Location Fix

### ~~WeatherDetailView: Location Unavailable state~~ DONE
WeatherDetailView observes `WatchLocationManager.shared.locationStatus`. When `.denied` or `.restricted`, renders `ContentUnavailableView("Location Unavailable", ...)` instead of stale weather data.

---

### ~~WatchDebugView: Last location + last fetch diagnostics~~ DONE
Added LOCATION section (auth status, lat/lon, last fix time) and BACKGROUND section (last refresh time, age). Reads from App Group keys `user_latitude`, `user_longitude`, `lastLocationUpdate`, `last_background_refresh`.

---

### ~~WatchWeatherService: Wind direction + pop data mapping~~ DONE
Added `wind_deg` and `pop` to OpenWeather structs; mapped both paths (Apple WeatherKit uses `wind.direction.value` + `hourlyForecast.first?.precipitationChance`; OpenWeather uses `wind_deg` + `hourly[0].pop`). Extracted `SharedWeatherSummary.make(from:alert:hourly:nextHourSummary:)` factory. Removed hardcoded "N"/0 from WatchLocationManager, BackgroundWatchUpdater, and WatchAppGroupManager.

---

### ~~Duplicate weather fetches on launch~~ DONE
Removed `requestLocation()` from `locationManagerDidChangeAuthorization` (was firing on every init even when already authorized). Added `isFetchingWeather` in-flight guard to `updateWeather()`. Removed redundant `startUpdating()` from `onAppear` — `onChange(.active)` already fires on cold launch. Result: one fetch per foreground entry instead of 5+.
