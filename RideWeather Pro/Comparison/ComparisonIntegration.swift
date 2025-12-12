//
//  ComparisonIntegration.swift
//  RideWeather Pro 
//
//

import SwiftUI
import Combine
import Charts

// Add Comparison Card to Analysis Results

struct ComparisonPromptCard: View {
    let analysis: RideAnalysis
    let onCompare: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compare to Pacing Plan")
                        .font(.headline)
                    Text("See where you could improve time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button(action: onCompare) {
                Text("Compare Now")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}


// MARK: - 5. Updated ComparisonSelectionViewModel

@MainActor
class ComparisonSelectionViewModelComplete: ObservableObject {
    @Published var availablePlans: [StoredPacingPlan] = []
    @Published var isLoading = false
    @Published var comparisonResult: PacingPlanComparison?
    
    private let controller: AdvancedCyclingController
    
    init(controller: AdvancedCyclingController) {
        self.controller = controller
    }
    
    func loadAvailablePlans() {
        isLoading = true
        
        Task {
            let plans = controller.loadSavedPlans()
            
            await MainActor.run {
                self.availablePlans = plans
                self.isLoading = false
            }
        }
    }
    
    func selectPlan(_ storedPlan: StoredPacingPlan, for analysis: RideAnalysis, ftp: Double) {
        let engine = PacingPlanComparisonEngine()
        
        let comparison = engine.comparePlanToActual(
            pacingPlan: storedPlan.plan,
            actualRide: analysis,
            ftp: ftp
        )
        
        // Save comparison
        let storage = AnalysisStorageManager()
        storage.saveComparison(comparison)
        
        comparisonResult = comparison
    }
}

// Comparison History View

struct ComparisonHistoryView: View {
    @StateObject private var viewModel = ComparisonHistoryViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.comparisons.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Comparisons Yet")
                            .font(.headline)
                        Text("Compare your rides to pacing plans to see them here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(viewModel.comparisons) { comparison in
                            ComparisonHistoryRow(comparison: comparison)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedComparison = comparison
                                }
                        }
                        .onDelete { indexSet in
                            viewModel.deleteComparisons(at: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("Comparison History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $viewModel.selectedComparison) { comparison in
                PacingComparisonView(comparison: comparison)
            }
        }
        .onAppear {
            viewModel.loadComparisons()
        }
    }
}

struct ComparisonHistoryRow: View {
    let comparison: PacingPlanComparison
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comparison.routeName)
                    .font(.headline)
                
                Spacer()
                
                // Grade badge
                Text(comparison.performanceGrade.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: comparison.performanceGrade.color))
                    .cornerRadius(6)
            }
            
            HStack(spacing: 12) {
                Label(formatDuration(comparison.actualTime), systemImage: "clock")
                    .font(.caption)
                
                if comparison.timeDifference != 0 {
                    Label(
                        formatDuration(abs(comparison.timeDifference)),
                        systemImage: comparison.timeDifference > 0 ? "arrow.up" : "arrow.down"
                    )
                    .font(.caption)
                    .foregroundColor(comparison.timeDifference > 0 ? .red : .green)
                }
                
                Label("\(Int(comparison.powerEfficiency))%", systemImage: "bolt")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            
            if comparison.totalPotentialTimeSavings > 5 {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                    Text("↑ \(formatDuration(comparison.totalPotentialTimeSavings)) potential")
                        .font(.caption2)
                }
                .foregroundColor(.orange)
            }
            
            Text(comparison.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}

@MainActor
class ComparisonHistoryViewModel: ObservableObject {
    @Published var comparisons: [PacingPlanComparison] = []
    @Published var selectedComparison: PacingPlanComparison?
    
    private let storage = AnalysisStorageManager()
    
    func loadComparisons() {
        comparisons = storage.loadAllComparisons()
    }
    
    func deleteComparisons(at offsets: IndexSet) {
        for index in offsets {
            storage.deleteComparison(comparisons[index])
        }
        loadComparisons()
    }
}

// MARK: - 8. Quick Comparison from Ride History

extension RideHistoryView {
    
    // Add this to your existing RideHistoryView
    func addComparisonButton() {
        /*
        For each ride in history, add a context menu or button:
        
        .contextMenu {
            Button(action: {
                // Show comparison selection for this analysis
            }) {
                Label("Compare to Plan", systemImage: "chart.bar.xaxis")
            }
        }
        */
    }
}

// MARK: - 9. Automatic Matching (Smart Feature)

class SmartComparisonMatcher {
    
    /// Automatically find the best matching plan for a ride
    func findBestMatch(
        for analysis: RideAnalysis,
        from plans: [StoredPacingPlan]
    ) -> StoredPacingPlan? {
        
        let matcher = SmartPlanMatcher()
        return matcher.findBestMatch(for: analysis, from: plans)
    }
}


// MARK: - 10. Notification Integration

extension ComparisonSelectionViewModel {
    
    // Auto-suggest comparison after ride import
    func checkForAutoComparison(analysis: RideAnalysis) {
        let plans = controller.loadSavedPlans()
        let matcher = SmartComparisonMatcher()
        
        if let matchedPlan = matcher.findBestMatch(for: analysis, from: plans) {
            // Show notification/banner
            showComparisonSuggestion(plan: matchedPlan, analysis: analysis)
        }
    }
    
    private func showComparisonSuggestion(plan: StoredPacingPlan, analysis: RideAnalysis) {
        // Post notification or show banner
        NotificationCenter.default.post(
            name: NSNotification.Name("SuggestPlanComparison"),
            object: ["plan": plan, "analysis": analysis]
        )
    }
}

// MARK: - 11. Widget/Summary Card

struct QuickComparisonSummaryCard: View {
    let comparison: PacingPlanComparison
    
    var body: some View {
        HStack(spacing: 16) {
            // Grade
            ZStack {
                Circle()
                    .fill(Color(hex: comparison.performanceGrade.color))
                    .frame(width: 60, height: 60)
                
                Text(comparison.performanceGrade.rawValue)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("vs Plan")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if comparison.timeDifference < 0 {
                    Text("↓ \(formatDuration(abs(comparison.timeDifference)))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                } else if comparison.timeDifference > 0 {
                    Text("↑ \(formatDuration(comparison.timeDifference))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                } else {
                    Text("Perfect!")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            if comparison.totalPotentialTimeSavings > 5 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Potential")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("↑ \(formatDuration(comparison.totalPotentialTimeSavings))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return minutes > 0 ? "\(minutes)m \(secs)s" : "\(secs)s"
    }
}

// MARK: - 12. Analytics & Trends

struct ComparisonTrendsView: View {
    let comparisons: [PacingPlanComparison]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Trends")
                .font(.headline)
            
            // Simple stats instead of chart
            HStack(spacing: 20) {
                StatBox(
                    label: "Avg Grade",
                    value: averageGrade,
                    color: .blue
                )
                
                StatBox(
                    label: "Best",
                    value: bestGrade,
                    color: .green
                )
                
                StatBox(
                    label: "Improvement",
                    value: improvementTrend,
                    color: .orange
                )
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private var averageGrade: String {
        guard !comparisons.isEmpty else { return "N/A" }
        let grades = comparisons.map { gradeToNumber($0.performanceGrade) }
        let avg = grades.reduce(0, +) / Double(grades.count)
        return String(format: "%.1f", avg)
    }
    
    private var bestGrade: String {
        comparisons.first?.performanceGrade.rawValue ?? "N/A"
    }
    
    private var improvementTrend: String {
        guard comparisons.count >= 2 else { return "N/A" }
        let recent = gradeToNumber(comparisons[0].performanceGrade)
        let old = gradeToNumber(comparisons[comparisons.count - 1].performanceGrade)
        let diff = recent - old
        return diff > 0 ? "↑ \(String(format: "%.1f", diff))" : "→"
    }
    
    private func gradeToNumber(_ grade: PacingPlanComparison.PerformanceGrade) -> Double {
        switch grade {
        case .aPlusPlus: return 12.0
        case .aPlus: return 11.0
        case .a: return 10.0
        case .aMinus: return 9.0
        case .bPlus: return 8.0
        case .b: return 7.0
        case .bMinus: return 6.0
        case .cPlus: return 5.0
        case .c: return 4.0
        case .cMinus: return 3.0
        case .d: return 2.0
        case .f: return 1.0
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

private var cardBackground: some View {
    Color(.systemBackground)
}
