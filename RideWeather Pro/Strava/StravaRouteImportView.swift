//
//  StravaRouteImportView.swift
//  RideWeather Pro
//

import SwiftUI
import CoreLocation
import Combine

struct StravaRouteImportView: View {
    @EnvironmentObject var stravaService: StravaService
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
                    StravaRoutesTab(onDismiss: {
                        dismiss()
                    })
                    .tag(ImportTab.routes)
                    
                    StravaActivitiesTab(onDismiss: {
                        dismiss()
                    })
                    .tag(ImportTab.activities)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Import from Strava")
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

// MARK: - Saved Routes Tab

struct StravaRoutesTab: View {
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = StravaRoutesViewModel()
    let onDismiss: () -> Void
    
    @State private var importingId: Int? = nil // ✅ ADDED: For per-row loading
    
    var body: some View {
        // ✅ REMOVED: Redundant NavigationStack
        Group {
            if viewModel.isLoading && viewModel.routes.isEmpty {
                ProgressView("Loading routes...")
            } else if let error = viewModel.errorMessage {
                errorView(error: error)
            } else if viewModel.routes.isEmpty {
                emptyRoutesView
            } else {
                routesList
            }
        }
        .onAppear {
            if viewModel.routes.isEmpty {
                viewModel.loadRoutes(service: stravaService)
            }
        }
    }
    
    private var routesList: some View {
        List {
            ForEach(viewModel.routes) { route in
                // ✅ CHANGED: Replaced NavigationLink with Button
                Button(action: {
                    importingId = route.id
                    viewModel.importRoute(
                        routeId: route.id,
                        routeName: route.name,
                        service: stravaService,
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
                        StravaRouteRow(route: route)
                            .environmentObject(weatherViewModel)
                        Spacer()
                        if importingId == route.id {
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
        }
        .refreshable {
            viewModel.loadRoutes(service: stravaService)
        }
    }
    
    private var emptyRoutesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Saved Routes")
                .font(.headline)
            Text("Create routes in the Strava app to see them here")
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
            Text("Error Loading Routes")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                viewModel.loadRoutes(service: stravaService)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Activities Tab

struct StravaActivitiesTab: View {
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = StravaActivitiesImportViewModel()
    let onDismiss: () -> Void
    
    @State private var importingId: Int? = nil // ✅ ADDED: For per-row loading
    
    var body: some View {
        // ✅ REMOVED: Redundant NavigationStack
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
                viewModel.loadActivities(service: stravaService)
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
                    viewModel.importRoute(
                        activityId: activity.id,
                        activityName: activity.name,
                        activityDate: activity.startDate,
                        service: stravaService,
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
                        StravaActivityRow(activity: activity)
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
                        viewModel.loadMoreActivities(service: stravaService)
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
            } else if !viewModel.activities.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.title3)
                                .foregroundColor(.green)
                            Text("All activities loaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .refreshable {
            viewModel.loadActivities(service: stravaService)
        }
    }
    
    private var emptyActivitiesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Activities Found")
                .font(.headline)
            Text("Your recent Strava rides will appear here")
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
                viewModel.loadActivities(service: stravaService)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Route Row

struct StravaRouteRow: View {
    let route: StravaRoute
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(route.name)
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 4) {
                    if route.starred {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    
                    Text(route.routeType)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            HStack(spacing: 16) {
                Label(
                    weatherViewModel.settings.units == .metric ?
                    String(format: "%.2f km", route.distanceKm) :
                        String(format: "%.2f mi", route.distanceMiles),
                    systemImage: "map"
                )
                .font(.caption)
                
                if route.elevation_gain > 0 {
                    let elevation = weatherViewModel.settings.units == .metric ?
                    route.elevation_gain :
                    route.elevation_gain * 3.28084
                    let unit = weatherViewModel.settings.units == .metric ? "m" : "ft"
                    
                    Label("\(Int(elevation))\(unit)", systemImage: "arrow.up.right")
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)
            
            if let description = route.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Activity Row

struct StravaActivityRow: View {
    let activity: StravaActivity
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.name)
                    .font(.headline)
                
                Spacer()
                
                // ✅ CHANGED: Show bolt icon if power data exists
                if let watts = activity.average_watts, watts > 0 {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else {
                    // Fallback to checkmark
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 16) {
                Label(activity.durationFormatted, systemImage: "clock")
                    .font(.caption)
                
                Label(
                    weatherViewModel.settings.units == .metric ?
                    String(format: "%.2f km", activity.distanceKm) :
                        String(format: "%.2f mi", activity.distanceMiles),
                    systemImage: "figure.outdoor.cycle"
                )
                .font(.caption)
                // ✅ ADDED: Show average watts if it exists
                if let watts = activity.average_watts, watts > 0 {
                    Label("\(Int(watts))W", systemImage: "bolt")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(.secondary)
            
            if let date = activity.startDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Routes View Model

@MainActor
class StravaRoutesViewModel: ObservableObject {
    @Published var routes: [StravaRoute] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    
    func loadRoutes(service: StravaService) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let routes = try await service.fetchRoutes(limit: 30)
                await MainActor.run {
                    self.routes = routes
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
    
    // ✅ UPDATED: Added onFailure callback
    func importRoute(
        routeId: Int,
        routeName: String,
        service: StravaService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void // ✅ ADDED
    ) {
        print("🔵 Starting import for route: \(routeName)")
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                print("🔵 Step 1: Extracting route \(routeId)")
                // ✅ UPDATED: Expect tuple return
                let (coordinates, totalDistance, elevationAnalysis) = try await service.extractRouteFromStravaRoute(routeId: routeId)
                print("🔵 Step 2: Got \(coordinates.count) coordinates")
                
                guard !coordinates.isEmpty else {
                    print("❌ No GPS data in route")
                    throw ImportError.noGPSData
                }
                
                print("🔵 Step 3: Updating weather view model")
                
                await MainActor.run {
                    // ✅ NEW: Clear the previous pacing plan when importing new route
                     weatherViewModel.clearAdvancedPlan()
                     
                    print("🔵 Step 4: Setting route points (\(coordinates.count) points)")
                    weatherViewModel.routePoints = coordinates

                    // ✅ ADDED: Set the authoritative distance
                    weatherViewModel.authoritativeRouteDistanceMeters = totalDistance
                    
                    // ✅ ADDED: Set elevation analysis if available
                    weatherViewModel.elevationAnalysis = elevationAnalysis
                    
                    print("🔵 Step 5: Setting route name to '\(routeName)'")
                    weatherViewModel.routeDisplayName = routeName
                    
                    // ✅ NEW: Also set the internal display name so stem notes use it
                    weatherViewModel.importedRouteDisplayName = routeName
                    
                    // If we have elevation analysis, trigger finalize to prepare for power analysis
                    if elevationAnalysis != nil {
                        weatherViewModel.finalizeRouteImport()
                    }
                    
                    print("🔵 Step 6: Import complete")
                    self.isImporting = false
                    
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    print("🔵 Step 7: Calling onSuccess callback")
                    onSuccess()
                }
                
            } catch {
                print("❌ Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
                    onFailure() // ✅ ADDED: Call failure callback
                }
            }
        }
    }
    
    enum ImportError: LocalizedError {
        case noGPSData
        
        var errorDescription: String? {
            switch self {
            case .noGPSData:
                return "This route doesn't contain GPS data"
            }
        }
    }
}

// MARK: - Activities View Model

@MainActor
class StravaActivitiesImportViewModel: ObservableObject {
    @Published var activities: [StravaActivity] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var isLoadingMore = false
    @Published var hasMorePages = true
     
     private var currentPage = 1
     private let perPage = 50
     
    func loadActivities(service: StravaService) {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        activities = []
        
        Task {
            do {
                let allActivities = try await service.fetchRecentActivities(page: currentPage, perPage: perPage)
                await MainActor.run {
                    let rides = allActivities.filter {
                        ($0.type == "Ride") &&
                        ($0.trainer == nil || $0.trainer == false) &&
                        !$0.start_date_local.isEmpty
                    }
                    
                    self.activities = rides
                    self.hasMorePages = allActivities.count == perPage
                    self.isLoading = false
                    
                    print("📱 Loaded page \(self.currentPage): \(allActivities.count) total, \(rides.count) rides")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadMoreActivities(service: StravaService) {
        guard !isLoadingMore && hasMorePages else {
            print("📱 Skipping load more: isLoadingMore=\(isLoadingMore), hasMorePages=\(hasMorePages)")
            return
        }
        
        print("📱 Loading more activities...")
        isLoadingMore = true
        errorMessage = nil
        currentPage += 1
        
        Task {
            do {
                let allActivities = try await service.fetchRecentActivities(page: currentPage, perPage: perPage)
                await MainActor.run {
                    let newRides = allActivities.filter {
                        ($0.type == "Ride") &&
                        ($0.trainer == nil || $0.trainer == false) &&
                       !$0.start_date_local.isEmpty
                    }
                    
                    self.activities.append(contentsOf: newRides)
                    self.hasMorePages = allActivities.count == perPage
                    self.isLoadingMore = false
                    
                    print("📱 Loaded page \(self.currentPage): Added \(newRides.count) rides (total: \(self.activities.count))")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMore = false
                    self.currentPage -= 1
                }
            }
        }
    }

    // ✅ UPDATED: Added onFailure callback
    func importRoute(
        activityId: Int,
        activityName: String,
        activityDate: Date?,
        service: StravaService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void // ✅ ADDED
    ) {
        print("🔵 Starting import for activity: \(activityName)")
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                print("🔵 Step 1: Extracting route for activity \(activityId)")
                // ✅ CHANGED: Capture all returned values, including elevation
                let (coordinates, totalDistance, elevationAnalysis) = try await service.extractRouteFromActivity(activityId: activityId)
                print("🔵 Step 2: Got \(coordinates.count) coordinates")
                
                guard !coordinates.isEmpty else {
                    print("❌ No GPS data in activity")
                    throw ImportError.noGPSData
                }
                
                print("🔵 Step 3: Updating weather view model")
                
                await MainActor.run {
                    // ✅ NEW: Clear the previous pacing plan when importing new route
                     weatherViewModel.clearAdvancedPlan()
                     
                    print("🔵 Step 4: Setting route points (\(coordinates.count) points)")
                    weatherViewModel.routePoints = coordinates
                    
                    // ✅ ADDED: Set the authoritative distance
                    weatherViewModel.authoritativeRouteDistanceMeters = totalDistance
                    
                    // ✅ ADDED: Set the elevation analysis
                    weatherViewModel.elevationAnalysis = elevationAnalysis
                    
                    print("🔵 Step 5: Setting route name to '\(activityName)'")
                    weatherViewModel.routeDisplayName = activityName
                    
                    // ✅ NEW: Also set the internal display name so stem notes use it
                    weatherViewModel.importedRouteDisplayName = activityName
                    
                    // If we have elevation analysis, trigger finalize to prepare for power analysis
                    if elevationAnalysis != nil {
                        weatherViewModel.finalizeRouteImport()
                    }
                    
                    print("🔵 Step 7: Import complete")
                    self.isImporting = false
                    
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    print("🔵 Step 8: Calling onSuccess callback")
                    onSuccess()
                }
                
            } catch {
                print("❌ Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
                    onFailure() // ✅ ADDED: Call failure callback
                }
            }
        }
    }
    
    enum ImportError: LocalizedError {
        case noGPSData
        
        var errorDescription: String? {
            switch self {
            case .noGPSData:
                return "This activity doesn't contain GPS data"
            }
        }
    }
}

/*
//
//  StravaRouteImportView.swift
//  RideWeather Pro
//

import SwiftUI
import CoreLocation
import Combine

struct StravaRouteImportView: View {
    @EnvironmentObject var stravaService: StravaService
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
                    StravaRoutesTab(onDismiss: {
                        dismiss()
                    })
                    .tag(ImportTab.routes)
                    
                    StravaActivitiesTab(onDismiss: {
                        dismiss()
                    })
                    .tag(ImportTab.activities)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Import from Strava")
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

// MARK: - Saved Routes Tab

struct StravaRoutesTab: View {
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = StravaRoutesViewModel()
    let onDismiss: () -> Void
    
    @State private var importingId: Int? = nil // ✅ ADDED: For per-row loading
    
    var body: some View {
        // ✅ REMOVED: Redundant NavigationStack
        Group {
            if viewModel.isLoading && viewModel.routes.isEmpty {
                ProgressView("Loading routes...")
            } else if let error = viewModel.errorMessage {
                errorView(error: error)
            } else if viewModel.routes.isEmpty {
                emptyRoutesView
            } else {
                routesList
            }
        }
        .onAppear {
            if viewModel.routes.isEmpty {
                viewModel.loadRoutes(service: stravaService)
            }
        }
    }
    
    private var routesList: some View {
        List {
            ForEach(viewModel.routes) { route in
                // ✅ CHANGED: Replaced NavigationLink with Button
                Button(action: {
                    importingId = route.id
                    viewModel.importRoute(
                        routeId: route.id,
                        routeName: route.name,
                        service: stravaService,
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
                        StravaRouteRow(route: route)
                            .environmentObject(weatherViewModel)
                        Spacer()
                        if importingId == route.id {
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
        }
        .refreshable {
            viewModel.loadRoutes(service: stravaService)
        }
    }
    
    private var emptyRoutesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Saved Routes")
                .font(.headline)
            Text("Create routes in the Strava app to see them here")
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
            Text("Error Loading Routes")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                viewModel.loadRoutes(service: stravaService)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Activities Tab

struct StravaActivitiesTab: View {
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = StravaActivitiesImportViewModel()
    let onDismiss: () -> Void
    
    @State private var importingId: Int? = nil // ✅ ADDED: For per-row loading
    
    var body: some View {
        // ✅ REMOVED: Redundant NavigationStack
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
                viewModel.loadActivities(service: stravaService)
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
                    viewModel.importRoute(
                        activityId: activity.id,
                        activityName: activity.name,
                        activityDate: activity.startDate,
                        service: stravaService,
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
                        StravaActivityRow(activity: activity)
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
                        viewModel.loadMoreActivities(service: stravaService)
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
            } else if !viewModel.activities.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.title3)
                                .foregroundColor(.green)
                            Text("All activities loaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .refreshable {
            viewModel.loadActivities(service: stravaService)
        }
    }
    
    private var emptyActivitiesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Activities Found")
                .font(.headline)
            Text("Your recent Strava rides will appear here")
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
                viewModel.loadActivities(service: stravaService)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Route Row

struct StravaRouteRow: View {
    let route: StravaRoute
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(route.name)
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 4) {
                    if route.starred {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    
                    Text(route.routeType)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            HStack(spacing: 16) {
                Label(
                    weatherViewModel.settings.units == .metric ?
                    String(format: "%.2f km", route.distanceKm) :
                        String(format: "%.2f mi", route.distanceMiles),
                    systemImage: "map"
                )
                .font(.caption)
                
                if route.elevation_gain > 0 {
                    let elevation = weatherViewModel.settings.units == .metric ?
                    route.elevation_gain :
                    route.elevation_gain * 3.28084
                    let unit = weatherViewModel.settings.units == .metric ? "m" : "ft"
                    
                    Label("\(Int(elevation))\(unit)", systemImage: "arrow.up.right")
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)
            
            if let description = route.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Activity Row

struct StravaActivityRow: View {
    let activity: StravaActivity
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.name)
                    .font(.headline)
                
                Spacer()
                
                // ✅ CHANGED: Show bolt icon if power data exists
                if let watts = activity.average_watts, watts > 0 {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else {
                    // Fallback to checkmark
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 16) {
                Label(activity.durationFormatted, systemImage: "clock")
                    .font(.caption)
                
                Label(
                    weatherViewModel.settings.units == .metric ?
                    String(format: "%.2f km", activity.distanceKm) :
                        String(format: "%.2f mi", activity.distanceMiles),
                    systemImage: "figure.outdoor.cycle"
                )
                .font(.caption)
                // ✅ ADDED: Show average watts if it exists
                if let watts = activity.average_watts, watts > 0 {
                    Label("\(Int(watts))W", systemImage: "bolt")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(.secondary)
            
            if let date = activity.startDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Routes View Model

@MainActor
class StravaRoutesViewModel: ObservableObject {
    @Published var routes: [StravaRoute] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    
    func loadRoutes(service: StravaService) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let routes = try await service.fetchRoutes(limit: 30)
                await MainActor.run {
                    self.routes = routes
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
    
    // ✅ UPDATED: Added onFailure callback
    func importRoute(
        routeId: Int,
        routeName: String,
        service: StravaService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void // ✅ ADDED
    ) {
        print("🔵 Starting import for route: \(routeName)")
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                print("🔵 Step 1: Extracting route \(routeId)")
                let (coordinates, totalDistance) = try await service.extractRouteFromStravaRoute(routeId: routeId)
                print("🔵 Step 2: Got \(coordinates.count) coordinates")
                
                guard !coordinates.isEmpty else {
                    print("❌ No GPS data in route")
                    throw ImportError.noGPSData
                }
                
                print("🔵 Step 3: Updating weather view model")
                
                await MainActor.run {
                    // ✅ NEW: Clear the previous pacing plan when importing new route
                     weatherViewModel.clearAdvancedPlan()
                     
                    print("🔵 Step 4: Setting route points (\(coordinates.count) points)")
                    weatherViewModel.routePoints = coordinates

                    // ✅ ADDED: Set the authoritative distance
                    weatherViewModel.authoritativeRouteDistanceMeters = totalDistance
                    
                    print("🔵 Step 5: Setting route name to '\(routeName)'")
                    weatherViewModel.routeDisplayName = routeName
                    
                    // ✅ NEW: Also set the internal display name so stem notes use it
                    weatherViewModel.importedRouteDisplayName = routeName
                    
                    print("🔵 Step 6: Import complete")
                    self.isImporting = false
                    
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    print("🔵 Step 7: Calling onSuccess callback")
                    onSuccess()
                }
                
            } catch {
                print("❌ Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
                    onFailure() // ✅ ADDED: Call failure callback
                }
            }
        }
    }
    
    enum ImportError: LocalizedError {
        case noGPSData
        
        var errorDescription: String? {
            switch self {
            case .noGPSData:
                return "This route doesn't contain GPS data"
            }
        }
    }
}

// MARK: - Activities View Model

@MainActor
class StravaActivitiesImportViewModel: ObservableObject {
    @Published var activities: [StravaActivity] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var isLoadingMore = false
    @Published var hasMorePages = true
     
     private var currentPage = 1
     private let perPage = 50
     
    func loadActivities(service: StravaService) {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        activities = []
        
        Task {
            do {
                let allActivities = try await service.fetchRecentActivities(page: currentPage, perPage: perPage)
                await MainActor.run {
                    let rides = allActivities.filter {
                        ($0.type == "Ride") &&
                        ($0.trainer == nil || $0.trainer == false) &&
                        !$0.start_date_local.isEmpty
                    }
                    
                    self.activities = rides
                    self.hasMorePages = allActivities.count == perPage
                    self.isLoading = false
                    
                    print("📱 Loaded page \(self.currentPage): \(allActivities.count) total, \(rides.count) rides")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadMoreActivities(service: StravaService) {
        guard !isLoadingMore && hasMorePages else {
            print("📱 Skipping load more: isLoadingMore=\(isLoadingMore), hasMorePages=\(hasMorePages)")
            return
        }
        
        print("📱 Loading more activities...")
        isLoadingMore = true
        errorMessage = nil
        currentPage += 1
        
        Task {
            do {
                let allActivities = try await service.fetchRecentActivities(page: currentPage, perPage: perPage)
                await MainActor.run {
                    let newRides = allActivities.filter {
                        ($0.type == "Ride") &&
                        ($0.trainer == nil || $0.trainer == false) &&
                       !$0.start_date_local.isEmpty
                    }
                    
                    self.activities.append(contentsOf: newRides)
                    self.hasMorePages = allActivities.count == perPage
                    self.isLoadingMore = false
                    
                    print("📱 Loaded page \(self.currentPage): Added \(newRides.count) rides (total: \(self.activities.count))")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMore = false
                    self.currentPage -= 1
                }
            }
        }
    }

    // ✅ UPDATED: Added onFailure callback
    func importRoute(
        activityId: Int,
        activityName: String,
        activityDate: Date?,
        service: StravaService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void // ✅ ADDED
    ) {
        print("🔵 Starting import for activity: \(activityName)")
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                print("🔵 Step 1: Extracting route for activity \(activityId)")
                // ✅ CHANGED: Capture both returned values
                let (coordinates, totalDistance) = try await service.extractRouteFromActivity(activityId: activityId)
                print("🔵 Step 2: Got \(coordinates.count) coordinates")
                
                guard !coordinates.isEmpty else {
                    print("❌ No GPS data in activity")
                    throw ImportError.noGPSData
                }
                
                print("🔵 Step 3: Updating weather view model")
                
                await MainActor.run {
                    // ✅ NEW: Clear the previous pacing plan when importing new route
                     weatherViewModel.clearAdvancedPlan()
                     
                    print("🔵 Step 4: Setting route points (\(coordinates.count) points)")
                    weatherViewModel.routePoints = coordinates
                    
                    // ✅ ADDED: Set the authoritative distance
                    weatherViewModel.authoritativeRouteDistanceMeters = totalDistance
                    
                    print("🔵 Step 5: Setting route name to '\(activityName)'")
                    weatherViewModel.routeDisplayName = activityName
                    
                    // ✅ NEW: Also set the internal display name so stem notes use it
                    weatherViewModel.importedRouteDisplayName = activityName
                    
                    print("🔵 Step 7: Import complete")
                    self.isImporting = false
                    
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    print("🔵 Step 8: Calling onSuccess callback")
                    onSuccess()
                }
                
            } catch {
                print("❌ Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
                    onFailure() // ✅ ADDED: Call failure callback
                }
            }
        }
    }
    
    enum ImportError: LocalizedError {
        case noGPSData
        
        var errorDescription: String? {
            switch self {
            case .noGPSData:
                return "This activity doesn't contain GPS data"
            }
        }
    }
}
*/
