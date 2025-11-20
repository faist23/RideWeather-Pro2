//
//  LaunchView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/12/25.
//

import SwiftUI

struct LaunchView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.4)]),
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            VStack {
                    Image("rider_bike_image")
 //               Image(systemName: "bicycle")
                    .resizable()
                    .renderingMode(.template) // 2. THIS allows .foregroundColor to work
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.white)
                
                Text("RideWeather Pro")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .padding(.top)
            }
        }
    }
}
