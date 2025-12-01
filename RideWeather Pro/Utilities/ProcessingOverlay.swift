//
//  ProcessingOverlay.swift
//  RideWeather Pro
//
//  Enhanced version with better messaging and animation
//

import SwiftUI

struct ProcessingOverlay: View {
    var message: String = "Processing..."
    var subtitle: String? = nil // Optional additional context
    var progress: Double? = nil // If nil, shows spinning indicator. If set (0.0-1.0), shows pie.
    var icon: String? = nil // Optional custom icon
    
    var body: some View {
        ZStack {
            // 1. Dimmed Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
            
            // 2. Glassmorphism Card
            VStack(spacing: 20) {
                // Progress Indicator or Icon
                ZStack {
                    if let progress = progress {
                        // Determinate Progress Ring
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 6)
                            .frame(width: 56, height: 56)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(.blue.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                            .animation(.smooth, value: progress)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    } else if let iconName = icon {
                        // Custom Icon with subtle animation
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.1))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: iconName)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.blue.gradient)
                                .symbolEffect(.pulse, options: .repeating)
                        }
                    } else {
                        // Indeterminate Spinner
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    }
                }
                
                // Message Section
                VStack(spacing: 6) {
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(30)
            .frame(maxWidth: 280)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .zIndex(100)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
    }
}

// MARK: - Convenience Static Configurations

extension ProcessingOverlay {
    /// Standard loading state
    static func loading(_ message: String = "Loading...", subtitle: String? = nil) -> ProcessingOverlay {
        ProcessingOverlay(message: message, subtitle: subtitle)
    }
    
    /// Analyzing with data icon
    static func analyzing(_ message: String = "Analyzing Route", subtitle: String? = "Processing weather and terrain data") -> ProcessingOverlay {
        ProcessingOverlay(message: message, subtitle: subtitle, icon: "chart.xyaxis.line")
    }
    
    /// Syncing with cloud icon
    static func syncing(_ service: String, subtitle: String? = nil) -> ProcessingOverlay {
        ProcessingOverlay(
            message: "Syncing to \(service)",
            subtitle: subtitle ?? "Uploading route data",
            icon: "cloud.fill"
        )
    }
    
    /// Importing with arrow icon
    static func importing(_ source: String = "Activity", subtitle: String? = nil) -> ProcessingOverlay {
        ProcessingOverlay(
            message: "Importing \(source)",
            subtitle: subtitle ?? "Fetching route and data",
            icon: "arrow.down.circle.fill"
        )
    }
    
    /// Generating with sparkles icon
    static func generating(_ item: String, subtitle: String? = nil) -> ProcessingOverlay {
        ProcessingOverlay(
            message: "Generating \(item)",
            subtitle: subtitle,
            icon: "sparkles"
        )
    }
    
    /// Exporting with share icon
    static func exporting(_ format: String, subtitle: String? = nil) -> ProcessingOverlay {
        ProcessingOverlay(
            message: "Exporting \(format)",
            subtitle: subtitle ?? "Preparing file",
            icon: "square.and.arrow.up.fill"
        )
    }
    
    /// Custom with progress
    static func withProgress(_ message: String, progress: Double, subtitle: String? = nil) -> ProcessingOverlay {
        ProcessingOverlay(message: message, subtitle: subtitle, progress: progress)
    }
}

// MARK: - Preview

#Preview("Standard Loading") {
    ZStack {
        Color.blue.ignoresSafeArea()
        ProcessingOverlay.loading("Loading Activities")
    }
}

#Preview("Analyzing") {
    ZStack {
        Color.blue.ignoresSafeArea()
        ProcessingOverlay.analyzing()
    }
}

#Preview("Syncing to Garmin") {
    ZStack {
        Color.blue.ignoresSafeArea()
        ProcessingOverlay.syncing("Garmin", subtitle: "Pushing course data")
    }
}

#Preview("Importing Wahoo") {
    ZStack {
        Color.blue.ignoresSafeArea()
        ProcessingOverlay.importing("Wahoo Activity", subtitle: "Extracting route coordinates")
    }
}

#Preview("With Progress") {
    ZStack {
        Color.blue.ignoresSafeArea()
        ProcessingOverlay.withProgress("Importing Route", progress: 0.65, subtitle: "Processing elevation data")
    }
}

#Preview("Generating FIT") {
    ZStack {
        Color.blue.ignoresSafeArea()
        ProcessingOverlay.generating("FIT File", subtitle: "Creating course with power targets")
    }
}
