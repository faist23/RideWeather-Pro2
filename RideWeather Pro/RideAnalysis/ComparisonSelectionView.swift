//
//  ComparisonSelectionView.swift
//  RideWeather Pro
//

import SwiftUI
import Combine

struct ComparisonSelectionView: View {
    let analysis: RideAnalysis
    @StateObject private var viewModel: ComparisonSelectionViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(analysis: RideAnalysis) {
        self.analysis = analysis
        self._viewModel = StateObject(wrappedValue: ComparisonSelectionViewModel(analysis: analysis))
    }
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Finding matching plans...")
                } else if viewModel.matchingPlans.isEmpty {
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
            viewModel.loadAndFilterPlans()
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
            Text("No Matching Plans Found")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Looking for plans that match:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let metadata = analysis.metadata {
                    HStack {
                        Image(systemName: "figure.outdoor.cycle")
                        Text("\(String(format: "%.1f", metadata.totalDistance)) \(metadata.distanceUnit)")
                    }
                    .font(.caption)
                    
                    HStack {
                        Image(systemName: "arrow.up.right")
                        Text("+\(Int(metadata.elevation))\(metadata.elevationUnit)")
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            
            Text("Create a pacing plan for this route first")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var plansList: some View {
        List {
            if let bestMatch = viewModel.bestMatch {
                Section {
                    PlanRow(plan: bestMatch.plan, matchScore: bestMatch.score, isBestMatch: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectPlan(bestMatch.plan, for: analysis)
                        }
                } header: {
                    Text("Best Match (\(Int(bestMatch.score * 100))% similar)")
                }
            }
            
            if !viewModel.otherMatches.isEmpty {
                Section {
                    ForEach(viewModel.otherMatches, id: \.plan.id) { match in
                        PlanRow(plan: match.plan, matchScore: match.score, isBestMatch: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectPlan(match.plan, for: analysis)
                            }
                    }
                } header: {
                    Text("Other Possible Matches")
                }
            }
        }
    }
}

struct PlanRow: View {
    let plan: StoredPacingPlan
    let matchScore: Double
    let isBestMatch: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plan.routeName)
                    .font(.headline)
                
                Spacer()
                
                if isBestMatch {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 16) {
                Label(String(format: "%.1fkm", plan.plan.totalDistance), systemImage: "figure.outdoor.cycle")
                Label(String(format: "%.0fmin", plan.plan.totalTimeMinutes), systemImage: "clock")
                Label("\(Int(plan.plan.averagePower))W", systemImage: "bolt")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Match quality indicator
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(index < matchBars ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
                Text("\(Int(matchScore * 100))% match")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(plan.createdDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var matchBars: Int {
        switch matchScore {
        case 0.9...1.0: return 5
        case 0.8..<0.9: return 4
        case 0.7..<0.8: return 3
        case 0.6..<0.7: return 2
        default: return 1
        }
    }
}

@MainActor
class ComparisonSelectionViewModel: ObservableObject {
    @Published var matchingPlans: [MatchedPlan] = []
    @Published var isLoading = false
    @Published var comparisonResult: PacingPlanComparison?
    
    let controller = AdvancedCyclingController(settings: AppSettings())
    private let analysis: RideAnalysis
    
    var bestMatch: MatchedPlan? {
        matchingPlans.first
    }
    
    var otherMatches: [MatchedPlan] {
        Array(matchingPlans.dropFirst())
    }
    
    struct MatchedPlan {
        let plan: StoredPacingPlan
        let score: Double
    }
    
    init(analysis: RideAnalysis) {
        self.analysis = analysis
    }
    
    func loadAndFilterPlans() {
        isLoading = true
        
        let allPlans = controller.loadSavedPlans()
        let matcher = SmartPlanMatcher()
        
        // Get matches with scores
        let matches = matcher.findMatchingPlans(
            for: analysis,
            from: allPlans,
            minimumScore: 0.6 // Only show plans with 60%+ match
        )
        
        matchingPlans = matches.sorted { $0.score > $1.score }
        isLoading = false
        
        print("📊 Plan Matching Results:")
        print("   Total plans: \(allPlans.count)")
        print("   Matching plans: \(matchingPlans.count)")
        if let best = bestMatch {
            print("   Best match: \(best.plan.routeName) (\(Int(best.score * 100))%)")
        }
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
