//
//  RouteEmptyStateView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/15/25.
//


import SwiftUI
import UniformTypeIdentifiers

struct RouteEmptyStateView: View {
    var importAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 25) {
                Text("Import Your Route")
                    .font(.title2.weight(.semibold))

                Text("Upload a GPX or FIT file to see weather forecasts along your cycling route")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button(action: importAction) {
                Label("Import Route File", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
    }
}
