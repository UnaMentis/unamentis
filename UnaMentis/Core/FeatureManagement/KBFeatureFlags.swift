//
//  KBFeatureFlags.swift
//  UnaMentis
//
//  Feature flag management for Knowledge Bowl enhanced validation
//  Server administrators control which features are enabled for their users
//  All features are open source; flags control what's enabled on a given server
//

import Foundation
import OSLog

// MARK: - Feature Flags

/// Feature flag management for Knowledge Bowl (controlled by server admin)
actor KBFeatureFlags {
    private let logger = Logger(subsystem: "com.unamentis", category: "KBFeatureFlags")

    // MARK: - Features

    /// Available features for Knowledge Bowl
    enum Feature: String, Sendable, CaseIterable {
        case llmValidation = "kb_llm_validation"
        case customDictionaries = "kb_custom_dictionaries"
        case advancedAnalytics = "kb_advanced_analytics"
        case offlineMode = "kb_offline_mode"

        var displayName: String {
            switch self {
            case .llmValidation:
                return "LLM Answer Validation"
            case .customDictionaries:
                return "Custom Synonym Dictionaries"
            case .advancedAnalytics:
                return "Advanced Performance Analytics"
            case .offlineMode:
                return "Full Offline Mode"
            }
        }

        var description: String {
            switch self {
            case .llmValidation:
                return "Expert-level answer validation using a small open-source language model (Llama 3.2 1B). Achieves 95-98% accuracy."
            case .customDictionaries:
                return "Create and manage custom synonym dictionaries for specialized topics."
            case .advancedAnalytics:
                return "Detailed performance metrics and learning insights."
            case .offlineMode:
                return "Use all features without an internet connection."
            }
        }
    }

    // MARK: - Feature State

    /// Feature flags (controlled by server configuration)
    /// Server admin determines which features are enabled
    private var enabledFeatures: Set<Feature>

    // MARK: - Initialization

    init(enabledFeatures: Set<Feature> = []) {
        self.enabledFeatures = enabledFeatures
    }

    /// Initialize with server configuration
    /// - Parameter serverConfig: Configuration from server
    init(fromServerConfig config: [String: Bool]) {
        var features: Set<Feature> = []
        for (key, enabled) in config {
            if enabled, let feature = Feature(rawValue: key) {
                features.insert(feature)
            }
        }
        self.enabledFeatures = features
        logger.info("Initialized with \(features.count) enabled features")
    }

    // MARK: - Public API

    /// Check if a feature is enabled by the server admin
    /// - Parameter feature: Feature to check
    /// - Returns: True if feature is enabled
    nonisolated func isFeatureEnabled(_ feature: Feature) async -> Bool {
        await enabledFeatures.contains(feature)
    }

    /// Update feature flags from server configuration
    /// Called when syncing with server
    func updateFromServer(_ config: [String: Bool]) {
        var features: Set<Feature> = []
        for (key, enabled) in config {
            if enabled, let feature = Feature(rawValue: key) {
                features.insert(feature)
            }
        }
        enabledFeatures = features
        logger.info("Updated feature flags from server: \(features.count) enabled")
    }

    /// Enable a feature (for server admin or testing)
    func enable(_ feature: Feature) {
        enabledFeatures.insert(feature)
        logger.info("Enabled feature: \(feature.displayName)")
    }

    /// Disable a feature (for server admin or testing)
    func disable(_ feature: Feature) {
        enabledFeatures.remove(feature)
        logger.info("Disabled feature: \(feature.displayName)")
    }

    /// Get all enabled features
    nonisolated func getEnabledFeatures() async -> Set<Feature> {
        await enabledFeatures
    }

    /// Check device capability for feature
    /// - Parameter feature: Feature to check
    /// - Returns: True if device supports the feature
    nonisolated func isDeviceCapable(for feature: Feature) -> Bool {
        switch feature {
        case .llmValidation:
            // Tier 3 requires iPhone 12+ with 4GB+ RAM
            return DeviceCapability.supportsLLMValidation()

        case .customDictionaries, .advancedAnalytics, .offlineMode:
            // Available on all devices
            return true
        }
    }

    /// Get feature availability with reason
    /// - Parameter feature: Feature to check
    /// - Returns: Tuple of (available, reason)
    nonisolated func featureAvailability(for feature: Feature) async -> (available: Bool, reason: String?) {
        // Check if server admin has enabled this feature
        let isEnabled = await isFeatureEnabled(feature)
        guard isEnabled else {
            return (false, "Feature not enabled on this server")
        }

        // Check device capability
        guard isDeviceCapable(for: feature) else {
            return (false, "Device does not meet minimum requirements")
        }

        return (true, nil)
    }

    /// Get feature summary for UI display
    nonisolated func getFeatureSummary() async -> [(feature: Feature, enabled: Bool, reason: String?)] {
        let enabled = await enabledFeatures
        return Feature.allCases.map { feature in
            let isEnabled = enabled.contains(feature)
            let deviceCapable = isDeviceCapable(for: feature)

            let reason: String?
            if !isEnabled {
                reason = "Not enabled on this server"
            } else if !deviceCapable {
                reason = "Device does not meet requirements"
            } else {
                reason = nil
            }

            return (feature, isEnabled && deviceCapable, reason)
        }
    }
}

// MARK: - Default Configurations

extension KBFeatureFlags {
    /// Default configuration (all features enabled)
    /// Server admins can restrict as needed
    static func defaultConfiguration() -> KBFeatureFlags {
        KBFeatureFlags(enabledFeatures: Set(Feature.allCases))
    }

    /// Minimal configuration (Tier 1 only)
    /// For resource-constrained servers
    static func minimalConfiguration() -> KBFeatureFlags {
        KBFeatureFlags(enabledFeatures: [.offlineMode])
    }

    /// Standard configuration (Tier 1 + 2)
    /// Recommended for most servers
    static func standardConfiguration() -> KBFeatureFlags {
        KBFeatureFlags(enabledFeatures: [.offlineMode, .advancedAnalytics])
    }

    /// Full configuration (all tiers)
    /// For well-resourced servers
    static func fullConfiguration() -> KBFeatureFlags {
        KBFeatureFlags(enabledFeatures: Set(Feature.allCases))
    }
}

// MARK: - Preview Support

#if DEBUG
extension KBFeatureFlags {
    static func preview(enabled: Set<Feature> = Set(Feature.allCases)) -> KBFeatureFlags {
        KBFeatureFlags(enabledFeatures: enabled)
    }
}
#endif
