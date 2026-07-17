#!/bin/sh
# Regression harness for the route air-quality logic (no iOS test target).
# Compiles the pure calculator + AirNow selector with the fixtures in
# main.swift and runs them; prints ALL PASS / exits 0 on success.
set -e
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../.. && pwd)"
swiftc -o /tmp/aqi-harness-test main.swift \
  "$REPO_ROOT/RideWeather Pro/Utilities/EPAAirQualityCalculator.swift" \
  "$REPO_ROOT/RideWeather Pro/AirNowService.swift"
/tmp/aqi-harness-test
