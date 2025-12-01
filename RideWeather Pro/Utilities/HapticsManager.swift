//
//  HapticsManager.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/12/25.
//



import UIKit

class HapticsManager {
    static let shared = HapticsManager()
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    private init() {
        feedbackGenerator.prepare()
    }

    func triggerSuccess() {
        feedbackGenerator.notificationOccurred(.success)
    }
}
