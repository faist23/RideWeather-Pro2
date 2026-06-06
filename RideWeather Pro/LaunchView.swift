//
//  LaunchView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/12/25.
//

import SwiftUI

struct LaunchView: View {
    @ObservedObject var networkMonitor = NetworkMonitor.shared

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.4)]),
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 16) {
                Image("rider_bike_image")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.white)

                Text("RideWeather Pro")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                if networkMonitor.isConnected {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.9))
                        Text("Waiting for connection…")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
        }
    }
}
