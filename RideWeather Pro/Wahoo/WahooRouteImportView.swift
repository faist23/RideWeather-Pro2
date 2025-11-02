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
            // Activity count header
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
                NavigationLink {
                    WahooActivityDetailView(
                        activity: activity,
                        viewModel: viewModel,
                        wahooService: wahooService,
                        weatherViewModel: weatherViewModel,
                        onDismiss: onDismiss
                    )
                } label: {
                    // Re-using the row from WahooActivitiesView.swift
                    WahooActivityRow(activity: activity)
                        .environmentObject(weatherViewModel)
                }
            }
            
            // Load More section
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

// MARK: - Activity Detail/Confirmation View

struct WahooActivityDetailView: View {
    let activity: WahooWorkoutSummary
    @ObservedObject var viewModel: WahooActivitiesImportViewModel
    @ObservedObject var wahooService: WahooService
    @ObservedObject var weatherViewModel: WeatherViewModel
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss // For popping this detail view
    
    var body: some View {
        VStack(spacing: 24) {
            if viewModel.isImporting {
                importingView
            } else {
                activityInfoView
            }
        }
        .navigationTitle("Import Route")
        .navigationBarTitleDisplayMode(.inline)
        .padding()
    }
    
    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Importing route from activity...")
                .font(.headline)
            Text("Extracting GPS data for weather analysis")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var activityInfoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activity.displayName)
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    label: "Distance",
                    value: weatherViewModel.settings.units == .metric ?
                        String(format: "%.1f km", activity.distanceKm) :
                        String(format: "%.1f mi", activity.distanceMiles)
                )
                
                InfoRow(label: "Duration", value: activity.movingTimeFormatted)
                
                if let date = activity.rideDate {
                    InfoRow(
                        label: "Date",
                        value: date.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
            
            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
            
            Button(action: {
                viewModel.importRouteFromActivity(
                    activityId: activity.id,
                    activityName: activity.displayName,
                    activityDate: activity.rideDate,
                    service: wahooService,
                    weatherViewModel: weatherViewModel,
                    onSuccess: {
                        dismiss()  // Pop this detail view
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()  // Dismiss the main sheet
                        }
                    }
                )
            }) {
                HStack {
                    Image(systemName: "cloud.sun")
                    Text("Analyze Weather on This Route")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(viewModel.isImporting)
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
                let allActivities = try await service.fetchRecentWorkouts()
                await MainActor.run {
                    self.activities = allActivities
                    self.hasMorePages = allActivities.count == perPage
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

    func loadMoreActivities(service: WahooService) {
        // This logic would need to be built into your WahooService
        // For now, we just load the first page
        print("Load more Wahoo activities logic needed in WahooService")
        self.hasMorePages = false // Assume no more pages for now
    }

    func importRouteFromActivity(
        activityId: Int,
        activityName: String,
        activityDate: Date?,
        service: WahooService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void
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
                    weatherViewModel.routePoints = coordinates
                    weatherViewModel.routeDisplayName = activityName
                    // Do NOT set the rideDate, as the user wants to forecast
                    
                    self.isImporting = false
                    
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    onSuccess()
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }
}

