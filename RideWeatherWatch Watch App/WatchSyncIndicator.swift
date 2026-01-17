//
//  WatchSyncIndicator.swift
//  RideWeatherWatch Watch App
//
//  Reusable component to show last sync time
//

import SwiftUI

struct WatchSyncIndicator: View {
    @ObservedObject private var session = WatchSessionManager.shared
    
    var body: some View {
        if let lastUpdate = session.lastContextUpdate {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9))
                Text("Updated \(lastUpdate, style: .relative)")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary)
            .opacity(0.6)
        }
    }
}
