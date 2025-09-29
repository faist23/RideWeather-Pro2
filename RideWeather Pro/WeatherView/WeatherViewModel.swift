/*
 //
//  WeatherViewModel.swift
//  RideWeather Pro
//
//  Enhanced with performance optimizations and Swift 6 compatibility
//

import SwiftUI
import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
class WeatherViewModel: ObservableObject {
    // MARK: - Published Properties for UI Binding

    @Published var displayWeather: DisplayWeatherModel?
    @Published var hourlyForecast: [HourlyForecast] = []
    @Published var rideDate: Date = Date()
    @Published var settings: AppSettings {
        didSet {
            UserDefaultsManager.shared.saveSettings(settings)
            if oldValue.units != settings.units {
                Task { await fetchAllWeather() }
                averageSpeedInput = settings.units == .metric ? "25.0" : "16.5"
            }
        }
    }
    @Published var routePoints: [CLLocationCoordinate2D] = []
    @Published var weatherDataForRoute: [RouteWeatherPoint] = []
    @Published var averageSpeedInput: String = "16.5"
    @Published var locationName: String = "Loading location..."
    @Published var routeParsingProgress: Double = 0.0

    @Published var allHourlyData: [HourlyForecast] = [] // NEW: Extended hourly data for analytics

    // MARK: - UI State (Now Equatable for animations)

    enum UIState: Equatable {
        case loading
        case loaded
        case error(String)
        case parsing(Double)
        
        static func == (lhs: UIState, rhs: UIState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.loaded, .loaded):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            case (.parsing(let lhsProgress), .parsing(let rhsProgress)):
                return abs(lhsProgress - rhsProgress) < 0.001
            default:
                return false
            }
        }
    }
    @Published var uiState: UIState = .loading

    // MARK: - Signals
    let initialDataLoaded = PassthroughSubject<Void, Never>()
    private var hasLoadedInitialData = false
    private let weatherService = WeatherService()
    private let locationManager = LocationManager()
    private var cancellables = Set<AnyCancellable>()
    private let hapticsManager = HapticsManager.shared

    // MARK: - Background Processing (Actor-based for Swift 6)
    // CORRECTED: Removed parsing from the background actor as the libraries are not concurrency-safe
    private actor BackgroundProcessor {
        func selectKeyPoints(from points: [CLLocationCoordinate2D], maxPoints: Int) async -> [CLLocationCoordinate2D] {
            guard points.count > 2 else { return points }
            
            var keyPoints: [CLLocationCoordinate2D] = [points.first!]
            let halfwayIndex = points.count / 2
            let halfwayPoint = points[halfwayIndex]

            if maxPoints >= 3 {
                let remainingSlots = maxPoints - 3
                if remainingSlots > 0 {
                    let beforeHalfwaySlots = remainingSlots / 2
                    if beforeHalfwaySlots > 0 {
                        let stepBefore = Double(halfwayIndex - 1) / Double(beforeHalfwaySlots + 1)
                        for i in 1...beforeHalfwaySlots {
                            let index = Int(round(Double(i) * stepBefore))
                            if index > 0 && index < halfwayIndex {
                                keyPoints.append(points[index])
                            }
                        }
                    }
                    keyPoints.append(halfwayPoint)
                    let afterHalfwaySlots = remainingSlots - beforeHalfwaySlots
                    if afterHalfwaySlots > 0 {
                        let stepAfter = Double(points.count - 1 - halfwayIndex) / Double(afterHalfwaySlots + 1)
                        for i in 1...afterHalfwaySlots {
                            let index = halfwayIndex + Int(round(Double(i) * stepAfter))
                            if index < points.count - 1 {
                                keyPoints.append(points[index])
                            }
                        }
                    }
                } else {
                    keyPoints.append(halfwayPoint)
                }
            }
            keyPoints.append(points.last!)

            keyPoints = keyPoints.sorted { point1, point2 in
                guard let index1 = points.firstIndex(where: { $0.latitude == point1.latitude && $0.longitude == point1.longitude }),
                      let index2 = points.firstIndex(where: { $0.latitude == point2.latitude && $0.longitude == point2.longitude }) else {
                    return false
                }
                return index1 < index2
            }

            return keyPoints
        }
        
        func calculateETAs(for points: [CLLocationCoordinate2D], rideDate: Date, avgSpeed: Double) async -> [(coordinate: CLLocationCoordinate2D, distance: Double, eta: Date)] {
            var results: [(coordinate: CLLocationCoordinate2D, distance: Double, eta: Date)] = []
            guard !points.isEmpty else { return [] }
            
            var cumulativeDistance: Double = 0
            var previousLocation = CLLocation(latitude: points.first!.latitude, longitude: points.first!.longitude)

            results.append((coordinate: points.first!, distance: 0, eta: rideDate))

            for i in 1..<points.count {
                let currentLocation = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
                let distanceSegment = currentLocation.distance(from: previousLocation)
                cumulativeDistance += distanceSegment
                let timeToTravelSegment = distanceSegment / avgSpeed
                let eta = results.last!.eta.addingTimeInterval(timeToTravelSegment)
                results.append((coordinate: points[i], distance: cumulativeDistance, eta: eta))
                previousLocation = currentLocation
            }
            
            return results
        }
    }
    
    private let backgroundProcessor = BackgroundProcessor()

    // MARK: - Computed Properties for UI

    var locationDisplayName: String {
        return locationName.isEmpty ? "Current Location" : locationName
    }
    
    var formattedRideDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: rideDate)
    }

    var isLoading: Bool {
        switch uiState {
        case .loading, .parsing(_):
            return true
        default:
            return false
        }
    }
    
    
    var errorMessage: String? {
        if case .error(let msg) = uiState { return msg }
        return nil
    }

    private var averageSpeedMetersPerSecond: Double {
        guard let speed = Double(averageSpeedInput) else { return 7.15 }
        return settings.units == .metric ? speed * 1000 / 3600 : speed * 0.44704
    }

    // MARK: - Initialization

    init() {
        self.settings = UserDefaultsManager.shared.loadSettings()

        locationManager.$location
            .compactMap { $0 }
            .first()
            .sink { [weak self] location in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.fetchAllWeather(for: location)
                }
            }
            .store(in: &cancellables)

        locationManager.$authorizationStatus
            .sink { [weak self] status in
                guard let self = self else { return }
                Task { @MainActor in
                    if status == .denied {
                        self.uiState = .error("Location access denied. Please enable it in Settings.")
                        if !self.hasLoadedInitialData {
                            self.hasLoadedInitialData = true
                            self.initialDataLoaded.send()
                        }
                    }
                }
            }
            .store(in: &cancellables)

        locationManager.requestLocationAccess()
    }

    // MARK: - UI Actions

    func refreshWeather() async {
        if abs(rideDate.timeIntervalSinceNow) < 600 {
            rideDate = Date()
        }
        await fetchAllWeather()
    }

    func fetchAllWeather(for initialLocation: CLLocation? = nil) async {
        guard locationManager.authorizationStatus != .denied else { return }
        
        guard let location = initialLocation ?? locationManager.location else {
            uiState = .loading
            print("Location not available to fetch weather.")
            return
        }

        if !hasLoadedInitialData { uiState = .loading }
        else { uiState = .loading }

        Task {
            await getCityName(for: location)
        }

        do {
            async let currentResponse = weatherService.fetchCurrentWeather(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: settings.units.rawValue
            )
            async let forecastResponse = weatherService.fetchForecast(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: settings.units.rawValue
            )
            
            let (current, forecast) = try await (currentResponse, forecastResponse)
            
            await processWeatherData(current: current, forecast: forecast)
            uiState = .loaded
            hapticsManager.triggerSuccess()

            if !hasLoadedInitialData {
                hasLoadedInitialData = true
                initialDataLoaded.send()
            }
        } catch {
            uiState = .error("Failed to fetch weather: \(error.localizedDescription)")
            if !hasLoadedInitialData {
                hasLoadedInitialData = true
                initialDataLoaded.send()
            }
        }
    }

    // MARK: - Enhanced Route Import with Progress Tracking

    func importRoute(from url: URL) {
        Task {
            uiState = .parsing(0.0)
            weatherDataForRoute = []
            routePoints = []

            let routeParser = RouteParser()

            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let fileData = try Data(contentsOf: url)
                uiState = .parsing(0.2)
                
                // CORRECTED: Parsing is done on the main thread now to avoid concurrency errors
                // from non-Sendable third-party libraries.
                let points: [CLLocationCoordinate2D]
                let fileExtension = url.pathExtension.lowercased()
                if fileExtension == "gpx" {
                    points = try routeParser.parse(gpxData: fileData)
                } else if fileExtension == "fit" {
                    points = try routeParser.parse(fitData: fileData)
                } else {
                    throw RouteParseError.unknownFileType
                }

                uiState = .parsing(0.8)
                try await Task.sleep(nanoseconds: 200_000_000)
                
                routePoints = points
                uiState = .loaded
                hapticsManager.triggerSuccess()
                
            } catch {
                if let parseError = error as? RouteParseError {
                    switch parseError {
                    case .noCoordinatesFound:
                        uiState = .error("The route file was parsed, but no GPS coordinates were found.")
                    case .parsingFailed:
                        uiState = .error("Failed to parse the route file. It may be corrupt or in an unsupported format.")
                    default:
                        uiState = .error("An unknown error occurred while parsing the route file.")
                    }
                } else {
                    uiState = .error("Failed to read the route file: \(error.localizedDescription)")
                }
            }
        }
    }

    func calculateAndFetchWeather() async {
        guard !routePoints.isEmpty else { return }
        uiState = .loading
        weatherDataForRoute = []

        let keyPoints = await backgroundProcessor.selectKeyPoints(from: routePoints, maxPoints: 6)
        let pointsWithETAs = await backgroundProcessor.calculateETAs(
            for: keyPoints,
            rideDate: rideDate,
            avgSpeed: averageSpeedMetersPerSecond
        )

        let weatherPoints = await withTaskGroup(of: RouteWeatherPoint?.self, returning: [RouteWeatherPoint].self) { group in
            for point in pointsWithETAs {
                group.addTask {
                    await self.fetchWeatherForRoutePoint(
                        for: point.coordinate,
                        at: point.eta,
                        cumulativeDistance: point.distance
                    )
                }
            }
            
            var results: [RouteWeatherPoint] = []
            for await weatherPoint in group {
                if let weatherPoint = weatherPoint {
                    results.append(weatherPoint)
                }
            }
            return results
        }

        self.weatherDataForRoute = weatherPoints.sorted { $0.distance < $1.distance }
        self.uiState = .loaded
    }

    func centerMapOnRoute(_ cameraPosition: inout MapCameraPosition) {
        guard !routePoints.isEmpty else { return }

        let coords = routePoints
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLon = coords.map(\.longitude).min() ?? 0
        let maxLon = coords.map(\.longitude).max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max(abs(maxLat - minLat) * 1.3, 0.01),
            longitudeDelta: max(abs(maxLon - minLon) * 1.3, 0.01)
        )

        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Core Logic

    private func processWeatherData(current: CurrentWeatherResponse, forecast: OneCallResponse) async {
        if !current.name.isEmpty {
            locationName = current.name
        }
        
        let rideTimestamp = rideDate.timeIntervalSince1970
        let nowTimestamp = Date().timeIntervalSince1970
        let allHourlyData = forecast.hourly

        if abs(rideTimestamp - nowTimestamp) < 600 {
            displayWeather = mapCurrentToDisplayModel(current)
            if let startIndex = allHourlyData.firstIndex(where: { $0.dt > nowTimestamp }) {
                let upcomingHours = allHourlyData.dropFirst(startIndex).prefix(6)
                hourlyForecast = upcomingHours.map { mapForecastItemToUIModel($0) }
            } else {
                hourlyForecast = allHourlyData.suffix(6).map { mapForecastItemToUIModel($0) }
            }
        } else {
            guard let targetHour = allHourlyData.min(by: { abs($0.dt - rideTimestamp) < abs($1.dt - rideTimestamp) }) else {
                displayWeather = mapCurrentToDisplayModel(current)
                hourlyForecast = []
                return
            }
            displayWeather = mapForecastItemToDisplayModel(targetHour)
            if let startIndex = allHourlyData.firstIndex(where: { $0.dt == targetHour.dt }) {
                hourlyForecast = allHourlyData.dropFirst(startIndex + 1).prefix(6).map { mapForecastItemToUIModel($0) }
            } else {
                hourlyForecast = []
            }
        }
    }

    private func fetchWeatherForRoutePoint(for coordinate: CLLocationCoordinate2D, at time: Date, cumulativeDistance: Double) async -> RouteWeatherPoint? {
        do {
            let forecast = try await weatherService.fetchForecast(lat: coordinate.latitude, lon: coordinate.longitude, units: settings.units.rawValue)
            guard let weatherForHour = forecast.hourly.min(by: { abs($0.dt - time.timeIntervalSince1970) < abs($1.dt - time.timeIntervalSince1970) }) else {
                return nil
            }
            let displayWeather = mapForecastItemToDisplayModel(weatherForHour)
            return RouteWeatherPoint(coordinate: coordinate, distance: cumulativeDistance, eta: time, weather: displayWeather)
        } catch {
            print("Failed to fetch weather for route point: \(error)")
            return nil
        }
    }

    func fetchExtendedHourlyData() async {
        guard locationManager.authorizationStatus != .denied else { return }
        guard let location = locationManager.location else { return }
        
        do {
            let extendedForecast = try await weatherService.fetchExtendedForecast(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                units: settings.units.rawValue
            )
            
            // Convert extended data to HourlyForecast format
            allHourlyData = extendedForecast.hourly.map { item in
                let formatter = DateFormatter()
                formatter.dateFormat = "h a"
                let date = Date(timeIntervalSince1970: TimeInterval(item.dt))
                
                return HourlyForecast(
                    id: UUID(), // Add unique ID
                    time: formatter.string(from: date),
                    iconName: item.weather.first?.icon ?? "sun.max.fill",
                    temp: item.temp,
                    feelsLike: item.feelsLike,
                    pop: item.pop,
                    windSpeed: item.windSpeed,
                    windDirection: getWindDirection(degrees: Double(item.windDeg)),
                    windDeg: item.windDeg
                )
            }
        } catch {
            print("Failed to fetch extended hourly data: \(error)")
        }
    }

    // Helper method for wind direction
    private func getWindDirection(degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return directions[index]
    }
    
    // MARK: - Mapping Functions

    private func mapCurrentToDisplayModel(_ current: CurrentWeatherResponse) -> DisplayWeatherModel {
        return DisplayWeatherModel(
            temp: current.main.temp,
            feelsLike: current.main.feelsLike,
            humidity: current.main.humidity,
            windSpeed: current.wind.speed,
            windDirection: current.wind.direction,
            windDeg: current.wind.deg,
            description: current.weather.first?.description.capitalized ?? "Clear",
            iconName: current.weather.first?.iconName ?? "sun.max.fill"
        )
    }

    private func mapForecastItemToDisplayModel(_ forecastItem: HourlyItem) -> DisplayWeatherModel {
        return DisplayWeatherModel(
            temp: forecastItem.temp,
            feelsLike: forecastItem.feelsLike,
            humidity: 0,
            windSpeed: forecastItem.windSpeed,
            windDirection: forecastItem.windDirection,
            windDeg: forecastItem.windDeg,
            description: forecastItem.weather.first?.description.capitalized ?? "Clear",
            iconName: forecastItem.weather.first?.iconName ?? "sun.max.fill"
        )
    }

    private func mapForecastItemToUIModel(_ item: HourlyItem) -> HourlyForecast {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Date(timeIntervalSince1970: item.dt)
        return HourlyForecast(
            time: formatter.string(from: date),
            iconName: item.weather.first?.iconName ?? "sun.max.fill",
            temp: item.temp,
            feelsLike: item.feelsLike,
            pop: item.pop,
            windSpeed: item.windSpeed,
            windDirection: item.windDirection,
            windDeg: item.windDeg
        )
    }

    // MARK: - City Name with Modern MapKit API

    private func getCityName(for location: CLLocation) async {
        do {
            let request = MKLocalSearch.Request()
            request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
            
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            if let mapItem = response.mapItems.first {
                // CORRECTED: Use mapItem.name as a fallback to avoid deprecated placemark property
                let name = mapItem.name ?? "Unknown Location"
                withAnimation {
                    locationName = name
                }
            }
        } catch {
            print("Failed to find city name with MapKit: \(error)")
            if locationName == "Loading location..." {
                 locationName = "Unknown Location"
            }
        }
    }
}
*/


