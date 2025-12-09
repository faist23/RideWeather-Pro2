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
        
        do {
            courses = try await garminService.fetchCourses()
            if courses.isEmpty {
                errorMessage = nil // Show empty state instead of error
            }
        } catch {
            errorMessage = error.localizedDescription
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
}
