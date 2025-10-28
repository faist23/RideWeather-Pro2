//
//  AnalysisStorageManager+Comparisons.swift
//  RideWeather Pro
//
//  Add this extension to your AnalysisStorageManager class
//

import SwiftUI
import Foundation

extension AnalysisStorageManager {
    
    private var comparisonStorageKey: String { "savedPacingComparisons" }
    
    func saveComparison(_ comparison: PacingPlanComparison) {
        var comparisons = loadAllComparisons()
        comparisons.append(comparison)
        
        // Keep only last 30 comparisons
        if comparisons.count > 30 {
            comparisons = Array(comparisons.suffix(30))
        }
        
        if let encoded = try? JSONEncoder().encode(comparisons) {
            UserDefaults.standard.set(encoded, forKey: comparisonStorageKey)
        }
    }
    
    func loadAllComparisons() -> [PacingPlanComparison] {
        guard let data = UserDefaults.standard.data(forKey: comparisonStorageKey),
              let comparisons = try? JSONDecoder().decode([PacingPlanComparison].self, from: data) else {
            return []
        }
        return comparisons.sorted { $0.date > $1.date }
    }
    
    func deleteComparison(_ comparison: PacingPlanComparison) {
        var comparisons = loadAllComparisons()
        comparisons.removeAll { $0.id == comparison.id }
        
        if let encoded = try? JSONEncoder().encode(comparisons) {
            UserDefaults.standard.set(encoded, forKey: comparisonStorageKey)
        }
    }
}
