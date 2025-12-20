//
//  CacheService.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 12/19/25.
//

import Foundation

struct CacheService {
    // Determine your specific cache directory
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    /// Returns a formatted string size (e.g., "12.4 MB")
    static func getCurrentSize() -> String {
        guard let url = cacheURL else { return "Unknown" }
        // ... (Insert directory size calculation logic here)
        return "12 MB" // Placeholder return
    }

    static func clearCache() {
        guard let url = cacheURL else { return }
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for fileUrl in contents {
                try fileManager.removeItem(at: fileUrl)
            }
            print("Disk Clean: Cache cleared successfully.")
        } catch {
            print("Disk Clean Error: \(error.localizedDescription)")
        }
    }
}
