//
//  TrainingLoadStorage.swift
//  RideWeather Pro
//
//  File-based storage for training load data with automatic migration
//

import Foundation

// MARK: - TrainingLoadStorage (File-based)

class TrainingLoadStorage {
    static let shared = TrainingLoadStorage()
    
    private let fileManager = FileManager.default
    private let storageFileName = "trainingLoadData.json"
    private let migrationKey = "trainingLoadMigrated_v1"
    private let legacyUserDefaultsKey = "trainingLoadData"
    
    // File URL for storing training load data (internal for debug access)
    var fileURL: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent(storageFileName)
    }
    
    private init() {
        // Perform migration on first launch
        migrateFromUserDefaultsIfNeeded()
    }
    
    // MARK: - Public Methods
    
    /// Loads all daily training load data from file storage
    func loadAllDailyLoads() -> [DailyTrainingLoad] {
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                print("📁 Training Load: No file found, returning empty array")
                return []
            }
            
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loads = try decoder.decode([DailyTrainingLoad].self, from: data)
            print("📁 Training Load: Loaded \(loads.count) days from file")
            return loads
        } catch {
            print("❌ Training Load: Failed to load from file: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Saves all daily training load data to file storage
    func saveDailyLoads(_ loads: [DailyTrainingLoad]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // Remove prettyPrinted for more compact storage
            
            let data = try encoder.encode(loads)
            try data.write(to: fileURL, options: .atomic)
            
            print("📁 Training Load: Saved \(loads.count) days to file")
        } catch {
            print("❌ Training Load: Failed to save to file: \(error.localizedDescription)")
        }
    }
    
    /// Clears all training load data from file storage
    func clearAll() {
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                print("🗑️ Training Load: File deleted")
            }
        } catch {
            print("❌ Training Load: Failed to delete file: \(error.localizedDescription)")
        }
    }
    
    /// Returns the size of the training load data file in bytes
    func getStorageSize() -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// Returns a human-readable string of the file size
    func getStorageSizeFormatted() -> String {
        let bytes = getStorageSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Migration
    
    /// Automatically migrates data from UserDefaults to file storage (one-time operation)
    private func migrateFromUserDefaultsIfNeeded() {
        let userDefaults = UserDefaults.standard
        
        // Check if migration has already been performed
        guard !userDefaults.bool(forKey: migrationKey) else {
            print("📁 Training Load: Migration already completed")
            return
        }
        
        print("🔄 Training Load: Starting migration from UserDefaults...")
        
        // Try to load from UserDefaults
        guard let legacyData = userDefaults.data(forKey: legacyUserDefaultsKey),
              let legacyLoads = try? JSONDecoder().decode([DailyTrainingLoad].self, from: legacyData) else {
            print("📁 Training Load: No legacy data found in UserDefaults")
            userDefaults.set(true, forKey: migrationKey)
            userDefaults.synchronize()
            return
        }
        
        print("📁 Training Load: Found \(legacyLoads.count) days in UserDefaults")
        
        // Save to file storage
        saveDailyLoads(legacyLoads)
        
        // Verify the file was written successfully before cleaning up
        let verifyLoads = loadAllDailyLoads()
        guard verifyLoads.count == legacyLoads.count else {
            print("❌ Training Load: Migration verification failed! File has \(verifyLoads.count) days, expected \(legacyLoads.count)")
            print("⚠️ Training Load: Keeping UserDefaults data as backup")
            return
        }
        
        // Mark migration as complete FIRST (before removing UserDefaults data)
        userDefaults.set(true, forKey: migrationKey)
        userDefaults.synchronize() // Force immediate save
        
        print("✅ Training Load: Migration complete! \(legacyLoads.count) days moved to file storage")
        print("📁 Training Load: File size: \(getStorageSizeFormatted())")
        
        // Now it's safe to remove legacy data from UserDefaults
        userDefaults.removeObject(forKey: legacyUserDefaultsKey)
        userDefaults.synchronize()
        
        print("🧹 Training Load: Cleaned up UserDefaults")
    }
    
    /// Forces a migration (for testing or manual recovery)
    func forceMigration() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
        migrateFromUserDefaultsIfNeeded()
    }
}
