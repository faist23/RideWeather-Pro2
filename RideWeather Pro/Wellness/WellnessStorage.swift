//
//  WellnessStorage.swift
//  RideWeather Pro
//
//  File-based storage for wellness data with automatic migration
//

import Foundation

class WellnessStorage {
    static let shared = WellnessStorage()
    
    private let fileManager = FileManager.default
    private let storageFileName = "wellnessData.json"
    private let migrationKey = "wellnessMigrated_v1"
    private let legacyMetricsKey = "wellnessMetrics"
    private let legacySyncDateKey = "wellnessLastSync"
    
    var fileURL: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent(storageFileName)
    }
    
    private init() {
        migrateFromUserDefaultsIfNeeded()
    }
    
    // MARK: - Public Methods
    
    func loadMetrics() -> [DailyWellnessMetrics] {
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                print("📁 Wellness: No file found, returning empty array")
                return []
            }
            
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metrics = try decoder.decode([DailyWellnessMetrics].self, from: data)
            print("📁 Wellness: Loaded \(metrics.count) days from file")
            return metrics
        } catch {
            print("❌ Wellness: Failed to load from file: \(error.localizedDescription)")
            return []
        }
    }
    
    func saveMetrics(_ metrics: [DailyWellnessMetrics]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(metrics)
            try data.write(to: fileURL, options: .atomic)
            
            print("📁 Wellness: Saved \(metrics.count) days to file")
        } catch {
            print("❌ Wellness: Failed to save to file: \(error.localizedDescription)")
        }
    }
    
    func clearAll() {
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                print("🗑️ Wellness: File deleted")
            }
        } catch {
            print("❌ Wellness: Failed to delete file: \(error.localizedDescription)")
        }
    }
    
    func getStorageSize() -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    func getStorageSizeFormatted() -> String {
        let bytes = getStorageSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Sync Date Management
    
    func loadSyncDate() -> Date? {
        // Keep sync date in UserDefaults since it's a single value
        return UserDefaults.standard.object(forKey: legacySyncDateKey) as? Date
    }
    
    func saveSyncDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: legacySyncDateKey)
    }
    
    // MARK: - Migration
    
    private func migrateFromUserDefaultsIfNeeded() {
        let userDefaults = UserDefaults.standard
        
        guard !userDefaults.bool(forKey: migrationKey) else {
            print("📁 Wellness: Migration already completed")
            return
        }
        
        print("🔄 Wellness: Starting migration from UserDefaults...")
        
        guard let legacyData = userDefaults.data(forKey: legacyMetricsKey),
              let legacyMetrics = try? JSONDecoder().decode([DailyWellnessMetrics].self, from: legacyData) else {
            print("📁 Wellness: No legacy data found in UserDefaults")
            userDefaults.set(true, forKey: migrationKey)
            userDefaults.synchronize()
            return
        }
        
        print("📁 Wellness: Found \(legacyMetrics.count) days in UserDefaults")
        
        saveMetrics(legacyMetrics)
        
        let verifyMetrics = loadMetrics()
        guard verifyMetrics.count == legacyMetrics.count else {
            print("❌ Wellness: Migration verification failed!")
            return
        }
        
        userDefaults.set(true, forKey: migrationKey)
        userDefaults.synchronize()
        
        print("✅ Wellness: Migration complete! \(legacyMetrics.count) days moved to file storage")
        print("📁 Wellness: File size: \(getStorageSizeFormatted())")
        
        userDefaults.removeObject(forKey: legacyMetricsKey)
        userDefaults.synchronize()
        
        print("🧹 Wellness: Cleaned up UserDefaults")
    }
}
