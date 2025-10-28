//
//  SavedPlansView.swift
//  RideWeather Pro
//

import SwiftUI
import Combine

struct SavedPlansView: View {
    @StateObject private var viewModel = SavedPlansViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.plans.isEmpty {
                    emptyState
                } else {
                    plansList
                }
            }
            .navigationTitle("Saved Pacing Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadPlans()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Saved Plans")
                .font(.headline)
            Text("Generate a pacing plan from a route to see it here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var plansList: some View {
        List {
            ForEach(viewModel.plans) { plan in
                SavedPlanRow(plan: plan)
            }
            .onDelete { indexSet in
                viewModel.deletePlans(at: indexSet)
            }
        }
    }
}

struct SavedPlanRow: View {
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
            
            HStack(spacing: 8) {
                Text(plan.plan.strategy.description)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                
                Text(plan.plan.difficulty.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: plan.plan.difficulty.color).opacity(0.2))
                    .cornerRadius(4)
            }
            
            Text(plan.createdDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class SavedPlansViewModel: ObservableObject {
    @Published var plans: [StoredPacingPlan] = []
    
    private let controller = AdvancedCyclingController(settings: AppSettings())
    
    func loadPlans() {
        plans = controller.loadSavedPlans()
    }
    
    func deletePlans(at offsets: IndexSet) {
        for index in offsets {
            controller.deletePlan(plans[index])
        }
        loadPlans()
    }
}
