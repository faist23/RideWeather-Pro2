//
//  WahooActivitiesView.swift
//  RideWeather Pro
//

import SwiftUI

struct WahooActivitiesView: View {
    @EnvironmentObject var wahooService: WahooService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = WahooActivitiesViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if viewModel.isLoading && viewModel.activities.isEmpty {
                        ProgressView("Loading activities...")
                    } else if let error = viewModel.errorMessage {
                        errorView(error: error)
                    } else if viewModel.activities.isEmpty {
                        emptyStateView
                    } else {
                        activitiesList
                    }
                }
                
                // Processing overlay
                if viewModel.isImporting {
                    ProcessingOverlay.importing(
                        "Wahoo Activity",
                        subtitle: "Analyzing power and route data"
                    )
                    .zIndex(10)
                }
            }
            .navigationTitle("Wahoo Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingAnalysisImport, onDismiss: {
                viewModel.clearSelection() // Clear detail view when sheet closes
            }) {
                WahooImportSheet(
                    viewModel: viewModel,
                    wahooService: wahooService,
                    weatherViewModel: weatherViewModel
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewAnalysisImported"))) { _ in
                dismiss()
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
            ForEach(viewModel.activities) { activity in
                Button(action: {
                    // Trigger selection/sheet via ViewModel to maintain existing logic
                    viewModel.selectedActivityDetail = activity
                    viewModel.importActivity(service: wahooService, weatherViewModel: weatherViewModel)
                }) {
                    HStack {
                        WahooActivityRow(activity: activity)
                            .environmentObject(weatherViewModel)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
            }
            
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
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Activities Found")
                .font(.headline)
            Text("Your recent Wahoo cycling rides will appear here")
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

struct WahooActivityRow: View {
    let activity: WahooWorkoutSummary
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var hasPower: Bool {
        if let powerStr = activity.workoutSummary?.powerAvg, let power = Double(powerStr) {
            return power > 0
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.workoutSummary?.name ?? activity.name ?? "Wahoo Ride")
                    .font(.headline)
                    .opacity(hasPower ? 1.0 : 0.6)
                
                Spacer()
                
                if hasPower {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 16) {
                Label(activity.movingTimeFormatted, systemImage: "clock")
                    .font(.caption)
                
                Label(
                    weatherViewModel.settings.units == .metric ?
                        String(format: "%.2f km", activity.distanceKm) :
                        String(format: "%.2f mi", activity.distanceMiles),
                    systemImage: "figure.outdoor.cycle"
                )
                .font(.caption)
                
                if hasPower, let powerStr = activity.workoutSummary?.powerAvg, let power = Double(powerStr) {
                    Label("\(Int(power))W", systemImage: "bolt")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(.secondary)
            .opacity(hasPower ? 1.0 : 0.6)
            
            if let date = activity.rideDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(hasPower ? 1.0 : 0.6)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Import Sheet
struct WahooImportSheet: View {
    @ObservedObject var viewModel: WahooActivitiesViewModel
    @ObservedObject var wahooService: WahooService
    @ObservedObject var weatherViewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isFetchingDetail || viewModel.isImporting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(viewModel.isImporting ? "Importing from Wahoo..." : "Fetching Ride Details...")
                            .font(.headline)
                        Text(viewModel.isImporting ? "Fetching activity streams and analyzing performance" : "Loading ride stats...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                
                } else if let activity = viewModel.selectedActivityDetail {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(activity.name ?? "Wahoo Ride")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            WahooInfoRow(
                                label: "Distance",
                                value: weatherViewModel.settings.units == .metric ?
                                    String(format: "%.2f km", activity.distanceKm) :
                                    String(format: "%.2f mi", activity.distanceMiles)
                            )
                            WahooInfoRow(label: "Duration", value: activity.movingTimeFormatted)
                            
                            if activity.work > 0 {
                                let work = activity.work
                                WahooInfoRow(label: "Work", value: "\(Int(work/1000)) kJ")
                            } else {
                                WahooInfoRow(label: "Work", value: "N/A")
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
                            viewModel.importActivity(service: wahooService, weatherViewModel: weatherViewModel)
                        }) {
                            HStack {
                                Image(systemName: "chart.xyaxis.line")
                                Text("Analyze This Ride")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Error Loading Details")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle("Import from Wahoo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WahooInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

