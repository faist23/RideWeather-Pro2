//
//  BackgroundDecorationView.swift
//  RideWeather Pro
//
//  Enhanced version with customizable colors and intensity
//

import SwiftUI

struct BackgroundDecorationView: View {
    var baseColor: Color = .white
    var intensity: Double = 0.05
    var animationSpeed: Double = 0.3
    
    var body: some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // Floating circles
                ForEach(0..<3, id: \.self) { index in
                    let phase = time * animationSpeed + Double(index) * 0.2
                    let offsetX = sin(phase * 1.0) * 30
                    let offsetY = cos(phase * 0.8) * 40
                    
                    Circle()
                        .fill(baseColor.opacity(intensity))
                        .frame(width: CGFloat(80 + index * 20))
                        .offset(
                            x: [-100, 50, -50][index] + offsetX,
                            y: [-150, 100, -50][index] + offsetY
                        )
                }
                
                // Animated bike silhouette
                let bikePhase = time * (animationSpeed * 0.8)
                let bikeOffsetX = sin(bikePhase) * 80
                let bikeOffsetY = cos(bikePhase * 1.2) * 30
                let bikeRotation = sin(bikePhase * 1.5) * 10
                
                Image("rider_bike_image")
                //               Image(systemName: "bicycle")
                    .resizable()
                    .renderingMode(.template) // 2. THIS allows .foregroundColor to work
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .foregroundStyle(baseColor.opacity(intensity * 1.6))
                    .rotationEffect(.degrees(-15 + bikeRotation))
                    .offset(
                        x: -80 + bikeOffsetX,
                        y: 150 + bikeOffsetY
                    )
                    .blur(radius: 1)
            }
        }
    }
}

// MARK: - Convenience Background Modifier

struct AnimatedBackgroundModifier: ViewModifier {
    let gradient: LinearGradient
    let showDecoration: Bool
    let decorationColor: Color
    let decorationIntensity: Double
    
    func body(content: Content) -> some View {
        ZStack {
            gradient
                .ignoresSafeArea()
            
            if showDecoration {
                BackgroundDecorationView(
                    baseColor: decorationColor,
                    intensity: decorationIntensity
                )
            }
            
            content
        }
    }
}

extension View {
    func animatedBackground(
        gradient: LinearGradient,
        showDecoration: Bool = true,
        decorationColor: Color = .white,
        decorationIntensity: Double = 0.05
    ) -> some View {
        modifier(AnimatedBackgroundModifier(
            gradient: gradient,
            showDecoration: showDecoration,
            decorationColor: decorationColor,
            decorationIntensity: decorationIntensity
        ))
    }
}

// MARK: - Standard Gradient Styles

extension LinearGradient {
    static func cyclingBackground(temperature: Double?, rideDate: Date, isDark: Bool = false) -> LinearGradient {
        let hour = Calendar.current.component(.hour, from: rideDate)
        let isDayTime = hour >= 6 && hour < 19
        let temp = temperature ?? 20
        
        if isDark {
            return LinearGradient(
                colors: [.black, .indigo.opacity(0.8), .purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        
        if isDayTime {
            if temp > 25 {
                return LinearGradient(
                    colors: [.orange.opacity(0.8), .red.opacity(0.6), .yellow.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if temp < 10 {
                return LinearGradient(
                    colors: [.blue.opacity(0.8), .cyan.opacity(0.6), .mint.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [.blue.opacity(0.7), .cyan.opacity(0.5), .green.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            return LinearGradient(
                colors: [.black, .indigo.opacity(0.8), .purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    static var analyticsBackground: LinearGradient {
        LinearGradient(
            colors: [.blue.opacity(0.8), .indigo.opacity(0.6), .purple.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var routeBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.3, blue: 0.25),  // Dark teal
                Color(red: 0.15, green: 0.35, blue: 0.4), // Dark cyan
                Color(red: 0.1, green: 0.25, blue: 0.35)  // Dark blue-green
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var analysisDashboardBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.1, blue: 0.15),   // Very dark blue
                Color(red: 0.1, green: 0.15, blue: 0.25),   // Dark blue-gray
                Color(red: 0.08, green: 0.12, blue: 0.2)    // Dark slate
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var pacingPlanBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.05, blue: 0.15),   // Dark purple
                Color(red: 0.15, green: 0.1, blue: 0.2),    // Purple-gray
                Color(red: 0.08, green: 0.08, blue: 0.15)   // Dark indigo
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var fuelingPlanBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.08, blue: 0.05),  // Dark orange
                Color(red: 0.18, green: 0.12, blue: 0.08),  // Warm brown
                Color(red: 0.12, green: 0.08, blue: 0.06)   // Dark rust
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var exportBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.12, blue: 0.1),   // Dark teal
                Color(red: 0.08, green: 0.15, blue: 0.15),  // Teal-gray
                Color(red: 0.06, green: 0.1, blue: 0.12)    // Dark cyan
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var rideAnalysisBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.15, blue: 0.08),  // Dark green
                Color(red: 0.12, green: 0.18, blue: 0.12),  // Forest green
                Color(red: 0.08, green: 0.12, blue: 0.1)    // Dark olive
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    static var settingsBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.08, blue: 0.12),  // Dark gray-blue
                Color(red: 0.12, green: 0.12, blue: 0.18),  // Medium dark
                Color(red: 0.1, green: 0.1, blue: 0.15)     // Dark slate
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

