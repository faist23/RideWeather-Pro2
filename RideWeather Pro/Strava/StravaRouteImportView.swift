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
                        print("🔴 onDismiss called - closing main sheet")
                        dismiss()
                    })
                    .tag(ImportTab.routes)
                    
                    StravaActivitiesTab(onDismiss: {
                        print("🔴 onDismiss called - closing main sheet")
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
                        print("🔴 Cancel tapped - closing main sheet")
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
    
    var body: some View {
        NavigationStack {  // ✅ Wrap in NavigationStack
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
                // ✅ Use NavigationLink instead of onTapGesture
                NavigationLink {
                    StravaRouteDetailView(
                        route: route,
                        viewModel: viewModel,
                        stravaService: stravaService,
                        weatherViewModel: weatherViewModel,
                        onDismiss: onDismiss
                    )
                } label: {
                    StravaRouteRow(route: route)
                        .environmentObject(weatherViewModel)
                }
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
    
    var body: some View {
        NavigationStack {  // ✅ Wrap in NavigationStack
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
        }
        .onAppear {
            if viewModel.activities.isEmpty {
                viewModel.loadActivities(service: stravaService)
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
                    StravaActivityDetailView(
                        activity: activity,
                        viewModel: viewModel,
                        stravaService: stravaService,
                        weatherViewModel: weatherViewModel,
                        onDismiss: onDismiss
                    )
                } label: {
                    StravaActivityRow(activity: activity)
                        .environmentObject(weatherViewModel)
                }
            }
            
            // Load More section
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
                    String(format: "%.1f km", route.distanceKm) :
                        String(format: "%.1f mi", route.distanceMiles),
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
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            
            HStack(spacing: 16) {
                Label(activity.durationFormatted, systemImage: "clock")
                    .font(.caption)
                
                Label(
                    weatherViewModel.settings.units == .metric ?
                    String(format: "%.1f km", activity.distanceKm) :
                        String(format: "%.1f mi", activity.distanceMiles),
                    systemImage: "figure.outdoor.cycle"
                )
                .font(.caption)
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

// MARK: - Route Detail View (replaces the sheet)

struct StravaRouteDetailView: View {
    let route: StravaRoute
    @ObservedObject var viewModel: StravaRoutesViewModel
    @ObservedObject var stravaService: StravaService
    @ObservedObject var weatherViewModel: WeatherViewModel
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            if viewModel.isImporting {
                importingView
            } else {
                routeInfoView
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
            Text("Importing route from Strava...")
                .font(.headline)
            Text("Loading GPS data for weather analysis")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var routeInfoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(route.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let description = route.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    label: "Type",
                    value: route.routeType
                )
                
                InfoRow(
                    label: "Distance",
                    value: weatherViewModel.settings.units == .metric ?
                        String(format: "%.1f km", route.distanceKm) :
                        String(format: "%.1f mi", route.distanceMiles)
                )
                
                if route.elevation_gain > 0 {
                    let elevation = weatherViewModel.settings.units == .metric ?
                        route.elevation_gain :
                        route.elevation_gain * 3.28084
                    let unit = weatherViewModel.settings.units == .metric ? "m" : "ft"
                    
                    InfoRow(
                        label: "Elevation Gain",
                        value: "\(Int(elevation)) \(unit)"
                    )
                }
                
                InfoRow(
                    label: "Created",
                    value: route.createdDate.formatted(date: .abbreviated, time: .omitted)
                )
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
                viewModel.importRoute(
                    routeId: route.id,
                    routeName: route.name,
                    service: stravaService,
                    weatherViewModel: weatherViewModel,
                    onSuccess: {
                        dismiss()  // Pop the detail view
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
            
            Text("This will load the route and analyze weather conditions")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

/*// MARK: - Route Preview Sheet

struct StravaRoutePreviewSheet: View {
    let route: StravaRoute
    @ObservedObject var viewModel: StravaRoutesViewModel
    @ObservedObject var stravaService: StravaService
    @ObservedObject var weatherViewModel: WeatherViewModel
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isImporting {
                    importingView
                } else if !weatherViewModel.routePoints.isEmpty && viewModel.selectedRoute?.id == route.id {
                    // ✅ Show success state
                    successView
                } else {
                    routeInfoView
                }
            }
            .navigationTitle("Import Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(viewModel.isImporting ? "Importing..." : "Cancel") {
                        viewModel.showingRoutePreview = false
                    }
                    .disabled(viewModel.isImporting)
                }
            }
        }
    }
    
    // ✅ ADD SUCCESS VIEW
    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Route Imported!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("\(weatherViewModel.routePoints.count) GPS points loaded")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Continue") {
                viewModel.showingRoutePreview = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onDismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Importing route from Strava...")
                .font(.headline)
            Text("Loading GPS data for weather analysis")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var routeInfoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(route.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let description = route.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    label: "Type",
                    value: route.routeType
                )
                
                InfoRow(
                    label: "Distance",
                    value: weatherViewModel.settings.units == .metric ?
                    String(format: "%.1f km", route.distanceKm) :
                        String(format: "%.1f mi", route.distanceMiles)
                )
                
                if route.elevation_gain > 0 {
                    let elevation = weatherViewModel.settings.units == .metric ?
                    route.elevation_gain :
                    route.elevation_gain * 3.28084
                    let unit = weatherViewModel.settings.units == .metric ? "m" : "ft"
                    
                    InfoRow(
                        label: "Elevation Gain",
                        value: "\(Int(elevation)) \(unit)"
                    )
                }
                
                InfoRow(
                    label: "Created",
                    value: route.createdDate.formatted(date: .abbreviated, time: .omitted)
                )
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
                viewModel.importRoute(
                    service: stravaService,
                    weatherViewModel: weatherViewModel,
                    onSuccess: onDismiss
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
            
            Text("This will load the route and analyze weather conditions")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

// MARK: - Activity Preview Sheet

struct StravaActivityPreviewSheet: View {
    let activity: StravaActivity
    @ObservedObject var viewModel: StravaActivitiesImportViewModel
    @ObservedObject var stravaService: StravaService
    @ObservedObject var weatherViewModel: WeatherViewModel
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isImporting {
                    importingView
                } else {
                    activityInfoView
                }
            }
            .navigationTitle("Import Activity Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        viewModel.showingActivityPreview = false
                    }
                }
            }
        }
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
            Text(activity.name)
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    label: "Distance",
                    value: weatherViewModel.settings.units == .metric ?
                    String(format: "%.1f km", activity.distanceKm) :
                        String(format: "%.1f mi", activity.distanceMiles)
                )
                
                InfoRow(label: "Duration", value: activity.durationFormatted)
                
                if activity.total_elevation_gain > 0 {
                    let elevation = weatherViewModel.settings.units == .metric ?
                    activity.total_elevation_gain :
                    activity.total_elevation_gain * 3.28084
                    let unit = weatherViewModel.settings.units == .metric ? "m" : "ft"
                    
                    InfoRow(
                        label: "Elevation Gain",
                        value: "\(Int(elevation)) \(unit)"
                    )
                }
                
                if let date = activity.startDate {
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
                viewModel.importRoute(
                    service: stravaService,
                    weatherViewModel: weatherViewModel,
                    onSuccess: onDismiss
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
            
            Text("This will import the GPS route and analyze weather conditions")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }
}*/

// MARK: - Route Detail View (replaces the sheet)

// MARK: - Activity Detail View (replaces the sheet)

struct StravaActivityDetailView: View {
    let activity: StravaActivity
    @ObservedObject var viewModel: StravaActivitiesImportViewModel
    @ObservedObject var stravaService: StravaService
    @ObservedObject var weatherViewModel: WeatherViewModel
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            if viewModel.isImporting {
                importingView
            } else {
                activityInfoView
            }
        }
        .navigationTitle("Import Activity Route")
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
            Text(activity.name)
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    label: "Distance",
                    value: weatherViewModel.settings.units == .metric ?
                        String(format: "%.1f km", activity.distanceKm) :
                        String(format: "%.1f mi", activity.distanceMiles)
                )
                
                InfoRow(label: "Duration", value: activity.durationFormatted)
                
                if activity.total_elevation_gain > 0 {
                    let elevation = weatherViewModel.settings.units == .metric ?
                        activity.total_elevation_gain :
                        activity.total_elevation_gain * 3.28084
                    let unit = weatherViewModel.settings.units == .metric ? "m" : "ft"
                    
                    InfoRow(
                        label: "Elevation Gain",
                        value: "\(Int(elevation)) \(unit)"
                    )
                }
                
                if let date = activity.startDate {
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
                viewModel.importRoute(
                    activityId: activity.id,
                    activityName: activity.name,
                    activityDate: activity.startDate,
                    service: stravaService,
                    weatherViewModel: weatherViewModel,
                    onSuccess: {
                        dismiss()  // Pop the detail view
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
            
            Text("This will import the GPS route and analyze weather conditions")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

// MARK: - Routes View Model

@MainActor
class StravaRoutesViewModel: ObservableObject {
    @Published var routes: [StravaRoute] = []
//    @Published var selectedRoute: StravaRoute?
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
//    @Published var showingRoutePreview = false
    
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
    
/*    func selectRoute(_ route: StravaRoute) {
        selectedRoute = route
        showingRoutePreview = true
    }*/
    
    // ✅ SIMPLIFY importRoute - remove route parameter since it's passed directly
    func importRoute(
        routeId: Int,
        routeName: String,
        service: StravaService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void
    ) {
        print("🔵 Starting import for route: \(routeName)")
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                print("🔵 Step 1: Extracting route \(routeId)")
                
                // Extract GPS route
                let coordinates = try await service.extractRouteFromStravaRoute(routeId: routeId)
                
                print("🔵 Step 2: Got \(coordinates.count) coordinates")
                
                guard !coordinates.isEmpty else {
                    print("❌ No GPS data in route")
                    throw ImportError.noGPSData
                }
                
                print("🔵 Step 3: Updating weather view model")
                
                // Import into weather view model
                await MainActor.run {
                    print("🔵 Step 4: Setting route points (\(coordinates.count) points)")
                    weatherViewModel.routePoints = coordinates
                    
                    print("🔵 Step 5: Setting route name to '\(routeName)'")
                    weatherViewModel.routeDisplayName = routeName
                    
                    print("🔵 Step 6: Import complete")
                    self.isImporting = false
                    
                    // Show success feedback
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    print("🔵 Step 7: Calling onSuccess callback")
                    onSuccess()
                }
                
            } catch ImportError.noGPSData {
                print("❌ Import failed: No GPS data")
                await MainActor.run {
                    self.errorMessage = "This route doesn't have GPS data"
                    self.isImporting = false
                }
            } catch let error as StravaService.StravaError {
                print("❌ Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isImporting = false
                }
            } catch {
                print("❌ Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
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
     private let perPage = 30
     
    func loadActivities(service: StravaService) {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        
        Task {
            do {
                let activities = try await service.fetchRecentActivities(page: currentPage, perPage: perPage)
                await MainActor.run {
                    // Only show activities with GPS data
                    self.activities = activities.filter { $0.start_date_local != "" }
                    self.hasMorePages = activities.count == perPage
                    self.isLoading = false
                    
                    print("📱 Loaded page \(self.currentPage): \(self.activities.count) activities")
                    if self.hasMorePages {
                        print("📱 More pages available")
                    } else {
                        print("📱 No more pages")
                    }
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
                let newActivities = try await service.fetchRecentActivities(page: currentPage, perPage: perPage)
                await MainActor.run {
                    // Filter and append new activities
                    let filteredNew = newActivities.filter { $0.start_date_local != "" }
                    let oldCount = self.activities.count
                    self.activities.append(contentsOf: filteredNew)
                    self.hasMorePages = newActivities.count == perPage
                    self.isLoadingMore = false
                    
                    print("📱 Loaded page \(self.currentPage): Added \(filteredNew.count) activities (total now: \(self.activities.count))")
                    if self.hasMorePages {
                        print("📱 More pages available")
                    } else {
                        print("📱 Reached end of activities")
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMore = false
                    self.currentPage -= 1  // Revert page on error
                    print("❌ Error loading more activities: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func importRoute(
        activityId: Int,
        activityName: String,
        activityDate: Date?,
        service: StravaService,
        weatherViewModel: WeatherViewModel,
        onSuccess: @escaping () -> Void
    ) {
        print("🔵 Starting import for activity: \(activityName)")
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                print("🔵 Step 1: Extracting route for activity \(activityId)")
                
                // Extract GPS route from activity
                let coordinates = try await service.extractRouteFromActivity(activityId: activityId)
                
                print("🔵 Step 2: Got \(coordinates.count) coordinates")
                
                guard !coordinates.isEmpty else {
                    print("❌ No GPS data in activity")
                    throw ImportError.noGPSData
                }
                
                print("🔵 Step 3: Updating weather view model")
                
                // Import into weather view model
                await MainActor.run {
                    print("🔵 Step 4: Setting route points (\(coordinates.count) points)")
                    weatherViewModel.routePoints = coordinates
                    
                    print("🔵 Step 5: Setting route name to '\(activityName)'")
                    weatherViewModel.routeDisplayName = activityName
                    
                    // Set ride date to activity date
                    if let activityDate = activityDate {
                        print("🔵 Step 6: Setting ride date to \(activityDate)")
                        weatherViewModel.rideDate = activityDate
                    }
                    
                    print("🔵 Step 7: Import complete")
                    self.isImporting = false
                    
                    // Show success feedback
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    print("🔵 Step 8: Calling onSuccess callback")
                    onSuccess()
                }
                
            } catch ImportError.noGPSData {
                print("❌ Import failed: No GPS data")
                await MainActor.run {
                    self.errorMessage = "This activity doesn't have GPS data"
                    self.isImporting = false
                }
            } catch let error as StravaService.StravaError {
                print("❌ Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isImporting = false
                }
            } catch {
                print("❌ Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to import route: \(error.localizedDescription)"
                    self.isImporting = false
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
