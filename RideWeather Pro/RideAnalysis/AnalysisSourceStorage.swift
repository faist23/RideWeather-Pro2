//
//  AnalysisSourceStorage.swift
//  RideWeather Pro
//
//  File-backed store for per-analysis source info (Strava / Wahoo / Garmin /
//  FIT file). Previously a single growing dictionary in UserDefaults that was
//  rewritten on every import and never pruned when analyses were deleted.
//

import Foundation

/// One persisted source entry, keyed by the analysis it describes.
struct AnalysisSourceRecord: Codable {
    let analysisId: UUID
    let source: RideSourceInfo
}

/// Persists `RideSourceInfo` per ride analysis in a JSON file.
///
/// Held as `static` state so the one-time migration out of UserDefaults runs
/// once per launch (same convention as the other `JSONFileStorage` users).
enum AnalysisSourceStorage {
    /// Legacy UserDefaults key holding a JSON-encoded `[UUID: RideSourceInfo]`.
    private static let legacyDictionaryKey = "analysisSourceInfo"
    private static let migrationFlagKey = "analysisSourceInfoMigratedToFile_v1"

    /// `JSONFileStorage` only migrates legacy *arrays*; the old data is a
    /// dictionary, so it's migrated by `migrateLegacyDictionaryIfNeeded()`
    /// instead and this legacy key is intentionally one that never existed.
    private static let file = JSONFileStorage<AnalysisSourceRecord>(
        fileName: "analysisSources.json",
        legacyUserDefaultsKey: "analysisSourceRecords",
        label: "Analysis Sources"
    )

    /// In-memory copy, loaded (and migrated) on first access.
    private static var cache: [UUID: RideSourceInfo] = {
        migrateLegacyDictionaryIfNeeded()
        return Dictionary(
            file.load().map { ($0.analysisId, $0.source) },
            uniquingKeysWith: { _, newest in newest }
        )
    }()

    /// All stored sources, keyed by analysis id.
    static func loadAll() -> [UUID: RideSourceInfo] { cache }

    /// Stores (or replaces) the source for one analysis.
    static func save(_ source: RideSourceInfo, for analysisId: UUID) {
        cache[analysisId] = source
        persist()
    }

    /// Drops sources whose analysis no longer exists (deleted, or trimmed by
    /// the saved-analysis cap).
    static func prune(keeping analysisIds: Set<UUID>) {
        let before = cache.count
        cache = cache.filter { analysisIds.contains($0.key) }
        if cache.count != before { persist() }
    }

    private static func persist() {
        file.save(cache.map { AnalysisSourceRecord(analysisId: $0.key, source: $0.value) })
    }

    private static func migrateLegacyDictionaryIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlagKey) else { return }

        guard let data = defaults.data(forKey: legacyDictionaryKey),
              let legacy = try? JSONDecoder().decode([UUID: RideSourceInfo].self, from: data) else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        // Merge in case the file already has entries, then verify before
        // dropping the UserDefaults copy.
        var merged = Dictionary(
            file.load().map { ($0.analysisId, $0.source) },
            uniquingKeysWith: { _, newest in newest }
        )
        for (id, source) in legacy where merged[id] == nil { merged[id] = source }
        file.save(merged.map { AnalysisSourceRecord(analysisId: $0.key, source: $0.value) })

        guard file.load().count == merged.count else {
            print("❌ Analysis Sources: migration verification failed — keeping UserDefaults data")
            return
        }
        defaults.set(true, forKey: migrationFlagKey)
        defaults.removeObject(forKey: legacyDictionaryKey)
        print("✅ Analysis Sources: migrated \(legacy.count) entries to analysisSources.json")
    }
}
