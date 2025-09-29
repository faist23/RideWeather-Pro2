import SwiftUI

struct BackgroundDecorationView: View {
    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // Floating circles
                ForEach(0..<3, id: \.self) { index in
                    let phase = time * 0.3 + Double(index) * 0.2
                    let offsetX = sin(phase * 0.8) * 30
                    let offsetY = cos(phase * 0.6) * 40
                    
                    Circle()
                        .fill(.white.opacity(0.05))
                        .frame(width: CGFloat(80 + index * 20))
                        .offset(
                            x: [-100, 50, -50][index] + offsetX,
                            y: [-150, 100, -50][index] + offsetY
                        )
                }
                
                // Animated bike silhouette
                let bikePhase = time * 0.1
                let bikeOffsetX = sin(bikePhase) * 50
                let bikeOffsetY = cos(bikePhase * 1.2) * 30
                let bikeRotation = sin(bikePhase * 1.5) * 10
                
                Image(systemName: "bicycle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .foregroundStyle(.white.opacity(0.08))
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