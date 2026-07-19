//
//  JSONFileStorage.swift
//  RideWeather Pro
//
//  Generic file-based storage for large Codable arrays with automatic
//  one-time migration out of UserDefaults (same pattern as TrainingLoadStorage).
//

import Foundation

/// Persists a Codable array as a JSON file in the Documents directory.
///
/// UserDefaults rejects domains over 4 MB, so large blobs (ride analyses,
/// pacing plans, comparisons) live in files instead. On first use, any
/// legacy blob under `legacyUserDefaultsKey` is moved into the file and
/// removed from UserDefaults once the file verifiably holds it.
final class JSONFileStorage<Element: Codable> {
    private let fileManager = FileManager.default
    private let label: String
    private let legacyUserDefaultsKey: String
    private let migrationKey: String
    let fileURL: URL

    init(fileName: String, legacyUserDefaultsKey: String, label: String) {
        self.label = label
        self.legacyUserDefaultsKey = legacyUserDefaultsKey
        self.migrationKey = "\(legacyUserDefaultsKey)Migrated_v1"
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = documentsDirectory.appendingPathComponent(fileName)
        migrateFromUserDefaultsIfNeeded()
    }

    func load() -> [Element] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Element].self, from: data)
        } catch {
            print("❌ \(label): Failed to load from file: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ items: [Element]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ \(label): Failed to save to file: \(error.localizedDescription)")
        }
    }

    // MARK: - Migration

    private func migrateFromUserDefaultsIfNeeded() {
        let userDefaults = UserDefaults.standard
        guard !userDefaults.bool(forKey: migrationKey) else { return }

        guard let legacyData = userDefaults.data(forKey: legacyUserDefaultsKey),
              let legacyItems = try? JSONDecoder().decode([Element].self, from: legacyData) else {
            // Nothing to migrate
            userDefaults.set(true, forKey: migrationKey)
            return
        }

        print("🔄 \(label): Migrating \(legacyItems.count) items from UserDefaults to file...")
        save(legacyItems)

        // Only drop the UserDefaults copy once the file verifiably holds it
        guard load().count == legacyItems.count else {
            print("❌ \(label): Migration verification failed — keeping UserDefaults data")
            return
        }

        userDefaults.set(true, forKey: migrationKey)
        userDefaults.removeObject(forKey: legacyUserDefaultsKey)
        print("✅ \(label): Migration complete (\(legacyItems.count) items moved to \(fileURL.lastPathComponent))")
    }
}
