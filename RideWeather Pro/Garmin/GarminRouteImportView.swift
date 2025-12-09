import SwiftUI
import CoreLocation

struct GarminRouteImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var garminService: GarminService
    
    // Callbacks to pass data back to parent
    var onImport: ([EnhancedRoutePoint], String) -> Void
    
    @State private var courses: [GarminCourseSummary] = []
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var selectedCourseId: Int?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                if isLoading && courses.isEmpty {
                    ProgressView("Connecting to Garmin...")
                } else if let error = errorMsg {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Try Again") { loadCourses() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List {
                        if courses.isEmpty {
                            ContentUnavailableView(
                                "No Courses Found",
                                systemImage: "map",
                                description: Text("Create courses in Garmin Connect to see them here.")
                            )
                        } else {
                            Section("Recent Courses") {
                                ForEach(courses) { course in
                                    CourseRow(course: course, isSelected: selectedCourseId == course.courseId) {
                                        importCourse(course)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable { await loadCourses() }
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
        errorMsg = nil
        do {
            courses = try await garminService.fetchCourses()
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }
    
    private func importCourse(_ course: GarminCourseSummary) {
        selectedCourseId = course.courseId
        isLoading = true
        
        Task {
            do {
                let details = try await garminService.fetchCourseDetails(courseId: String(course.courseId))
                
                // Convert to EnhancedRoutePoint
                let routePoints = details.geoPoints.map { geo -> EnhancedRoutePoint in
                    // Note: Garmin GeoPoints might not have distance calculated between them
                    // You might need to run a pass to calculate cumulative distance
                    return EnhancedRoutePoint(
                        coordinate: CLLocationCoordinate2D(latitude: geo.latitude, longitude: geo.longitude),
                        elevation: geo.elevation,
                        distance: 0 // Will need recalculation
                    )
                }
                
                // Recalculate distances for the route points
                let processedPoints = RouteProcessor.recalculateDistances(for: routePoints)
                
                await MainActor.run {
                    onImport(processedPoints, course.courseName)
                    dismiss()
                }
            } catch {
                errorMsg = "Failed to import: \(error.localizedDescription)"
                selectedCourseId = nil
            }
            isLoading = false
        }
    }
}

// Subview for List Row
struct CourseRow: View {
    let course: GarminCourseSummary
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.courseName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 12) {
                        Label(
                            String(format: "%.1f km", course.distanceMeters / 1000.0),
                            systemImage: "ruler"
                        )
                        if let gain = course.elevationGainMeters {
                            Label(
                                String(format: "%.0f m", gain),
                                systemImage: "arrow.up.right"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(isSelected)
    }
}