//
//  WeatherViewModel.swift - Updated with filename tracking
//

import SwiftUI
import Combine
import CoreLocation
import MapKit

@MainActor
class WeatherViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var displayWeather: DisplayWeatherModel?
    @Published var hourlyForecast: [HourlyForecast] = []
    @Published var allHourlyData: [HourlyForecast] = []
    @Published var rideDate: Date = Date()
    @Published var enhancedInsights: EnhancedWeatherInsights?
    @Published var settings: AppSettings {
        didSet {
            UserDefaultsManager.shared.saveSettings(settings)
            if oldValue.units != settings.units {
                Task { await fetchAllWeather() }
                let currentSpeed = Double(averageSpeedInput) ?? settings.averageSpeed
                if oldValue.units == .metric && settings.units == .imperial {
                    let newSpeed = currentSpeed * 0.621371
                    averageSpeedInput = String(format: "%.1f", newSpeed)
                    settings.averageSpeed = newSpeed
                } else if oldValue.units == .imperial && settings.units == .metric {
                    let newSpeed = currentSpeed * 1.60934
                    averageSpeedInput = String(format: "%.1f", newSpeed)
                    settings.averageSpeed = newSpeed
                }
            }
        }
    }
    @Published var routePoints: [CLLocationCoordinate2D] = []
    @Published var weatherDataForRoute: [RouteWeatherPoint] = []
    @Published var averageSpeedInput: String = "16.5"
    @Published var locationName: String = "Loading location..."
    @Published var uiState: UIState = .loading
    @Published var currentLocation: CLLocation?
    
    // NEW: Filename tracking properties
    @Published var lastImportedFileName: String? = nil
    @Published var importedRouteDisplayName: String = ""
    
    // Advanced pacing properties
    @Published var advancedController: AdvancedCyclingController?
    @Published var isGeneratingAdvancedPlan = false
    @Published var intensityAdjustment: Double = 0.0
    @Published var advancedPlanError: String?
    @Published var selectedPacingStrategy: PacingStrategy = .balanced

    // MARK: - Analytics Properties
    @Published var showingAnalytics = false
    
    @Published var elevationAnalysis: ElevationAnalysis?
    @Published var powerAnalysisResult: PowerRouteAnalysisResult?

    @Published var enhancedRoutePoints: [EnhancedRoutePoint] = []

    @Published var currentRideAnalyzer: RideFileAnalyzer?
    @Published var lastPowerAnalysis: PowerRouteAnalysisResult?
    
    // MARK: - Dependencies
    let initialDataLoaded = PassthroughSubject<Void, Never>()
    private var hasLoadedInitialData = false
    private let weatherRepo = WeatherRepository()
    private let locationManager = LocationManager()
    private let hapticsManager = HapticsManager.shared
    private let backgroundProcessor = RouteProcessor()
    private let cityNameResolver = CityNameResolver()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties
    var locationDisplayName: String { locationName.isEmpty ? "Current Location" : locationName }
    var formattedRideDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: rideDate)
    }
    var isLoading: Bool {
        if case .loading = uiState { return true }
        if case .parsing = uiState { return true }
        return false
    }
    var errorMessage: String? {
        if case .error(let msg) = uiState { return msg }
        return nil
    }
    
    var averageSpeedMetersPerSecond: Double {
        guard let speed = Double(averageSpeedInput) else { return 7.15 }
        let baseSpeed = settings.units == .metric ? speed * 1000 / 3600 : speed * 0.44704
        
        print("Base speed calculation: \(speed) \(settings.units.speedUnitAbbreviation) = \(baseSpeed) m/s")
        
        return baseSpeed
    }
    
    // NEW: Computed property for route display name
    var routeDisplayName: String {
        if !importedRouteDisplayName.isEmpty {
            return importedRouteDisplayName
        }
        if let fileName = lastImportedFileName, !fileName.isEmpty {
            return cleanFileName(fileName)
        }
        return "Imported Route"
    }

    // MARK: - Analytics Computed Properties
    var hourlyForecasts: [HourlyForecast] {
        return allHourlyData.isEmpty ? hourlyForecast : allHourlyData
    }

    var finalPacingPlan: PacingPlan? {
        // This will return the original plan if adjustment is 0, or the tweaked plan otherwise.
        return advancedController?.pacingPlan?.applying(intensityAdjustment: intensityAdjustment)
    }

    // MARK: - Init
    init() {
        self.settings = UserDefaultsManager.shared.loadSettings()
        self.averageSpeedInput = String(settings.averageSpeed)
        locationManager.$location
            .compactMap { $0 }
            .first()
            .sink { [weak self] location in
                guard let self = self else { return }
                self.currentLocation = location
                Task { @MainActor in await self.fetchAllWeather(for: location) }
            }
            .store(in: &cancellables)

        locationManager.$authorizationStatus
            .sink { [weak self] status in
                guard let self = self else { return }
                if status == .denied {
                    self.uiState = .error("Location access denied. Enable it in Settings.")
                    if !self.hasLoadedInitialData {
                        self.hasLoadedInitialData = true
                        self.initialDataLoaded.send()
                    }
                }
            }
            .store(in: &cancellables)

        locationManager.requestLocationAccess()
    }

    // MARK: - Filename Helper Methods
    
    /// Cleans up filename for display by removing extension and path components
    private func cleanFileName(_ fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
        
        // Replace underscores and hyphens with spaces for better readability
        return nameWithoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
    
    /// Generates export filename with custom suffix
    func generateExportFilename(baseName: String? = nil, suffix: String, extension fileExtension: String) -> String {
        let routeName: String
        if let baseName = baseName, !baseName.isEmpty {
            routeName = baseName
        } else if let fileName = lastImportedFileName, !fileName.isEmpty {
            routeName = cleanFileName(fileName)
        } else {
            routeName = "route"
        }
        
        // Clean the route name for filename use
        let cleanName = routeName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        
        return "\(cleanName)-\(suffix).\(fileExtension)"
    }

    // MARK: - Route Import Methods (Updated)
    
    func importRoute(from url: URL) {
        Task {
            uiState = .parsing(0.0)
            weatherDataForRoute = []
            routePoints = []
            elevationAnalysis = nil
            
            // ✅ ADDED: Clear the advanced plan and cached power analysis to prevent showing stale data.
            advancedController = nil
            powerAnalysisResult = nil
            
            // Store filename information
            let fileName = url.lastPathComponent
            self.lastImportedFileName = fileName
            self.importedRouteDisplayName = cleanFileName(fileName)

            let parser = RouteParser()
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let fileData = try Data(contentsOf: url)
                uiState = .parsing(0.2)
                
                let result: (coordinates: [CLLocationCoordinate2D], elevationAnalysis: ElevationAnalysis?)
                let fileExtension = url.pathExtension.lowercased()
                if fileExtension == "gpx" {
                    result = try parser.parseWithElevation(gpxData: fileData)
                } else if fileExtension == "fit" {
                    result = try parser.parseWithElevation(fitData: fileData)
                } else {
                    throw RouteParseError.unknownFileType
                }

                uiState = .parsing(0.8)
                try await Task.sleep(nanoseconds: 200_000_000)

                self.routePoints = result.coordinates
                self.elevationAnalysis = result.elevationAnalysis
                self.powerAnalysisResult = nil // Clear the cache

                self.finalizeRouteImport()

                if let analysis = result.elevationAnalysis, analysis.hasActualData {
                    print("✅ Successfully imported route with elevation data. Total Gain: \(analysis.totalGain)m")
                } else {
                    print("⚠️ Route imported, but no elevation data was found or generated.")
                }
                
                // Fetch extended hourly data for the new route
                try await self.fetchExtendedHourlyData()

                uiState = .loaded
                hapticsManager.triggerSuccess()
            } catch {
                // Clear filename info on error
                self.lastImportedFileName = nil
                self.importedRouteDisplayName = ""
                uiState = .error("Failed to parse route file: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Existing Methods (unchanged)
    
    func refreshWeather() async {
        guard let location = currentLocation else { return }
        rideDate = Date()
        uiState = .loading
        
        do {
            let completeData = try await weatherRepo.fetchCompleteWeatherData(
                for: location,
                units: settings.units.rawValue
            )
            await processWeatherData(current: completeData.current, forecast: completeData.forecast)
            self.enhancedInsights = completeData.enhancedInsights
            uiState = .loaded
        } catch {
            uiState = .error("Failed to fetch weather: \(error.localizedDescription)")
        }
    }
    
    func fetchAllWeather(for initialLocation: CLLocation? = nil) async {
        guard locationManager.authorizationStatus != .denied else { return }
        guard let location = initialLocation ?? locationManager.location else {
            uiState = .loading
            return
        }

        uiState = .loading
        Task { await cityNameResolver.getCityName(for: location, into: self) }

        do {
            let completeData = try await weatherRepo.fetchCompleteWeatherData(
                for: location,
                units: settings.units.rawValue
            )
            await processWeatherData(current: completeData.current, forecast: completeData.forecast)
            self.enhancedInsights = completeData.enhancedInsights
            try await fetchExtendedHourlyData()
            uiState = .loaded
            hapticsManager.triggerSuccess()

            if !hasLoadedInitialData {
                hasLoadedInitialData = true
                initialDataLoaded.send()
            }
        } catch {
            uiState = .error("Failed to fetch weather: \(error.localizedDescription)")
        }
    }

    func openAnalytics() async {
        if !allHourlyData.isEmpty {
            showingAnalytics = true
            return
        }

        uiState = .loading
        do {
            try await fetchExtendedHourlyData()
            uiState = .loaded
            showingAnalytics = true
        } catch {
            print("❌ Failed to fetch extended data for analytics: \(error.localizedDescription)")
            uiState = .error("Could not load the detailed forecast. Please try again.")
        }
    }

    func fetchExtendedHourlyData() async throws {
        guard locationManager.authorizationStatus != .denied else { return }
        guard let location = locationManager.location else { return }

        let fetchedData = try await weatherRepo.fetchExtendedForecast(
            for: location,
            units: settings.units.rawValue
        )

        let currentAQI = self.enhancedInsights?.airQuality
        self.allHourlyData = fetchedData.map { forecast in
            var mutableForecast = forecast
            mutableForecast.aqi = currentAQI
            return mutableForecast
        }
    }
    
    func calculateAndFetchWeather() async {
        guard !routePoints.isEmpty else { return }
        uiState = .loading
        weatherDataForRoute = []
        
        let keyPointCoordinates = generateAdaptiveSamplePoints(from: self.routePoints)
        print("✅ Index-based sampling generated \(keyPointCoordinates.count) key points to fetch.")
        
        let adjustedSpeed = calculateAdjustedSpeed(baseSpeed: averageSpeedMetersPerSecond)
        
        let pointsWithETAs = await backgroundProcessor.calculateETAs(
            for: keyPointCoordinates,
            from: routePoints,
            rideDate: rideDate,
            avgSpeed: adjustedSpeed
        )
 
        var fetchedPoints: [RouteWeatherPoint] = []
        var lastSuccessfulWeather: DisplayWeatherModel? = nil

        for point in pointsWithETAs {
            if let weatherPoint = await weatherRepo.fetchWeatherForRoutePoint(
                coordinate: point.coordinate,
                time: point.eta,
                distance: point.distance,
                units: self.settings.units.rawValue
            ) {
                fetchedPoints.append(weatherPoint)
                lastSuccessfulWeather = weatherPoint.weather
            } else {
                if let lastWeather = lastSuccessfulWeather {
                    fetchedPoints.append(
                        RouteWeatherPoint(
                            coordinate: point.coordinate,
                            distance: point.distance,
                            eta: point.eta,
                            weather: lastWeather
                        )
                    )
                } else {
                    uiState = .error("Failed to fetch initial weather data for the route.")
                    return
                }
            }
        }

        self.weatherDataForRoute = fetchedPoints.sorted { $0.distance < $1.distance }
        self.uiState = .loaded
     }
    
    private func generateAdaptiveSamplePoints(from points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let targetFetchCount = 8
        
        guard points.count > targetFetchCount else {
            return points
        }
        
        var keyPoints = [CLLocationCoordinate2D]()
        let step = Double(points.count - 1) / Double(targetFetchCount - 1)
        
        for i in 0..<targetFetchCount {
            let index = Int(round(Double(i) * step))
            if index < points.count {
                keyPoints.append(points[index])
            }
        }
        
        var uniquePoints = [CLLocationCoordinate2D]()
        var seenCoords = Set<HashableCoordinate>()
        for point in keyPoints {
            let hashablePoint = HashableCoordinate(point)
            if !seenCoords.contains(hashablePoint) {
                uniquePoints.append(point)
                seenCoords.insert(hashablePoint)
            }
        }
        
        return uniquePoints
    }
    
    private func calculateAdjustedSpeed(baseSpeed: Double) -> Double {
        var adjustedSpeed = baseSpeed
        if settings.considerElevation, let analysis = self.elevationAnalysis, analysis.hasActualData {
            let totalDistanceMeters = calculateTotalDistance(routePoints)
            if totalDistanceMeters > 0 {
                let gainPerKm = (analysis.totalGain / totalDistanceMeters) * 1000
                let penaltyFactor = 1.0 - (gainPerKm / 10.0) * 0.03
                adjustedSpeed -= (0.3 * analysis.totalGain/100/3)
                print(String(format: "🏔️ Elevation Penalty Applied. Speed adjusted by %.2f%%", (1 - penaltyFactor) * 100))
            }
        }
        if settings.includeRestStops {
            let restStopFactor = 1.0 - (Double(settings.restStopCount) * 0.02)
            adjustedSpeed *= restStopFactor
            print("🛑 Rest Stop Penalty Applied.")
        }
        return adjustedSpeed
    }

    private func calculateTotalDistance(_ points: [CLLocationCoordinate2D]) -> Double {
        guard points.count > 1 else { return 0 }
        var totalDistance: Double = 0
        for i in 1..<points.count {
            let location1 = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let location2 = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            totalDistance += location2.distance(from: location1)
        }
        return totalDistance
    }
    
    func centerMapOnRoute(_ cameraPosition: inout MapCameraPosition) {
        guard !routePoints.isEmpty else { return }
        let coords = routePoints
        let minLat = coords.map(\.latitude).min() ?? 0
        let maxLat = coords.map(\.latitude).max() ?? 0
        let minLon = coords.map(\.longitude).min() ?? 0
        let maxLon = coords.map(\.longitude).max() ?? 0

        let center = CLLocationCoordinate2D(latitude: (minLat+maxLat)/2, longitude: (minLon+maxLon)/2)
        let span = MKCoordinateSpan(latitudeDelta: max(abs(maxLat-minLat)*1.3, 0.01),
                                    longitudeDelta: max(abs(maxLon-minLon)*1.3, 0.01))
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func processWeatherData(current: CurrentWeatherResponse, forecast: OneCallResponse) async {
        if !current.name.isEmpty { locationName = current.name }
        let rideTimestamp = rideDate.timeIntervalSince1970
        let nowTimestamp = Date().timeIntervalSince1970
        let allData = forecast.hourly

        if abs(rideTimestamp - nowTimestamp) < 600 {
            displayWeather = WeatherMapper.mapCurrentToDisplayModel(current)
            if let startIndex = allData.firstIndex(where: { $0.dt > nowTimestamp }) {
                let upcomingHours = allData.dropFirst(startIndex).prefix(6)
                hourlyForecast = upcomingHours.map { WeatherMapper.mapForecastItemToUIModel($0) }
            }
        } else {
            guard let targetHour = allData.min(by: { abs($0.dt - rideTimestamp) < abs($1.dt - rideTimestamp) }) else {
                displayWeather = WeatherMapper.mapCurrentToDisplayModel(current)
                hourlyForecast = []
                return
            }
            displayWeather = WeatherMapper.mapForecastItemToDisplayModel(targetHour)
            if let startIndex = allData.firstIndex(where: { $0.dt == targetHour.dt }) {
                hourlyForecast = allData.dropFirst(startIndex+1).prefix(6).map { WeatherMapper.mapForecastItemToUIModel($0) }
            }
        }
    }
    
    // MARK: - Advanced Pacing Methods
    
    func generateAdvancedCyclingPlan(
        strategy: PacingStrategy = .balanced,
        startTime: Date = Date()
    ) async {
        await MainActor.run {
            guard !weatherDataForRoute.isEmpty else {
                advancedPlanError = "No route data available. Import a route first."
                return
            }
            
            guard settings.speedCalculationMethod == .powerBased else {
                advancedPlanError = "Enable power-based analysis in settings first."
                return
            }
            
            isGeneratingAdvancedPlan = true
            advancedPlanError = nil
        }
        
        // Create controller if needed
        if advancedController == nil {
            await MainActor.run {
                advancedController = AdvancedCyclingController(settings: settings)
            }
        }
        
        guard let controller = advancedController else {
            await MainActor.run { isGeneratingAdvancedPlan = false }
            return
        }
        
        guard let powerAnalysis = getPowerAnalysisResult() else {
            await MainActor.run {
                advancedPlanError = "Could not generate power analysis for the route."
                isGeneratingAdvancedPlan = false
            }
            return
        }
 
        self.lastPowerAnalysis = powerAnalysis

        debugPowerAnalysis(powerAnalysis)
        
        // Use fueling preferences from settings
        await controller.generateAdvancedRacePlan(
            from: powerAnalysis,
            strategy: strategy,
            fuelingPreferences: settings.fuelingPreferences,
            startTime: startTime,
            routeName: self.routeDisplayName
        )
        
        await MainActor.run {
            isGeneratingAdvancedPlan = false
            print("Plan generated with \(controller.pacingPlan?.segments.count ?? 0) segments")
        }
    }

    private func debugPowerAnalysis(_ analysis: PowerRouteAnalysisResult) {
        print("🔍 POWER ANALYSIS DEBUG:")
        print("   Total segments: \(analysis.segments.count)")
        print("   Total time: \(String(format: "%.1f", analysis.totalTimeSeconds/3600))h")
        print("   Avg speed: \(String(format: "%.1f", analysis.averageSpeedMps * 3.6))km/h")
        
        let totalElevationGain = analysis.segments.reduce(0.0) { result, segment in
            return result + max(0, segment.elevationGrade * segment.distanceMeters)
        }
        
        print("   Total elevation gain: \(Int(totalElevationGain))m")
        
        let powerStats = analysis.segments.map { $0.powerRequired }
        let minPower = powerStats.min() ?? 0
        let maxPower = powerStats.max() ?? 0
        let avgPower = powerStats.reduce(0, +) / Double(powerStats.count)
        
        print("   Power range: \(Int(minPower))W - \(Int(maxPower))W (avg \(Int(avgPower))W)")
        
        let steepSegments = analysis.segments.filter { abs($0.elevationGrade) > 0.08 }
        print("   Steep segments (>8%): \(steepSegments.count)")
        
        let lowPowerSegments = analysis.segments.filter { $0.powerRequired < 100 }
        print("   Low power segments (<100W): \(lowPowerSegments.count)")
        
        if lowPowerSegments.count > analysis.segments.count / 2 {
            print("⚠️ WARNING: Too many low power segments - check your power calculation!")
        }
        
        print("\n🔋 First 5 segments detail:")
        for (index, segment) in analysis.segments.prefix(5).enumerated() {
            print("   \(index + 1): \(Int(segment.distanceMeters))m, \(String(format: "%.1f", segment.elevationGrade * 100))%, \(Int(segment.powerRequired))W")
        }
    }
    
}

fileprivate struct HashableCoordinate: Hashable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

// MARK: - Power Analysis Integration

extension WeatherViewModel {
    var isPowerBasedAnalysisEnabled: Bool {
        settings.speedCalculationMethod == .powerBased
    }
    
    func getPowerAnalysisResult() -> PowerRouteAnalysisResult? {
        if let cachedResult = self.powerAnalysisResult {
            return cachedResult
        }
        
        guard isPowerBasedAnalysisEnabled, !weatherDataForRoute.isEmpty else {
            return nil
        }
        
        print("⚡️ Performing one-time power analysis...")
        let engine = PowerRouteAnalyticsEngine(
            weatherPoints: weatherDataForRoute,
            settings: settings,
            elevationAnalysis: elevationAnalysis
        )
        let result = engine.analyzePowerBasedRoute()
        
        DispatchQueue.main.async {
            self.powerAnalysisResult = result
        }
        
        return result
    }

    func recalculateWithNewSettings() {
        if !weatherDataForRoute.isEmpty {
            Task {
                await calculateAndFetchWeather()
            }
        }
    }
}
// MARK: - WeatherViewModel Route Import Update

extension WeatherViewModel {
    
    /// Call this after importing a route to prepare for FIT export
    func finalizeRouteImport() {
        buildEnhancedRoutePoints()
    }
}

extension WeatherViewModel {
    
    /// Builds enhanced route points from basic coordinates and elevation data
    func buildEnhancedRoutePoints() {
        guard !routePoints.isEmpty else {
            enhancedRoutePoints = []
            return
        }
        
        var enhanced: [EnhancedRoutePoint] = []
        var cumulativeDistance = 0.0
        var previousCoordinate: CLLocationCoordinate2D?
        
        for (index, coordinate) in routePoints.enumerated() {
            // Calculate distance
            if let prevCoord = previousCoordinate {
                let location1 = CLLocation(latitude: prevCoord.latitude, longitude: prevCoord.longitude)
                let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                cumulativeDistance += location2.distance(from: location1)
            }
            
            // Get elevation from elevation analysis if available
            let elevation = elevationAnalysis?.elevation(at: cumulativeDistance)
            
            // Create enhanced point
            let enhancedPoint = EnhancedRoutePoint(
                coordinate: coordinate,
                elevation: elevation,
                distance: cumulativeDistance,
                timestamp: nil
            )
            
            enhanced.append(enhancedPoint)
            previousCoordinate = coordinate
        }
        
        self.enhancedRoutePoints = enhanced
        print("✅ Built \(enhanced.count) enhanced route points")
    }
    
    /// Export Garmin Course FIT file with power targets
    func exportGarminCourseFIT() async throws -> URL? {
        // Build enhanced points if not already done
        if enhancedRoutePoints.isEmpty {
            buildEnhancedRoutePoints()
        }
        
        guard let controller = advancedController,
              let pacing = self.finalPacingPlan, // <-- Grabs the FINAL adjusted plan
              !enhancedRoutePoints.isEmpty else {
            throw GarminCourseFitGenerator.CourseExportError.invalidData("Missing required data")
        }

        // Generate the course name
        let courseName = generateExportFilename(
            baseName: routeDisplayName,
            suffix: "",
            extension: ""
        ).replacingOccurrences(of: "_", with: " ")
        
        // Generate FIT data
        let fitData = try controller.generateGarminCourseFIT(
            pacingPlan: pacing, // <-- Pass the adjusted plan in
            routePoints: enhancedRoutePoints,
            courseName: courseName
        )
        
        guard let data = fitData else {
            throw GarminCourseFitGenerator.CourseExportError.fitSDKError("Failed to generate FIT data")
        }
        
        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = generateExportFilename(
            baseName: routeDisplayName,
            suffix: "course-power",
            extension: "fit"
        )
        let tempFile = tempDir.appendingPathComponent(filename)
        
        try data.write(to: tempFile)
        
        print("✅ Garmin Course FIT exported: \(tempFile.lastPathComponent)")
        
        return tempFile
    }
}
