// UnaMentis - Module Registry
// Local cache for downloaded modules
//
// The registry stores metadata for modules the user has downloaded.
// Actual module content and questions are fetched from the server
// during sessions to keep the app lightweight.

import SwiftUI
import Logging

/// Local registry for downloaded modules
///
/// This is a cache of modules the user has chosen to download.
/// Module discovery happens through ModuleService (server-side).
/// The registry persists downloaded module metadata locally.
@MainActor
public final class ModuleRegistry: ObservableObject {
    /// Shared singleton instance
    public static let shared = ModuleRegistry()

    private static let logger = Logger(label: "com.unamentis.modules.registry")

    /// Downloaded modules stored locally
    @Published private(set) var downloadedModules: [String: DownloadedModule] = [:]

    /// UserDefaults key for persisting downloaded modules
    private let storageKey = "com.unamentis.downloadedModules"

    private init() {
        loadFromStorage()
    }

    // MARK: - Downloaded Modules

    /// All downloaded modules
    public var allDownloaded: [DownloadedModule] {
        Array(downloadedModules.values).sorted { $0.name < $1.name }
    }

    /// Check if a module is downloaded
    public func isDownloaded(moduleId: String) -> Bool {
        downloadedModules[moduleId] != nil
    }

    /// Get a downloaded module by ID
    public func getDownloaded(moduleId: String) -> DownloadedModule? {
        downloadedModules[moduleId]
    }

    /// Register a newly downloaded module
    public func registerDownloaded(_ module: DownloadedModule) {
        downloadedModules[module.id] = module
        saveToStorage()
        Self.logger.info("Registered downloaded module: \(module.name)")
    }

    /// Remove a downloaded module
    public func removeDownloaded(moduleId: String) {
        if let module = downloadedModules.removeValue(forKey: moduleId) {
            saveToStorage()
            Self.logger.info("Removed downloaded module: \(module.name)")
        }
    }

    /// Clear all downloaded modules
    public func clearAll() {
        downloadedModules.removeAll()
        saveToStorage()
        Self.logger.info("Cleared all downloaded modules")
    }

    // MARK: - Persistence

    private func saveToStorage() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(downloadedModules.values))
            UserDefaults.standard.set(data, forKey: storageKey)
            Self.logger.debug("Saved \(downloadedModules.count) modules to storage")
        } catch {
            Self.logger.error("Failed to save modules: \(error)")
        }
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            Self.logger.debug("No downloaded modules in storage")
            return
        }

        do {
            let decoder = JSONDecoder()
            let modules = try decoder.decode([DownloadedModule].self, from: data)
            downloadedModules = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
            Self.logger.info("Loaded \(modules.count) modules from storage")
        } catch {
            Self.logger.error("Failed to load modules: \(error)")
        }
    }
}
