//
//  EnhancedBikeRecommendationView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//


import SwiftUI

struct EnhancedBikeRecommendationView: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var animateIcon = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Smart Recommendations", systemImage: recommendation.icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: animateIcon)
                
                Spacer()
                
                Circle()
                    .fill(recommendationColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(recommendation.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text(recommendation.advice)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(nil)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(recommendationColor.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: recommendationColor.opacity(0.2), radius: 12, y: 4)
        .onAppear {
            withAnimation(.bouncy.delay(0.3)) {
                animateIcon = true
            }
        }
    }
    
    private var recommendation: (title: String, advice: String, icon: String) {
        let tempF = viewModel.settings.units == .metric ? (weather.temp * 9/5) + 32 : weather.temp
        let wind = weather.windSpeed
        let desc = weather.description.lowercased()
        
        if desc.contains("rain") || desc.contains("thunderstorm") || desc.contains("drizzle") {
            return ("Rain Gear Essential", "It's wet out there! Wear a waterproof jacket, consider fenders, and be cautious on slick surfaces. Visibility may be reduced.", "cloud.rain.fill")
        }
        
        let windThreshold = viewModel.settings.units == .metric ? 6.7 : 15
        if wind > windThreshold {
            return ("High Wind Warning", "Strong winds detected. Expect extra resistance and be mindful of crosswinds. Consider a more aerodynamic position.", "wind")
        }
        
        if tempF < 40 {
            return ("Cold Weather Ride", "Dress in layers with thermal gear, gloves, and a head cover. Pre-warm your muscles and stay hydrated with warm fluids.", "thermometer.snowflake")
        }
        
        if tempF > 85 {
            return ("Hot Weather Alert", "Hydrate well before and during your ride. Use sunscreen, wear light breathable clothing, and consider starting earlier.", "sun.max.fill")
        }
        
        return ("Perfect Cycling Conditions!", "The weather looks great for a ride. Enjoy the road and stay safe out there!", "bicycle")
    }
    
    private var recommendationColor: Color {
        let desc = weather.description.lowercased()
        let tempF = viewModel.settings.units == .metric ? (weather.temp * 9/5) + 32 : weather.temp
        let wind = weather.windSpeed
        let windThreshold = viewModel.settings.units == .metric ? 6.7 : 15
        
        if desc.contains("rain") || desc.contains("thunderstorm") {
            return .blue
        } else if wind > windThreshold {
            return .orange
        } else if tempF < 40 {
            return .cyan
        } else if tempF > 85 {
            return .red
        } else {
            return .green
        }
    }
}