//
//  GarminRouteImportView.swift
//  RideWeather Pro
//
//  Import a route from a Garmin activity (Route Forecast flow)
//  Fixed: Now extracts Elevation Data to prevent "No Route Data" errors
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
                // 1. Fetch detailed activity data (Samples)
                let detail = try await garminService.fetchActivityDetails(
                    activityId: activity.activityId
                )

                // 2. Extract Route & Elevation
                let (coordinates, elevationAnalysis) = extractRouteAndElevation(from: detail)

                guard !coordinates.isEmpty else {
                    throw GarminRouteImportError.noRouteData
                }

                await MainActor.run {
                    weatherViewModel.clearAdvancedPlan()
                    
                    // Set the coordinates
                    weatherViewModel.routePoints = coordinates
                    weatherViewModel.routeDisplayName = activity.activityName ?? "Garmin Ride"
                    weatherViewModel.importedRouteDisplayName = activity.activityName ?? "Garmin Ride"
                    weatherViewModel.importSource = "Garmin"
                    
                    // 3. INJECT ELEVATION (The Fix)
                    // This prevents the app from trying to re-fetch elevation and failing.
                    if let elevation = elevationAnalysis {
                        weatherViewModel.elevationAnalysis = elevation
                        weatherViewModel.authoritativeRouteDistanceMeters = detail.distanceInMeters
                    }
                }

                // 4. Finalize
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

    // MARK: - Route Extraction (Enhanced)

    private func extractRouteAndElevation(
        from activity: GarminActivityDetail
    ) -> ([CLLocationCoordinate2D], ElevationAnalysis?) {

        guard let samples = activity.samples else { return ([], nil) }

        var coordinates: [CLLocationCoordinate2D] = []
        var elevationPoints: [ElevationPoint] = []
        
        var cumulativeDistance: Double = 0
        var previousLoc: CLLocation?
        var totalClimb: Double = 0
        var totalDescent: Double = 0
        var minElev: Double = 10000
        var maxElev: Double = -10000
        var previousElev: Double?

        for sample in samples {
            guard let lat = sample.latitude, let lon = sample.longitude else { continue }
            
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            coordinates.append(coord)
            
            // Calculate Elevation Data
            let location = CLLocation(latitude: lat, longitude: lon)
            if let prev = previousLoc {
                cumulativeDistance += location.distance(from: prev)
            }
            previousLoc = location
            
            if let elev = sample.elevation {
                minElev = min(minElev, elev)
                maxElev = max(maxElev, elev)
                
                // Calculate grade
                var grade: Double = 0
                if let prevE = previousElev, let lastPoint = elevationPoints.last {
                    let distChange = cumulativeDistance - lastPoint.distance
                    if distChange > 1 { // Avoid division by zero
                        grade = ((elev - prevE) / distChange) * 100.0
                    }
                }
                
                if let prevE = previousElev {
                    let diff = elev - prevE
                    if diff > 0 { totalClimb += diff }
                    else { totalDescent += abs(diff) }
                }
                
                elevationPoints.append(ElevationPoint(
                    distance: cumulativeDistance,
                    elevation: elev,
                    grade: grade
                ))
                
                previousElev = elev
            }
        }
        
        // Construct Elevation Analysis if data exists
        var analysis: ElevationAnalysis? = nil
        if !elevationPoints.isEmpty {
            analysis = ElevationAnalysis(
                totalGain: totalClimb,
                totalLoss: totalDescent,
                maxElevation: maxElev,
                minElevation: minElev,
                elevationProfile: elevationPoints,
                hasActualData: true
            )
        }
        
        return (coordinates, analysis)
    }
}

// MARK: - Errors

enum GarminRouteImportError: LocalizedError {
    case noRouteData

    var errorDescription: String? {
        "This activity does not contain route GPS data."
    }
}

