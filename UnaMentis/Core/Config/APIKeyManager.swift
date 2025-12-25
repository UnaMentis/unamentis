// UnaMentis - API Key Manager
// Secure management of API keys for external services
//
// Part of Configuration (TDD Section 7)

import Foundation
import Security
import Logging

/// Manages API keys securely using Keychain and environment variables
///
/// Priority order:
/// 1. Keychain (most secure, persistent)
/// 2. Environment variables (development)
/// 3. UserDefaults (fallback, least secure)
public actor APIKeyManager {
    
    // MARK: - Singleton
    
    public static let shared = APIKeyManager()
    
    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.apikeys")
    private static let migrationLogger = Logger(label: "com.unamentis.apikeys.migration")
    private let serviceName = "com.unamentis.apikeys"
    private let legacyServiceName = "com.voicelearn.apikeys"

    /// Flag to track if migration has been attempted
    private static let migrationKey = "apiKeyMigrationCompleted"
    
    /// API key identifiers
    public enum KeyType: String, CaseIterable, Sendable {
        case assemblyAI = "ASSEMBLYAI_API_KEY"
        case deepgram = "DEEPGRAM_API_KEY"
        case openAI = "OPENAI_API_KEY"
        case anthropic = "ANTHROPIC_API_KEY"
        case elevenLabs = "ELEVENLABS_API_KEY"
        case liveKit = "LIVEKIT_API_KEY"
        case liveKitSecret = "LIVEKIT_API_SECRET"
        
        public var displayName: String {
            switch self {
            case .assemblyAI: return "AssemblyAI"
            case .deepgram: return "Deepgram"
            case .openAI: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .elevenLabs: return "ElevenLabs"
            case .liveKit: return "LiveKit API Key"
            case .liveKitSecret: return "LiveKit Secret"
            }
        }
    }
    
    // MARK: - Initialization

    private init() {
        logger.info("APIKeyManager initialized")

        // Perform one-time migration from legacy service name
        if !UserDefaults.standard.bool(forKey: Self.migrationKey) {
            migrateFromLegacyService()
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
        }
    }

    // MARK: - Migration

    /// Migrate API keys from legacy service name (com.voicelearn.apikeys)
    /// This is called once on first launch after upgrade to preserve user's keys
    /// Note: nonisolated because it's called from init and only uses synchronous Keychain APIs
    private nonisolated func migrateFromLegacyService() {
        Self.migrationLogger.debug("Checking for legacy API keys to migrate...")

        var migratedCount = 0

        for keyType in KeyType.allCases {
            // Check if key exists in legacy service
            if let legacyKey = getFromLegacyKeychainSync(keyType) {
                // Check if new service already has this key
                if getFromKeychainSync(keyType) == nil {
                    // Migrate: save to new service
                    if saveToKeychainSync(keyType: keyType, value: legacyKey) {
                        migratedCount += 1
                        Self.migrationLogger.info("Migrated API key: \(keyType.displayName)")
                    } else {
                        Self.migrationLogger.error("Failed to migrate \(keyType.displayName)")
                    }
                }

                // Delete from legacy service (cleanup)
                deleteLegacyKeySync(keyType)
            }
        }

        if migratedCount > 0 {
            Self.migrationLogger.info("Successfully migrated \(migratedCount) API key(s) from legacy storage")
        } else {
            Self.migrationLogger.debug("No legacy API keys found to migrate")
        }
    }

    /// Get a key from the legacy keychain service (synchronous, nonisolated)
    private nonisolated func getFromLegacyKeychainSync(_ keyType: KeyType) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.voicelearn.apikeys",
            kSecAttrAccount as String: keyType.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Get a key from the new keychain service (synchronous, nonisolated)
    private nonisolated func getFromKeychainSync(_ keyType: KeyType) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unamentis.apikeys",
            kSecAttrAccount as String: keyType.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Save a key to the new keychain service (synchronous, nonisolated)
    private nonisolated func saveToKeychainSync(keyType: KeyType, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        // Delete any existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unamentis.apikeys",
            kSecAttrAccount as String: keyType.rawValue
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unamentis.apikeys",
            kSecAttrAccount as String: keyType.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Delete a key from legacy keychain service (synchronous, nonisolated)
    private nonisolated func deleteLegacyKeySync(_ keyType: KeyType) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.voicelearn.apikeys",
            kSecAttrAccount as String: keyType.rawValue
        ]

        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Public API
    
    /// Get an API key, checking sources in priority order
    public func getKey(_ keyType: KeyType) -> String? {
        // 1. Try Keychain first
        if let key = getFromKeychain(keyType) {
            return key
        }
        
        // 2. Try environment variable
        if let key = ProcessInfo.processInfo.environment[keyType.rawValue], !key.isEmpty {
            return key
        }
        
        // 3. Try UserDefaults (for development only)
        if let key = UserDefaults.standard.string(forKey: keyType.rawValue), !key.isEmpty {
            return key
        }
        
        logger.warning("No API key found for: \(keyType.displayName)")
        return nil
    }
    
    /// Store an API key in Keychain
    public func setKey(_ keyType: KeyType, value: String) throws {
        try saveToKeychain(keyType: keyType, value: value)
        logger.info("Saved API key for: \(keyType.displayName)")
    }
    
    /// Remove an API key from Keychain
    public func removeKey(_ keyType: KeyType) throws {
        try deleteFromKeychain(keyType)
        logger.info("Removed API key for: \(keyType.displayName)")
    }
    
    /// Check if a key is configured
    public func hasKey(_ keyType: KeyType) -> Bool {
        getKey(keyType) != nil
    }
    
    /// Get status of all keys
    public func getKeyStatus() -> [KeyType: Bool] {
        var status: [KeyType: Bool] = [:]
        for keyType in KeyType.allCases {
            status[keyType] = hasKey(keyType)
        }
        return status
    }
    
    /// Validate all required keys for a session based on selected providers
    /// Returns empty array if all required keys are present or if using on-device providers
    public func validateRequiredKeys() -> [KeyType] {
        var required: [KeyType] = []

        // Check STT provider - read from UserDefaults
        let sttRaw = UserDefaults.standard.string(forKey: "sttProvider") ?? ""
        switch sttRaw {
        case "AssemblyAI Universal-Streaming":
            required.append(.assemblyAI)
        case "Deepgram Nova-3":
            required.append(.deepgram)
        case "OpenAI Whisper":
            required.append(.openAI)
        case "Apple Speech (On-Device)", "GLM-ASR-Nano (On-Device)", "GLM-ASR-Nano (Self-Hosted)":
            // On-device or self-hosted, no API key needed
            break
        default:
            // Default to on-device if not set
            break
        }

        // Check LLM provider
        let llmRaw = UserDefaults.standard.string(forKey: "llmProvider") ?? ""
        switch llmRaw {
        case "OpenAI":
            if !required.contains(.openAI) {
                required.append(.openAI)
            }
        case "Anthropic Claude":
            required.append(.anthropic)
        case "Local MLX":
            // On-device, no API key needed
            break
        default:
            // Default to on-device if not set
            break
        }

        // Check TTS provider
        let ttsRaw = UserDefaults.standard.string(forKey: "ttsProvider") ?? ""
        switch ttsRaw {
        case "Deepgram Aura-2":
            if !required.contains(.deepgram) {
                required.append(.deepgram)
            }
        case "ElevenLabs Flash", "ElevenLabs Turbo":
            required.append(.elevenLabs)
        case "Apple TTS (On-Device)":
            // On-device, no API key needed
            break
        default:
            // Default to on-device if not set
            break
        }

        logger.debug("Required keys based on settings: \(required.map { $0.displayName })")
        return required.filter { !hasKey($0) }
    }
    
    // MARK: - Keychain Operations
    
    private func getFromKeychain(_ keyType: KeyType) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyType.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    private func saveToKeychain(keyType: KeyType, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw APIKeyError.invalidValue
        }
        
        // Delete any existing key first
        try? deleteFromKeychain(keyType)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyType.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw APIKeyError.keychainError(status)
        }
    }
    
    private func deleteFromKeychain(_ keyType: KeyType) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyType.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyError.keychainError(status)
        }
    }
}

// MARK: - Errors

public enum APIKeyError: Error, LocalizedError {
    case invalidValue
    case keychainError(OSStatus)
    case keyNotFound(APIKeyManager.KeyType)
    
    public var errorDescription: String? {
        switch self {
        case .invalidValue:
            return "Invalid API key value"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .keyNotFound(let keyType):
            return "API key not found: \(keyType.displayName)"
        }
    }
}
