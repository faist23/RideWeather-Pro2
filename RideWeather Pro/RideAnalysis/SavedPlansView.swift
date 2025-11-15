//
//  SavedPlansView.swift
//  RideWeather Pro
//

import SwiftUI
import Combine

struct SavedPlansView: View {
    @StateObject private var viewModel = SavedPlansViewModel()
    @Environment(\.dismiss) private var dismiss
    
    // --- MANUALLY CONTROLLED STATE ---
    @State private var isEditing = false // We will control this ourselves
    @State private var selectedPlanIDs = Set<UUID>()
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.plans.isEmpty {
                    emptyState
                } else {
                    plansList // This is the List
                }
            }
            .navigationTitle("Saved Pacing Plans")
            .navigationBarTitleDisplayMode(.inline)
            // --- UPDATED TOOLBAR ---
            .toolbar {
                // 1. Top-left "Done" button (to dismiss the sheet)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                // 2. Top-right "Select" / "Checkmark" button (to control edit mode)
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.plans.isEmpty {
                        // Our custom button to toggle edit state
                        Button {
                            withAnimation {
                                isEditing.toggle()
                            }
                        } label: {
                            if isEditing {
                                // --- THIS IS THE CHANGE ---
                                Image(systemName: "checkmark")
                                    .fontWeight(.bold)
                                // --- END CHANGE ---
                            } else {
                                Text("Select")
                            }
                        }
                    }
                }
                
                // 3. Bottom "Trash" button (visible only in edit mode)
                ToolbarItem(placement: .bottomBar) {
                    if isEditing {
                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                if !selectedPlanIDs.isEmpty {
                                    showingDeleteConfirmation = true
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(selectedPlanIDs.isEmpty)
                            Spacer()
                        }
                    }
                }
            }
            // --- END UPDATED TOOLBAR ---
            .alert("Delete \(selectedPlanIDs.count) Plan(s)?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    withAnimation {
                        viewModel.deletePlans(ids: selectedPlanIDs)
                        selectedPlanIDs.removeAll()
                        isEditing = false // <-- Exit edit mode after delete
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to permanently delete the selected plans?")
            }
        }
        .onAppear {
            viewModel.loadPlans()
        }
        // Clear selection when we manually toggle editing off
        .onChange(of: isEditing) { _, newValue in
            if newValue == false {
                selectedPlanIDs.removeAll()
            }
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
        // The List will now obey the .environment(\.editMode, ...) modifier
        List(selection: $selectedPlanIDs) {
            ForEach(viewModel.plans) { plan in
                SavedPlanRow(plan: plan)
                    .tag(plan.id)
            }
            .onDelete { indexSet in
                viewModel.deletePlans(at: indexSet)
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
    }
}

//
// NO CHANGES TO SavedPlanRow or SavedPlansViewModel
//

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
    
    // This is for swipe-to-delete
    func deletePlans(at offsets: IndexSet) {
        let plansToDelete = offsets.map { plans[$0] }
        for plan in plansToDelete {
            controller.deletePlan(plan)
        }
        loadPlans() // Refresh the list
    }
    
    // This is for multi-delete
    func deletePlans(ids: Set<UUID>) {
        let plansToDelete = plans.filter { ids.contains($0.id) }
        for plan in plansToDelete {
            controller.deletePlan(plan)
        }
        loadPlans() // Refresh the list
    }
}
