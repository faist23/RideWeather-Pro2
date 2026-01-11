//
//  PhoneSessionManager.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 1/10/26.
//

import Foundation
import WatchConnectivity

class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("📱 Phone WCSession activated: \(activationState.rawValue)")
        if let error = error {
            print("📱 Activation error: \(error.localizedDescription)")
        }
        
        // CRITICAL FIX: Send data immediately when the session connects
        if activationState == .activated {
            DispatchQueue.main.async {
                self.sendUpdate()
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    
    func sessionDidDeactivate(_ session: WCSession) {
        // If the session deactivates (e.g. switching watches), reactivate it
        WCSession.default.activate()
    }
    
    // MARK: - Sending Data
    
    func sendUpdate() {
        // 1. Check Activation
        guard WCSession.default.activationState == .activated else {
            print("⚠️ Cannot send: WCSession is not activated")
            return
        }
        
        // 2. Fetch Data
        guard let loadSummary = TrainingLoadManager.shared.getCurrentSummary() else {
            print("⚠️ Cannot send: No Training Load Summary available (TSB is nil)")
            return
        }
        
        print("📱 Preparing to send TSB: \(Int(loadSummary.currentTSB))")
        
        // 3. Encode & Send
        do {
            let loadData = try JSONEncoder().encode(loadSummary)
            
            var context: [String: Any] = ["trainingLoad": loadData]
            
            // Add wellness if available
            if let wellness = WellnessManager.shared.currentSummary {
                let wellnessData = try JSONEncoder().encode(wellness)
                context["wellness"] = wellnessData
                print("📱 Adding Wellness data to payload")
            }
            
            try WCSession.default.updateApplicationContext(context)
            print("✅ Sent update to Watch (Size: \(loadData.count) bytes)")
            
        } catch {
            print("❌ Error encoding watch data: \(error)")
        }
    }
}
