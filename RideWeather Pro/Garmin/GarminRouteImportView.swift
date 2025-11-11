
//
//  GarminRouteImportView.swift
//  RideWeather Pro
//
//  Sheet for importing a route from a past Garmin activity
//

import SwiftUI
import CoreLocation
import Combine

// MARK: - Main Import View

struct GarminRouteImportView: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: ImportTab = .activities
    
    enum ImportTab {
        case routes
        case activities
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom tab picker
                Picker("Import Type", selection: $selectedTab) {
                    Text("Saved Routes").tag(ImportTab.routes)
                    Text("Activities").tag(ImportTab.activities)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                TabView(selection: $selectedTab) {
                    // --- Saved Routes Tab (Disabled) ---
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Import Not Supported")
                            .font(.headline)
                        Text("The official Garmin API does not allow apps to read or import a user's saved routes or courses.\n\nYou can, however, import the route from a completed activity.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Switch to Activities") {
                            selectedTab = .activities
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .tag(ImportTab.routes)
                    
                    // --- Activities Tab (Enabled) ---
                    GarminActivitiesTab(onDismiss: {
                        dismiss()
                    })
                    .tag(ImportTab.activities)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Import from Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Activities Tab

struct GarminActivitiesTab: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = GarminActivitiesImportViewModel()
    let onDismiss: () -> Void
    
    @State private var importingId: String? = nil // Use String for Garmin's activityId
    
    var body: some View {
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
        .onAppear {
            if viewModel.activities.isEmpty {
                viewModel.loadActivities(service: garminService)
            }
        }
    }
    
    private var activitiesList: some View {
        List {
            Section {
                Text("Showing recent completed activities with GPS data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Activity list
            ForEach(viewModel.activities) { activity in
                Button(action: {
                    importingId = activity.activityId
                    viewModel.importRouteFromActivity(
                        activityId: activity.activityId,
                        activityName: activity.activityName ?? "Garmin Ride",
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
                        if importingId == activity.activityId {
                            ProgressView()
                                .frame(width: 20)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(importingId != nil) // Disable all rows while importing
            }
            
            // Load More section
            if viewModel.hasMorePages {
                Section {
                    Button(action: {
                        viewModel.loadMoreActivities(service: garminService)
                    }) {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Loading...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .font(.title3)
                                Text("Load More Activities")
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(viewModel.isLoadingMore)
                }
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
            Text("Your recent Garmin rides with GPS data will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
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

// MARK: - Activity Row

struct GarminActivityRow: View {
    let activity: GarminActivity
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.activityName ?? "Garmin Ride")
                    .font(.headline)
                
                Spacer()
                
                if (activity.averagePower ?? 0) > 0 {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 16) {
                Label(activity.durationFormatted, systemImage: "clock")
                    .font(.caption)
                
                Label(
                    weatherViewModel.settings.units == .metric ?
                    String(format: "%.2f km", activity.distanceMeters / 1000.0) :
                    String(format: "%.2f mi", activity.distanceMeters / 1609.34),
                    systemImage: "figure.outdoor.cycle"
                )
                .font(.caption)
                
                if let watts = activity.averagePower, watts > 0 {
                    Label("\(Int(watts))W", systemImage: "bolt")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(.secondary)
            
            if let date = activity.startTime {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Activities View Model

@MainActor
class GarminActivitiesImportViewModel: ObservableObject {
    @Published var activities: [GarminActivity] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var isLoadingMore = false
    @Published var hasMorePages = false // Garmin API doesn't support pagination well, load a fixed amount
     
    private var currentPage = 0
    private let perPage = 50 // Load 50 at a time
     
    func loadActivities(service: GarminService) {
        isLoading = true
        errorMessage = nil
        currentPage = 0
        activities = []
        
        loadMoreActivities(service: service) {
            self.isLoading = false
        }
    }
    
    func loadMoreActivities(service: GarminService, completion: (() -> Void)? = nil) {
        guard !isLoadingMore else { return }
        
        isLoadingMore = true
        errorMessage = nil
        
        Task {
            do {
                // Calculate date range (e.g., last 90 days)
                let calendar = Calendar.current
                let endDate = Date()
                let startDate = calendar.date(byAdding: .day, value: -90, to: endDate)!

                let allActivities = try await service.fetchRecentActivities(
                    startDate: startDate,
                    limit: perPage,
                    start: currentPage * perPage
                )
                
                await MainActor.run {
                    // Filter for outdoor cycling with GPS
                    let rides = allActivities.filter {
                        ($0.activityType?.typeKey == "cycling" || $0.activityType?.typeKey == "road_biking") &&
                        ($0.distance ?? 0) > 0
                    }
                    
                    self.activities.append(contentsOf: rides)
                    self.hasMorePages = allActivities.count == perPage // Guess pagination
                    self.isLoadingMore = false
                    self.currentPage += 1
                    completion?()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMore = false
                    completion?()
                }
            }
        }
    }

    func importRouteFromActivity(
        activityId: String,
        activityName: String,
        service: GarminService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                // Use the new service function
                let (coordinates, totalDistance) = try await service.extractRouteFromGarminActivity(activityId: activityId)
                
                guard !coordinates.isEmpty else {
                    throw GarminService.GarminError.noRouteData
                }
                
                // Update the main view model
                await MainActor.run {
                    weatherViewModel.routePoints = coordinates
                    weatherViewModel.routeDisplayName = activityName
                    weatherViewModel.authoritativeRouteDistanceMeters = totalDistance
                    
                    self.isImporting = false
                    
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    onSuccess()
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
                    onFailure()
                }
            }
        }
    }
}
