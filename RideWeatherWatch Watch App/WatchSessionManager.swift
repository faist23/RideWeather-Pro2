//
//  WatchSessionManager.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 1/10/26.
//


import Foundation
import WatchConnectivity
import SwiftUI
import Combine

@MainActor
class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    
    @Published var loadSummary: TrainingLoadSummary?
    @Published var wellnessSummary: WellnessSummary?
    
    override private init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            processContext(applicationContext)
        }
    }
    
    private func processContext(_ context: [String: Any]) {
        if let loadData = context["trainingLoad"] as? Data,
           let decoded = try? JSONDecoder().decode(TrainingLoadSummary.self, from: loadData) {
            self.loadSummary = decoded
        }
        
        if let wellnessData = context["wellness"] as? Data,
           let decoded = try? JSONDecoder().decode(WellnessSummary.self, from: wellnessData) {
            self.wellnessSummary = decoded
        }
    }
}
