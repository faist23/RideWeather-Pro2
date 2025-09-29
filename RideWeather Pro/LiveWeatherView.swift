import SwiftUI

struct LiveWeatherView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isShowingSettings = false

    var backgroundGradient: LinearGradient {
        let hour = Calendar.current.component(.hour, from: viewModel.rideDate)
        let isDayTime = hour >= 6 && hour < 19

        if isDayTime {
            return LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.4)]), startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(gradient: Gradient(colors: [Color.black, Color.indigo.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                Image(systemName: "bicycle")
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundColor(.white.opacity(0.1))
                    .rotationEffect(.degrees(-30))
                    .offset(x: -100, y: 100)
                    .ignoresSafeArea()

                ScrollView {
                    if viewModel.isLoading && viewModel.displayWeather == nil {
                        ShimmerView().shimmer()
                    } else if let weatherData = viewModel.displayWeather {
                        VStack(spacing: 20) {
                            headerView(location: viewModel.locationName)
                            CurrentWeatherView(weather: weatherData)
                            HourlyForecastView(hourlyData: viewModel.hourlyForecast)
                            SmartBikeRecommendationView(weather: weatherData)
                        }
                        .padding([.top, .horizontal])
                    } else if let errorMessage = viewModel.errorMessage {
                        errorView(message: errorMessage)
                    }
                }
                .refreshable {
                    await viewModel.refreshWeather()
                }
            }
            .navigationTitle("Cycling Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isShowingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(currentRideDate: viewModel.rideDate)
            }
        }
    }
    
    private func headerView(location: String) -> some View {
        VStack {
            Text(location).font(.largeTitle).fontWeight(.bold)
            Text("\(viewModel.rideDate, style: .date) at \(viewModel.rideDate, style: .time)")
        }.foregroundColor(.white).shadow(radius: 2)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 50)).foregroundColor(.yellow)
            Text(message).font(.headline).multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.refreshWeather() }
            }.buttonStyle(.borderedProminent)
        }.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// All subviews are now correctly defined and will compile.
struct CurrentWeatherView: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 15) {
                Image(systemName: weather.iconName).font(.system(size: 60)).foregroundColor(.yellow)
                VStack(alignment: .leading) {
                    Text("\(weather.temp, format: .number.precision(.fractionLength(0)))\(viewModel.settings.units.tempSymbol)")
                    Text(weather.description).font(.headline)
                }
                .font(.system(size: 50, weight: .bold)).minimumScaleFactor(0.5)
            }
            HStack(spacing: 20) {
                factView(label: "Feels Like", value: "\(String(format: "%.0f", weather.feelsLike))°")
                VStack {
                    Text("Wind")
                    HStack {
                        Image(systemName: "arrow.up").rotationEffect(.degrees(Double(weather.windDeg) + 180))
                        Text("\(String(format: "%.0f", weather.windSpeed)) \(viewModel.settings.units.speedSymbol)").fontWeight(.semibold)
                    }
                }
                if weather.humidity > 0 { factView(label: "Humidity", value: "\(weather.humidity)%") }
            }.font(.caption)
        }
        .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).foregroundColor(.white)
    }

    private func factView(label: String, value: String) -> some View {
        VStack { Text(label); Text(value).fontWeight(.semibold) }
    }
}

struct HourlyForecastView: View {
    let hourlyData: [HourlyForecast]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("6-Hour Forecast").font(.title2).fontWeight(.bold).foregroundColor(.white).padding(.leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hourlyData) { hour in
                        VStack(spacing: 8) {
                            Text(hour.time).font(.caption).fontWeight(.bold)
                            Image(systemName: hour.iconName).font(.title2).foregroundColor(.yellow)
                            VStack {
                                Text("\(hour.temp, format: .number.precision(.fractionLength(0)))°")
                                Text("Feels \(hour.feelsLike, format: .number.precision(.fractionLength(0)))°")
                                    .font(.caption2).foregroundColor(.white.opacity(0.8))
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up").rotationEffect(.degrees(Double(hour.windDeg) + 180))
                                Text(String(format: "%.0f", hour.windSpeed))
                            }.font(.caption)
                            if hour.pop > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "cloud.rain.fill"); Text("\(Int(hour.pop * 100))%")
                                }.font(.caption).foregroundColor(.cyan)
                            }
                        }
                        .padding(.vertical, 12).padding(.horizontal, 8).frame(minWidth: 70)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }.padding(.horizontal)
            }
        }.foregroundColor(.white)
    }
}

struct SmartBikeRecommendationView: View {
    let weather: DisplayWeatherModel
    @EnvironmentObject var viewModel: WeatherViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🚴‍♂️ Smart Recommendations").font(.title2).fontWeight(.bold).foregroundColor(.white)
            VStack(alignment: .leading, spacing: 8) {
                Label(recommendation.title, systemImage: recommendation.icon).font(.headline)
                Text(recommendation.advice).font(.subheadline)
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }.foregroundColor(.white)
    }

    private var recommendation: (title: String, advice: String, icon: String) {
        let tempInFahrenheit = viewModel.settings.units == .metric ? (weather.temp * 9/5) + 32 : weather.temp
        let wind = weather.windSpeed
        let description = weather.description.lowercased()
        if description.contains("rain") || description.contains("thunderstorm") || description.contains("drizzle") {
            return ("Rain Gear Essential", "It's wet! Wear a waterproof jacket, consider fenders, and be cautious on slick surfaces.", "cloud.rain.fill")
        }
        let windThreshold = viewModel.settings.units == .metric ? 6.7 : 15
        if wind > windThreshold {
            return ("High Wind Warning", "Strong winds detected. Expect extra resistance and be mindful of crosswinds.", "wind")
        }
        if tempInFahrenheit < 40 {
             return ("Cold Weather Ride", "Dress in layers. Thermal gear, gloves, and a head cover are highly recommended.", "thermometer.snowflake")
        }
        if tempInFahrenheit > 85 {
            return ("Hot Weather Alert", "Hydrate well, use sunscreen, and wear light, breathable clothing.", "sun.max.fill")
        }
        return ("Perfect Cycling Conditions!", "The weather looks great for a ride. Enjoy the road!", "bicycle")
    }
}
