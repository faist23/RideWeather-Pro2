//
//  AnalysisStorageManager+Comparisons.swift
//  RideWeather Pro
//
//  Add this extension to your AnalysisStorageManager class
//

import SwiftUI
import Foundation

extension AnalysisStorageManager {

    // Shared across all instances so the one-time UserDefaults migration
    // runs once per launch
    private static let comparisonStorage = JSONFileStorage<PacingPlanComparison>(
        fileName: "savedPacingComparisons.json",
        legacyUserDefaultsKey: "savedPacingComparisons",
        label: "Pacing Comparisons"
    )

    func saveComparison(_ comparison: PacingPlanComparison) {
        var comparisons = loadAllComparisons()
        comparisons.append(comparison)

        // Keep only the 30 most recent comparisons (sort oldest-first so
        // suffix keeps the newest — loadAllComparisons returns newest-first)
        if comparisons.count > 30 {
            comparisons = Array(comparisons.sorted { $0.date < $1.date }.suffix(30))
        }

        Self.comparisonStorage.save(comparisons)
    }

    func loadAllComparisons() -> [PacingPlanComparison] {
        return Self.comparisonStorage.load().sorted { $0.date > $1.date }
    }

    func deleteComparison(_ comparison: PacingPlanComparison) {
        var comparisons = loadAllComparisons()
        comparisons.removeAll { $0.id == comparison.id }

        Self.comparisonStorage.save(comparisons)
    }
}
