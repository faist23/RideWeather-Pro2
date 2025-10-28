//
//  ComparisonSelectionView.swift
//  RideWeather Pro
//

import SwiftUI
import Combine

struct ComparisonSelectionView: View {
    let analysis: RideAnalysis
    @StateObject private var viewModel = ComparisonSelectionViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading plans...")
                } else if viewModel.availablePlans.isEmpty {
                    emptyState
                } else {
                    plansList
                }
            }
            .navigationTitle("Select Plan to Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadAvailablePlans()
        }
        .sheet(item: $viewModel.comparisonResult) { comparison in
            PacingComparisonView(comparison: comparison)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Pacing Plans Found")
                .font(.headline)
            Text("Create a pacing plan from a route first")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var plansList: some View {
        List(viewModel.availablePlans) { plan in
            PlanRow(plan: plan)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectPlan(plan, for: analysis)
                }
        }
    }
}

struct PlanRow: View {
    let plan: StoredPacingPlan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.routeName)
                .font(.headline)
            
            HStack(spacing: 16) {
                Label(String(format: "%.1fkm", plan.plan.totalDistance), systemImage: "figure.outdoor.cycle")
                Label(String(format: "%.0fmin", plan.plan.totalTimeMinutes), systemImage: "clock")
                Label("\(Int(plan.plan.averagePower))W", systemImage: "bolt")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Text(plan.createdDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class ComparisonSelectionViewModel: ObservableObject {
    @Published var availablePlans: [StoredPacingPlan] = []
    @Published var isLoading = false
    @Published var comparisonResult: PacingPlanComparison?
    
    let controller = AdvancedCyclingController(settings: AppSettings())
    
    func loadAvailablePlans() {
        isLoading = true
        availablePlans = controller.loadSavedPlans()
        isLoading = false
    }
    
    func selectPlan(_ storedPlan: StoredPacingPlan, for analysis: RideAnalysis) {
        let engine = PacingPlanComparisonEngine()
        let ftp = Double(AppSettings().functionalThresholdPower)
        
        let comparison = engine.comparePlanToActual(
            pacingPlan: storedPlan.plan,
            actualRide: analysis,
            ftp: ftp
        )
        
        let storage = AnalysisStorageManager()
        storage.saveComparison(comparison)
        
        comparisonResult = comparison
    }
}
