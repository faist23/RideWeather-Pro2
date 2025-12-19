//
//  GarminRouteImportView.swift
//  RideWeather Pro
//
//  Import a route from a Garmin activity (Route Forecast flow)
//

import SwiftUI
import CoreLocation

struct GarminRouteImportView: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var activities: [GarminActivitySummary] = []
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importingId: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                content

                if isImporting {
                    ProcessingOverlay.importing(
                        "Garmin Activity",
                        subtitle: "Extracting route and elevation"
                    )
                    .zIndex(10)
                }
            }
            .navigationTitle("Import Garmin Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if activities.isEmpty {
                    await loadActivities()
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && activities.isEmpty {
            ProgressView("Loading activities…")
        } else if let errorMessage {
            errorView(errorMessage)
        } else if activities.isEmpty {
            emptyView
        } else {
            activitiesList
        }
    }

    private var activitiesList: some View {
        List {
            ForEach(activities) { activity in
                Button {
                    importRoute(from: activity)
                } label: {
                    HStack {
                        GarminActivityRow(activity: activity)
                            .environmentObject(weatherViewModel)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                .disabled(importingId != nil)
            }
        }
        .refreshable {
            await loadActivities()
        }
    }

    // MARK: - States

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Activities Found")
                .font(.headline)

            Text("Recent Garmin cycling activities will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Unable to Load Activities")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await loadActivities() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Data

    private func loadActivities() async {
        isLoading = true
        errorMessage = nil

        do {
            activities = try await garminService.fetchRecentActivities(limit: 50)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func importRoute(from activity: GarminActivitySummary) {
        importingId = activity.activityId
        isImporting = true

        Task {
            do {
                let detail = try await garminService.fetchActivityDetails(
                    activityId: activity.activityId
                )

                let coordinates = extractRouteCoordinates(from: detail)

                guard !coordinates.isEmpty else {
                    throw GarminRouteImportError.noRouteData
                }

                await MainActor.run {
                    weatherViewModel.clearAdvancedPlan()

                    weatherViewModel.routePoints = coordinates
                    weatherViewModel.routeDisplayName =
                        activity.activityName ?? "Garmin Ride"
                    weatherViewModel.importedRouteDisplayName =
                        activity.activityName ?? "Garmin Ride"
                    weatherViewModel.importSource = "Garmin" 
                }

                await weatherViewModel.finalizeRouteImport()

                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()

                dismiss()

            } catch {
                await MainActor.run {
                    errorMessage = "Failed to import route: \(error.localizedDescription)"
                    isImporting = false
                    importingId = nil
                }
            }
        }
    }

    // MARK: - Route Extraction

    private func extractRouteCoordinates(
        from activity: GarminActivityDetail
    ) -> [CLLocationCoordinate2D] {

        guard let samples = activity.samples else { return [] }

        return samples.compactMap { sample in
            guard let lat = sample.latitude,
                  let lon = sample.longitude else {
                return nil
            }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
}

// MARK: - Errors

enum GarminRouteImportError: LocalizedError {
    case noRouteData

    var errorDescription: String? {
        "This activity does not contain route GPS data."
    }
}


/*
//
//  GarminRouteImportView.swift
//  RideWeather Pro
//

import SwiftUI

struct GarminRouteImportView: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var courses: [GarminCourse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    
    var filteredCourses: [GarminCourse] {
        if searchText.isEmpty {
            return courses
        }
        return courses.filter { $0.courseName.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading your Garmin courses...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange)
                        Text("Unable to load courses")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            Task { await loadCourses() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if courses.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        Text("No Courses Found")
                            .font(.headline)
                        Text("Create courses in Garmin Connect to import them here")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(filteredCourses) { course in
                            CourseRow(course: course) {
                                Task {
                                    await importCourse(course)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search courses")
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Import from Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadCourses()
            }
        }
    }
    
    private func loadCourses() async {
        isLoading = true
        errorMessage = nil
        
        print("📥 GarminRouteImportView: Starting to load courses...")
        
        do {
            courses = try await garminService.fetchCourses()
            print("✅ GarminRouteImportView: Successfully loaded \(courses.count) courses")
            if courses.isEmpty {
                errorMessage = nil // Show empty state instead of error
            }
        } catch {
            let errorMsg = error.localizedDescription
            errorMessage = errorMsg
            print("❌ GarminRouteImportView: Failed to load courses")
            print("   Error: \(errorMsg)")
            if let garminError = error as? GarminService.GarminError {
                print("   Garmin Error Type: \(garminError)")
            }
        }
        
        isLoading = false
    }
    
    private func importCourse(_ course: GarminCourse) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch the full course details with GPS points
            let routePoints = try await garminService.fetchCourseDetails(courseId: course.courseId)
            
            // Convert RoutePoint to CLLocationCoordinate2D
            let coordinates = routePoints.map { $0.coordinate }
            
            await MainActor.run {
                viewModel.routePoints = coordinates
                viewModel.routeDisplayName = course.courseName
                viewModel.authoritativeRouteDistanceMeters = course.distance
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to import course: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

struct CourseRow: View {
    let course: GarminCourse
    let onImport: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.courseName)
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Label(formatDistance(course.distance), systemImage: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let elevGain = course.elevationGain {
                        Label(formatElevation(elevGain), systemImage: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button {
                onImport()
            } label: {
                Text("Import")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.1f km", km)
    }
    
    private func formatElevation(_ meters: Double) -> String {
        return String(format: "%.0f m", meters)
    }
}

// MARK: - Models

struct GarminCourse: Identifiable, Codable {
    let courseId: Int
    let courseName: String
    let distance: Double // meters
    let elevationGain: Double?
    let elevationLoss: Double?
    
    var id: Int { courseId }
    
    enum CodingKeys: String, CodingKey {
        case courseId
        case courseName
        case distance
        case elevationGain
        case elevationLoss
    }
}*/

/*
import SwiftUI
import CoreLocation
import Combine

struct GarminRouteImportView: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = GarminActivitiesImportViewModel()
    let onDismiss: () -> Void
    
    @State private var importingId: Int? = nil // For per-row loading
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Main Content Layer
                Group {
                    if viewModel.isLoading && viewModel.activities.isEmpty {
                        ProgressView("Loading activities...")
                    } else if let error = viewModel.errorMessage {
                        errorView(error: error)
                    } else if viewModel.activities.isEmpty {
                        emptyActivitiesView
                    } else {
                        activitiesList
                    }
                }
                
                // Loading Overlay Layer
                if viewModel.isImporting {
                    ProcessingOverlay.importing(
                        "Garmin Activity",
                        subtitle: "Extracting GPS data and elevation profile"
                    )
                    .zIndex(1)
                }
            }
            .navigationTitle("Import Garmin Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
        .onAppear {
            if viewModel.activities.isEmpty {
                viewModel.loadActivities(service: garminService)
            }
        }
    }
    
    private var activitiesList: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "figure.outdoor.cycle")
                        .foregroundColor(.orange)
                    Text("\(viewModel.activities.count) activities")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            // Activity list
            ForEach(viewModel.activities) { activity in
                Button(action: {
                    importingId = activity.id
                    viewModel.importRouteFromActivity(
                        activityId: activity.activityId,
                        activityName: activity.activityName ?? "Garmin Ride",
                        activityDate: activity.startDate,
                        service: garminService,
                        weatherViewModel: weatherViewModel,
                        onSuccess: {
                            importingId = nil
                            onDismiss()
                        },
                        onFailure: {
                            importingId = nil
                        }
                    )
                }) {
                    HStack {
                        GarminActivityRow(activity: activity)
                            .environmentObject(weatherViewModel)
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                .disabled(importingId != nil) // Disable all rows while importing
            }
        }
        .refreshable {
            viewModel.loadActivities(service: garminService)
        }
    }
    
    private var emptyActivitiesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Activities Found")
                .font(.headline)
            Text("Your recent Garmin rides will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("Error Loading Activities")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                viewModel.loadActivities(service: garminService)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - View Model for this specific import flow

@MainActor
class GarminActivitiesImportViewModel: ObservableObject {
    @Published var activities: [GarminActivitySummary] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    
    func loadActivities(service: GarminService) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedActivities = try await service.fetchRecentActivities(limit: 50)
                
                // Filter for activities with GPS data (distance > 0)
                let filteredActivities = fetchedActivities.filter {
                    ($0.distanceInMeters ?? 0) > 0
                }
                
                await MainActor.run {
                    self.activities = filteredActivities
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func importRouteFromActivity(
        activityId: Int,
        activityName: String,
        activityDate: Date,
        service: GarminService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                // 1. Fetch activity details with GPS samples
                let activityDetail = try await service.fetchActivityDetails(activityId: activityId)
                
                // 2. Extract route from GPS samples
                let (coordinates, elevationAnalysis) = try extractRouteFromActivity(activityDetail)
                
                guard !coordinates.isEmpty else {
                    throw GarminService.GarminError.apiError(statusCode: 0, message: "No GPS data in activity")
                }
                
                // 3. Update WeatherViewModel
                weatherViewModel.clearAdvancedPlan()
                
                // Convert RoutePoint to CLLocationCoordinate2D
                let clCoordinates = coordinates.map { point in
                    CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                }
                
                weatherViewModel.routePoints = clCoordinates
                weatherViewModel.routeDisplayName = activityName
                weatherViewModel.importedRouteDisplayName = activityName
                
                // Populate elevation data
                weatherViewModel.elevationAnalysis = elevationAnalysis
                
                // Store authoritative distance
                if let distance = activityDetail.distanceInMeters {
                    weatherViewModel.authoritativeRouteDistanceMeters = distance
                }
                
                // 4. Finalize import
                if elevationAnalysis != nil {
                    await weatherViewModel.finalizeRouteImport()
                }
                
                self.isImporting = false
                
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                onSuccess()
                
            } catch {
                self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                self.isImporting = false
                onFailure()
            }
        }
    }
    
    // MARK: - Route Extraction
    
    private func extractRouteFromActivity(_ activity: GarminActivityDetail) throws -> ([RoutePoint], ElevationAnalysis?) {
        guard let samples = activity.samples, !samples.isEmpty else {
            throw GarminService.GarminError.apiError(statusCode: 0, message: "No GPS samples")
        }
        
        // Filter samples with valid GPS coordinates
        let validSamples = samples.filter { sample in
            sample.latitude != nil && sample.longitude != nil
        }
        
        guard !validSamples.isEmpty else {
            throw GarminService.GarminError.apiError(statusCode: 0, message: "No valid GPS coordinates")
        }
        
        print("GarminRouteImport: Processing \(validSamples.count) GPS points")
        
        // Convert to RoutePoints with cumulative distance
        var routePoints: [RoutePoint] = []
        var cumulativeDistance: Double = 0
        var previousLocation: CLLocation?
        
        // Track elevation
        var elevations: [Double] = []
        var totalClimb: Double = 0
        var totalDescent: Double = 0
        
        for sample in validSamples {
            guard let lat = sample.latitude, let lon = sample.longitude else { continue }
            
            let currentLocation = CLLocation(latitude: lat, longitude: lon)
            
            // Calculate distance from previous point
            if let prevLoc = previousLocation {
                let segmentDistance = currentLocation.distance(from: prevLoc)
                cumulativeDistance += segmentDistance
            }
            
            // Track elevation changes
            if let elevation = sample.elevation {
                elevations.append(elevation)
                
                if let lastElevation = elevations.dropLast().last {
                    let change = elevation - lastElevation
                    if change > 0 {
                        totalClimb += change
                    } else {
                        totalDescent += abs(change)
                    }
                }
            }
            
            let routePoint = RoutePoint(
                latitude: lat,
                longitude: lon,
                elevation: sample.elevation,
                distance: cumulativeDistance
            )
            
            routePoints.append(routePoint)
            previousLocation = currentLocation
        }
        
        print("GarminRouteImport: Extracted \(routePoints.count) route points")
        print("GarminRouteImport: Total distance: \(String(format: "%.2f", cumulativeDistance / 1000))km")
        
        // Create elevation analysis
        var elevationAnalysis: ElevationAnalysis?
        if !elevations.isEmpty {
            // Convert elevations to ElevationPoint array with grade calculation
            var elevationPoints: [ElevationPoint] = []
            
            for index in elevations.indices {
                let elevation = elevations[index]
                let distance = routePoints[index].distance
                
                // Calculate grade from previous point
                var grade: Double = 0
                if index > 0 {
                    let elevChange = elevation - elevations[index - 1]
                    let distChange = distance - routePoints[index - 1].distance
                    if distChange > 0 {
                        grade = (elevChange / distChange) * 100 // Convert to percentage
                    }
                }
                
                elevationPoints.append(ElevationPoint(
                    distance: distance,
                    elevation: elevation,
                    grade: grade
                ))
            }
            
            elevationAnalysis = ElevationAnalysis(
                totalGain: totalClimb,
                totalLoss: totalDescent,
                maxElevation: elevations.max() ?? 0,
                minElevation: elevations.min() ?? 0,
                elevationProfile: elevationPoints,
                hasActualData: true
            )
            
            print("GarminRouteImport: Climb: \(String(format: "%.0f", totalClimb))m, Descent: \(String(format: "%.0f", totalDescent))m")
        }
        
        return (routePoints, elevationAnalysis)
    }
}

struct CourseRow: View {
    let course: GarminCourse
    let onImport: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.courseName)
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Label(formatDistance(course.distance), systemImage: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let elevGain = course.elevationGain {
                        Label(formatElevation(elevGain), systemImage: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button {
                onImport()
            } label: {
                Text("Import")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.1f km", km)
    }
    
    private func formatElevation(_ meters: Double) -> String {
        return String(format: "%.0f m", meters)
    }
}

// MARK: - Models
*/struct GarminCourse: Identifiable, Codable {
    let courseId: Int
    let courseName: String
    let distance: Double
    let elevationGain: Double?
    let elevationLoss: Double?
    
    var id: Int { courseId }
    
    enum CodingKeys: String, CodingKey {
        case courseId
        case courseName
        case distance
        case elevationGain
        case elevationLoss
    }
}

