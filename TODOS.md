# TODOS

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
