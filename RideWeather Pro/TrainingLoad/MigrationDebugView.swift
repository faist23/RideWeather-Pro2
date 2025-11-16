//
//  MigrationDebugView.swift
//  RideWeather Pro
//
//  TEMPORARY: Debug view to test and verify migration
//  Add this temporarily to verify migration, then remove
//

import SwiftUI

/*struct MigrationDebugView: View {
    @State private var fileExists = false
    @State private var fileSize = "0 KB"
    @State private var daysInFile = 0
    @State private var daysInUserDefaults = 0
    @State private var migrationCompleted = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Migration Status") {
                    HStack {
                        Text("Migration Flag")
                        Spacer()
                        Image(systemName: migrationCompleted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(migrationCompleted ? .green : .red)
                    }
                }
                
                Section("File Storage") {
                    HStack {
                        Text("File Exists")
                        Spacer()
                        Image(systemName: fileExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(fileExists ? .green : .red)
                    }
                    
                    HStack {
                        Text("File Size")
                        Spacer()
                        Text(fileSize)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Days in File")
                        Spacer()
                        Text("\(daysInFile)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("UserDefaults (Legacy)") {
                    HStack {
                        Text("Days in UserDefaults")
                        Spacer()
                        Text("\(daysInUserDefaults)")
                            .foregroundColor(.secondary)
                    }
                    
                    if daysInUserDefaults > 0 {
                        Text("⚠️ Legacy data still present")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("✅ Cleaned up")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Section("Actions") {
                    Button {
                        refreshStatus()
                    } label: {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }
                    
                    Button {
                        resetMigration()
                    } label: {
                        Label("Reset Migration Flag", systemImage: "arrow.counterclockwise")
                    }
                    .foregroundColor(.orange)
                    
                    Button {
                        forceMigration()
                    } label: {
                        Label("Force Migration", systemImage: "arrow.right.circle.fill")
                    }
                    .foregroundColor(.blue)
                    
                    Button(role: .destructive) {
                        deleteFile()
                    } label: {
                        Label("Delete File", systemImage: "trash")
                    }
                }
                
                Section("Test Load") {
                    Button {
                        testLoadData()
                    } label: {
                        Label("Test Load from File", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .navigationTitle("Migration Debug")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                refreshStatus()
            }
            .alert("Test Result", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func refreshStatus() {
        let storage = TrainingLoadStorage.shared
        
        // Check file
        fileExists = FileManager.default.fileExists(atPath: storage.fileURL.path)
        fileSize = storage.getStorageSizeFormatted()
        daysInFile = storage.loadAllDailyLoads().count
        
        // Check UserDefaults
        if let data = UserDefaults.standard.data(forKey: "trainingLoadData"),
           let loads = try? JSONDecoder().decode([DailyTrainingLoad].self, from: data) {
            daysInUserDefaults = loads.count
        } else {
            daysInUserDefaults = 0
        }
        
        // Check migration flag
        migrationCompleted = UserDefaults.standard.bool(forKey: "trainingLoadMigrated_v1")
        
        print("📊 Status: File=\(fileExists), Size=\(fileSize), Days=\(daysInFile), UserDefaults=\(daysInUserDefaults), Migrated=\(migrationCompleted)")
    }
    
    private func resetMigration() {
        UserDefaults.standard.removeObject(forKey: "trainingLoadMigrated_v1")
        UserDefaults.standard.synchronize()
        refreshStatus()
        print("🔄 Migration flag reset")
    }
    
    private func forceMigration() {
        TrainingLoadStorage.shared.forceMigration()
        refreshStatus()
    }
    
    private func deleteFile() {
        TrainingLoadStorage.shared.clearAll()
        refreshStatus()
    }
    
    private func testLoadData() {
        let loads = TrainingLoadStorage.shared.loadAllDailyLoads()
        
        if loads.isEmpty {
            alertMessage = "No data found in file"
        } else {
            let sorted = loads.sorted { $0.date < $1.date }
            let first = sorted.first!.date.formatted(date: .abbreviated, time: .omitted)
            let last = sorted.last!.date.formatted(date: .abbreviated, time: .omitted)
            alertMessage = "✅ Loaded \(loads.count) days\nFrom: \(first)\nTo: \(last)"
        }
        
        showingAlert = true
    }
}

// MARK: - Helper to access fileURL for debug view
extension TrainingLoadStorage {
    func getFileURL() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("trainingLoadData.json")
    }
}*/
