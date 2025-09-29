import SwiftUI

struct RouteBottomControlsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Binding var isImporting: Bool
    @Binding var isSpeedFieldFocused: Bool
    @Binding var showBottomControls: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Status indicators
            if viewModel.isLoading {
                ModernLoadingView()
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            // Main controls card
            VStack(spacing: 24) {
                // Import and date section
                HStack(spacing: 16) {
                    ImportButton { isImporting = true }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Ride Time", systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        DatePicker(
                            "",
                            selection: $viewModel.rideDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                // Speed input section
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Average Speed", systemImage: "speedometer")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("Speed", text: $viewModel.averageSpeedInput)
                                .keyboardType(.decimalPad)
                                .focused($isSpeedFieldFocused)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)

                            Text(viewModel.settings.units.speedUnitAbbreviation)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Hide controls button
                    Button {
                        withAnimation(.smooth) {
                            showBottomControls = false
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Action button
                Button {
                    isSpeedFieldFocused = false
                    withAnimation(.smooth) {
                        showBottomControls = false
                    }
                    Task { await viewModel.calculateAndFetchWeather() }
                } label: {
                    Label("Generate Forecast", systemImage: "cloud.sun.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.routePoints.isEmpty)
                .animation(.easeInOut, value: viewModel.routePoints.isEmpty)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 16, y: 4)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
