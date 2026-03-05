//
//  HapticsManager.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/12/25.
//



import UIKit

class HapticsManager {
    static let shared = HapticsManager()
    
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private init() {
        notificationGenerator.prepare()
    }

    // MARK: - Existing Methods
    
    /// Triggers success haptic (route analysis complete, data loaded successfully)
    func triggerSuccess() {
        notificationGenerator.notificationOccurred(.success)
    }
    
    // MARK: - New Feedback Methods
    
    /// Triggers warning haptic (weather alerts, poor conditions detected)
    func triggerWarning() {
        notificationGenerator.notificationOccurred(.warning)
    }
    
    /// Triggers error haptic (import failed, network error)
    func triggerError() {
        notificationGenerator.notificationOccurred(.error)
    }
    
    /// Light impact for subtle interactions (segment selection, chart interactions)
    func triggerLightImpact() {
        lightImpactGenerator.prepare()
        lightImpactGenerator.impactOccurred()
    }
    
    /// Medium impact for more significant interactions (starting analysis, switching tabs)
    func triggerMediumImpact() {
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()
    }
    
    /// Selection feedback for picker-like interactions (time selection, date picker)
    func triggerSelection() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }
}
