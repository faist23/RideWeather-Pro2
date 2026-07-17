//
//  WatchAirQuality.swift
//  RideWeatherWatch Watch App
//

import Foundation
import CoreLocation
import SwiftUI

/// Watch-side copy of the phone's EPA air-quality handling — the category
/// bands/colors from `EPAAirQualityCalculator.Category` and the AirNow
/// current-observations fetch from `AirNowService`. Like the watch's
/// `HeatIndexCalculator`, this copy must stay in sync with the phone
/// implementation (same bands, same EPA colors, same severity ranks).
enum WatchAirQuality {

    /// EPA AQI categories; the rank (1–6) is a stable token safe to persist
    /// or carry across targets.
    enum Category: Int {
        case good = 1
        case moderate
        case unhealthySensitive
        case unhealthy
        case veryUnhealthy
        case hazardous

        init?(severityRank: Int) {
            self.init(rawValue: severityRank)
        }

        init(aqi: Int) {
            switch aqi {
            case ..<51: self = .good
            case ..<101: self = .moderate
            case ..<151: self = .unhealthySensitive
            case ..<201: self = .unhealthy
            case ..<301: self = .veryUnhealthy
            default: self = .hazardous
            }
        }

        var severityRank: Int { rawValue }

        /// Short labels for the watch's narrow rows ("Sensitive" abbreviates
        /// the phone's "Unhealthy for Sensitive Groups").
        var label: String {
            switch self {
            case .good: return "Good"
            case .moderate: return "Moderate"
            case .unhealthySensitive: return "Sensitive"
            case .unhealthy: return "Unhealthy"
            case .veryUnhealthy: return "Very Unhealthy"
            case .hazardous: return "Hazardous"
            }
        }

        var color: Color {
            switch self {
            case .good: return .green
            case .moderate: return .yellow
            case .unhealthySensitive: return .orange
            case .unhealthy: return .red
            // Official EPA colors, matching the phone — the iOS system
            // purple is too light to carry warning text.
            case .veryUnhealthy: return Color(red: 143/255, green: 63/255, blue: 151/255)
            case .hazardous: return Color(red: 126/255, green: 0/255, blue: 35/255)
            }
        }
    }

    private struct Observation: Codable {
        let parameterName: String
        let aqi: Int

        enum CodingKeys: String, CodingKey {
            case parameterName = "ParameterName"
            case aqi = "AQI"
        }
    }

    private static let apiKey: String? = {
        guard let path = Bundle.main.path(forResource: "AirNow", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 WatchAirQuality: AirNow.plist not found — AQI hidden on watch.")
            return nil
        }
        return dict["AirNowApiKey"]
    }()

    private static var cached: (value: Int, severityRank: Int, timestamp: Date)?

    /// Max official AirNow AQI across current per-pollutant observations
    /// (25-mile reporting-area search), or nil when there is no key, no US
    /// coverage, or the request fails — the watch simply hides the row.
    /// 30-minute cache; the watch stays at one location, so no key needed.
    static func fetchCurrentAQI(for coordinate: CLLocationCoordinate2D) async -> (value: Int, severityRank: Int)? {
        if let cached, Date().timeIntervalSince(cached.timestamp) < 1800 {
            return (cached.value, cached.severityRank)
        }
        guard let apiKey else { return nil }
        guard let url = URL(string: "https://www.airnowapi.org/aq/observation/latLong/current/?format=application/json&latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&distance=25&API_KEY=\(apiKey)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let observations = try JSONDecoder().decode([Observation].self, from: data)
            guard let worst = observations.filter({ $0.aqi >= 0 }).max(by: { $0.aqi < $1.aqi }) else {
                return nil
            }
            let value = min(worst.aqi, 500)
            let severityRank = Category(aqi: value).severityRank
            cached = (value, severityRank, Date())
            return (value, severityRank)
        } catch {
            print("⚠️ Watch AirNow unavailable: \(error)")
            return nil
        }
    }
}
