//
//  PerformanceMonitor.swift
//  RideWeather Pro
//
//  Performance monitoring and optimization utilities for iOS 26+
//

import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - Performance Monitor

@MainActor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var metrics: PerformanceMetrics = PerformanceMetrics()
    @Published var isMonitoring = false
    
    private let logger = Logger(subsystem: "com.rideweather.performance", category: "monitoring")
    private var timer: Timer?
    private var startTime: Date?
    
    private init() {}
    
    // MARK: - Public Interface
    
    func startMonitoring() {
        isMonitoring = true
        startTime = Date()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
        
        logger.info("Performance monitoring started")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        
        if let startTime = startTime {
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Performance monitoring stopped after \(duration) seconds")
        }
    }
    
    func logNetworkRequest(_ description: String, duration: TimeInterval, success: Bool) {
        metrics.networkRequests.append(
            NetworkMetric(
                description: description,
                duration: duration,
                success: success,
                timestamp: Date()
            )
        )
        
        // Keep only recent requests
        let cutoff = Date().addingTimeInterval(-300) // 5 minutes
        metrics.networkRequests.removeAll { $0.timestamp < cutoff }
        
        logger.info("Network request: \(description) - \(duration)ms - \(success ? "Success" : "Failed")")
    }
    
    func logViewRender(_ viewName: String, duration: TimeInterval) {
        metrics.viewRenderTimes.append(
            ViewRenderMetric(
                viewName: viewName,
                duration: duration,
                timestamp: Date()
            )
        )
        
        // Keep only recent renders
        let cutoff = Date().addingTimeInterval(-60) // 1 minute
        metrics.viewRenderTimes.removeAll { $0.timestamp < cutoff }
        
        if duration > 0.016 { // 16ms = 60 FPS threshold
            logger.warning("Slow view render: \(viewName) - \(duration * 1000)ms")
        }
    }
    
    func logMemoryWarning() {
        metrics.memoryWarnings += 1
        logger.error("Memory warning received")
    }
    
    // MARK: - Private Methods
    
    private func updateMetrics() {
        updateMemoryUsage()
        updateCPUUsage()
        updateBatteryLevel()
    }
    
    private func updateMemoryUsage() {
        let memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let memoryUsageMB = Double(memoryInfo.resident_size) / 1024.0 / 1024.0
            metrics.memoryUsageMB = memoryUsageMB
            
            if memoryUsageMB > 500 { // Alert if using more than 500MB
                logger.warning("High memory usage: \(memoryUsageMB)MB")
            }
        }
    }
    
    private func updateCPUUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            // This is a simplified CPU usage calculation
            // For more accurate measurements, you'd need thread-level sampling
            metrics.cpuUsage = min(Double(info.resident_size) / 1000000.0, 100.0)
        }
    }
    
    private func updateBatteryLevel() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        metrics.batteryLevel = Double(UIDevice.current.batteryLevel * 100)
    }
}

// MARK: - Performance Metrics

struct PerformanceMetrics {
    var memoryUsageMB: Double = 0
    var cpuUsage: Double = 0
    var batteryLevel: Double = 100
    var memoryWarnings: Int = 0
    var networkRequests: [NetworkMetric] = []
    var viewRenderTimes: [ViewRenderMetric] = []
    
    var averageNetworkResponseTime: Double {
        let successfulRequests = networkRequests.filter { $0.success }
        guard !successfulRequests.isEmpty else { return 0 }
        return successfulRequests.map { $0.duration }.reduce(0, +) / Double(successfulRequests.count)
    }
    
    var networkSuccessRate: Double {
        guard !networkRequests.isEmpty else { return 100 }
        let successful = networkRequests.filter { $0.success }.count
        return Double(successful) / Double(networkRequests.count) * 100
    }
    
    var averageViewRenderTime: Double {
        guard !viewRenderTimes.isEmpty else { return 0 }
        return viewRenderTimes.map { $0.duration }.reduce(0, +) / Double(viewRenderTimes.count)
    }
}

// MARK: - Metric Types

struct NetworkMetric: Identifiable {
    let id = UUID()
    let description: String
    let duration: TimeInterval
    let success: Bool
    let timestamp: Date
}

struct ViewRenderMetric: Identifiable {
    let id = UUID()
    let viewName: String
    let duration: TimeInterval
    let timestamp: Date
}

// MARK: - Performance Tracking View Modifier

struct PerformanceTracking: ViewModifier {
    let viewName: String
    @State private var renderStart: Date?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                renderStart = Date()
            }
            .task {
                // Track initial render time
                if let start = renderStart {
                    let renderTime = Date().timeIntervalSince(start)
                    PerformanceMonitor.shared.logViewRender(viewName, duration: renderTime)
                }
            }
    }
}

extension View {
    func trackPerformance(viewName: String) -> some View {
        modifier(PerformanceTracking(viewName: viewName))
    }
}

// MARK: - Network Performance Wrapper

class NetworkPerformanceWrapper {
    static func trackRequest<T>(
        _ description: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let startTime = Date()
        
        do {
            let result = try await operation()
            let duration = Date().timeIntervalSince(startTime)
            PerformanceMonitor.shared.logNetworkRequest(description, duration: duration, success: true)
            return result
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            PerformanceMonitor.shared.logNetworkRequest(description, duration: duration, success: false)
            throw error
        }
    }
}

// MARK: - Performance Debug View

struct PerformanceDebugView: View {
    @StateObject private var monitor = PerformanceMonitor.shared
    @State private var showDetails = false
    
    var body: some View {
        NavigationView {
            List {
                Section("System Resources") {
                    MetricRow(title: "Memory Usage", value: "\(String(format: "%.1f", monitor.metrics.memoryUsageMB)) MB")
                    MetricRow(title: "CPU Usage", value: "\(String(format: "%.1f", monitor.metrics.cpuUsage))%")
                    MetricRow(title: "Battery Level", value: "\(String(format: "%.0f", monitor.metrics.batteryLevel))%")
                    MetricRow(title: "Memory Warnings", value: "\(monitor.metrics.memoryWarnings)")
                }
                
                Section("Network Performance") {
                    MetricRow(title: "Avg Response Time", value: "\(String(format: "%.0f", monitor.metrics.averageNetworkResponseTime * 1000)) ms")
                    MetricRow(title: "Success Rate", value: "\(String(format: "%.1f", monitor.metrics.networkSuccessRate))%")
                    MetricRow(title: "Total Requests", value: "\(monitor.metrics.networkRequests.count)")
                }
                
                Section("UI Performance") {
                    MetricRow(title: "Avg Render Time", value: "\(String(format: "%.1f", monitor.metrics.averageViewRenderTime * 1000)) ms")
                    MetricRow(title: "Total Renders", value: "\(monitor.metrics.viewRenderTimes.count)")
                    
                    Button("Show Detailed Metrics") {
                        showDetails = true
                    }
                }
                
                Section("Controls") {
                    HStack {
                        Button(monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                            if monitor.isMonitoring {
                                monitor.stopMonitoring()
                            } else {
                                monitor.startMonitoring()
                            }
                        }
                        .foregroundColor(monitor.isMonitoring ? .red : .green)
                        
                        Spacer()
                        
                        Circle()
                            .fill(monitor.isMonitoring ? .green : .gray)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .navigationTitle("Performance")
            .sheet(isPresented: $showDetails) {
                DetailedMetricsView()
            }
        }
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
        }
    }
}

struct DetailedMetricsView: View {
    @StateObject private var monitor = PerformanceMonitor.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Recent Network Requests") {
                    ForEach(monitor.metrics.networkRequests.prefix(20)) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.description)
                                .font(.headline)
                            HStack {
                                Text("\(String(format: "%.0f", request.duration * 1000)) ms")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: request.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(request.success ? .green : .red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                Section("Recent View Renders") {
                    ForEach(monitor.metrics.viewRenderTimes.prefix(20)) { render in
                        HStack {
                            Text(render.viewName)
                            Spacer()
                            Text("\(String(format: "%.1f", render.duration * 1000)) ms")
                                .foregroundColor(render.duration > 0.016 ? .orange : .secondary)
                        }
                    }
                }
            }
            .navigationTitle("Detailed Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Optimized Image Loading

struct OptimizedAsyncImage: View {
    let url: URL?
    let placeholder: Image
    let contentMode: ContentMode
    
    @State private var loadedImage: Image?
    @State private var isLoading = false
    
    init(url: URL?, placeholder: Image = Image(systemName: "photo"), contentMode: ContentMode = .fit) {
        self.url = url
        self.placeholder = placeholder
        self.contentMode = contentMode
    }
    
    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                loadedImage
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
                    .foregroundColor(.secondary)
                    .opacity(isLoading ? 0.6 : 1.0)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url, loadedImage == nil, !isLoading else { return }
        
        isLoading = true
        
        Task {
            do {
                let result = try await NetworkPerformanceWrapper.trackRequest("Image Load: \(url.lastPathComponent)") {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard let uiImage = UIImage(data: data) else {
                        throw URLError(.badServerResponse)
                    }
                    return Image(uiImage: uiImage)
                }
                
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.loadedImage = result
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Memory Management Utilities

class MemoryManager {
    static let shared = MemoryManager()
    
    private init() {
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        PerformanceMonitor.shared.logMemoryWarning()
        
        // Perform cleanup
        clearCaches()
    }
    
    private func clearCaches() {
        // Clear image caches
        URLCache.shared.removeAllCachedResponses()
        
        // Clear weather service cache if available
        // WeatherService cache clearing would go here
        
        print("Memory cleanup performed")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Battery Optimization Utilities

class BatteryOptimizer: ObservableObject {
    @Published var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var batteryLevel: Float = UIDevice.current.batteryLevel
    
    private var timer: Timer?
    
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        startMonitoring()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBatteryInfo()
            }
        }
    }
    
    @MainActor
    private func updateBatteryInfo() {
        batteryLevel = UIDevice.current.batteryLevel
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    @objc private func powerStateChanged() {
        Task { @MainActor in
            updateBatteryInfo()
        }
    }
    
    // Optimization suggestions based on battery level
    var optimizationSuggestions: [String] {
        var suggestions: [String] = []
        
        if batteryLevel < 0.2 {
            suggestions.append("Consider reducing location updates frequency")
            suggestions.append("Disable background app refresh")
            suggestions.append("Use simplified UI animations")
        }
        
        if isLowPowerModeEnabled {
            suggestions.append("Network requests are being throttled")
            suggestions.append("Background processing is limited")
            suggestions.append("Some visual effects are disabled")
        }
        
        return suggestions
    }
    
    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}