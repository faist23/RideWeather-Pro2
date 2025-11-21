//
//  WahooRouteImportView.swift
//  RideWeather Pro
//
//  Sheet for importing a route from a past Wahoo activity
//

import SwiftUI
import CoreLocation
import Combine

// MARK: - Main Import View

struct WahooRouteImportView: View {
    @EnvironmentObject var wahooService: WahooService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = WahooActivitiesImportViewModel()
    let onDismiss: () -> Void
    
    @State private var importingId: Int? = nil // ✅ ADDED: For per-row loading
    
    var body: some View {
        NavigationStack {
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
            .navigationTitle("Import Wahoo Activity")
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
                viewModel.loadActivities(service: wahooService)
            }
        }
    }
    
    private var activitiesList: some View {
        List {
            // ... (your existing activity count Section) ...
            Section {
                HStack {
                    Image(systemName: "figure.outdoor.cycle")
                        .foregroundColor(.blue)
                    Text("\(viewModel.activities.count) activities")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if viewModel.hasMorePages {
                        Text("Tap below to load more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Activity list
            ForEach(viewModel.activities) { activity in
                // ✅ CHANGED: Replaced NavigationLink with Button
                Button(action: {
                    importingId = activity.id
                    viewModel.importRouteFromActivity(
                        activityId: activity.id,
                        activityName: activity.displayName,
                        activityDate: activity.rideDate,
                        service: wahooService,
                        weatherViewModel: weatherViewModel,
                        onSuccess: {
                            importingId = nil
                            onDismiss()
                        },
                        onFailure: { // ✅ ADDED: Handle failure
                            importingId = nil
                        }
                    )
                }) {
                    HStack {
                        // Re-using the row from WahooActivitiesView.swift
                        WahooActivityRow(activity: activity)
                            .environmentObject(weatherViewModel)
                        Spacer()
                        if importingId == activity.id {
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
            
            // ... (your existing Load More section) ...
            if viewModel.hasMorePages {
                Section {
                    Button(action: {
                        viewModel.loadMoreActivities(service: wahooService)
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
            viewModel.loadActivities(service: wahooService)
        }
    }
    
    private var emptyActivitiesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Activities Found")
                .font(.headline)
            Text("Your recent Wahoo rides will appear here")
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
                viewModel.loadActivities(service: wahooService)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - View Model for this specific import flow

@MainActor
class WahooActivitiesImportViewModel: ObservableObject {
    @Published var activities: [WahooWorkoutSummary] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var isLoadingMore = false
    @Published var hasMorePages = true
     
     private var currentPage = 1
     private let perPage = 50
     
    func loadActivities(service: WahooService) {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        activities = []
        
        Task {
            do {
                // This already filters for workout_type_id=0 (Cycling)
                let response = try await service.fetchRecentWorkouts(page: self.currentPage, perPage: perPage) // <-- Fetch page 0
                let allActivities = response.workouts
                
                // --- ADD THIS FILTER ---
                let filteredActivities = allActivities.filter {
                    let distance = Double($0.workoutSummary?.distanceAccum ?? "0") ?? 0
                    return distance > 0
                }
                // --- END ADD ---
                await MainActor.run {
                    self.activities = filteredActivities // <-- Use filtered list
                    if let total = response.total, let p = response.page, let pp = response.perPage, total > 0, pp > 0 {
                        self.hasMorePages = (p + 1) * pp < total
                    } else {
                        // Fallback if pagination data is missing
                        self.hasMorePages = allActivities.count == self.perPage
                    }
                    self.isLoading = false
                    self.currentPage = 2
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func loadMoreActivities(service: WahooService) {
        // This logic would need to be built into your WahooService
        // For now, we just load the first page
        //        print("Load more Wahoo activities logic needed in WahooService")
        //        self.hasMorePages = false // Assume no more pages for now
        guard !isLoadingMore && hasMorePages else { return }
        
        isLoadingMore = true
        errorMessage = nil
        
        Task {
            do {
                let response = try await service.fetchRecentWorkouts(page: self.currentPage, perPage: self.perPage)
                let newActivities = response.workouts
                
                // --- ADD THIS FILTER ---
                let filteredActivities = newActivities.filter {
                    let distance = Double($0.workoutSummary?.distanceAccum ?? "0") ?? 0
                    return distance > 0
                }
                // --- END ADD ---
                await MainActor.run {
                    self.activities.append(contentsOf: filteredActivities) // <-- Use filtered list
                    if let total = response.total, let p = response.page, let pp = response.perPage, total > 0, pp > 0 {
                        self.hasMorePages = (p + 1) * pp < total
                    } else {
                        // Fallback if pagination data is missing
                        self.hasMorePages = newActivities.count == self.perPage
                    }
                    self.isLoadingMore = false
                    self.currentPage += 1
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMore = false
                }
            }
        }
    }

    // ✅ UPDATED: Added onFailure callback
    func importRouteFromActivity(
        activityId: Int,
        activityName: String,
        activityDate: Date?,
        service: WahooService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void // ✅ ADDED
    ) {
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                // Use the new service function
                let coordinates = try await service.extractRouteFromActivity(activityId: activityId)
                
                guard !coordinates.isEmpty else {
                    throw WahooService.WahooError.noRouteData
                }
                
                // Update the main view model
                await MainActor.run {
                    // ✅ NEW: Clear the previous pacing plan when importing new route
                     weatherViewModel.clearAdvancedPlan()
                     
                    weatherViewModel.routePoints = coordinates
                    weatherViewModel.routeDisplayName = activityName
                    weatherViewModel.importedRouteDisplayName = activityName

                    self.isImporting = false
                    
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    onSuccess()
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
                    onFailure() // ✅ ADDED: Call failure callback
                }
            }
        }
    }
}

// NOTE: WahooActivityRow and InfoRow are intentionally omitted
// as they are correctly defined in WahooActivitiesView.swift
