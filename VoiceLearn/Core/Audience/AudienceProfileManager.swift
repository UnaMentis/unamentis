// VoiceLearn - Audience Profile Manager
// Manages storage, retrieval, and activation of audience profiles

import Foundation
import SwiftUI

/// Manages audience profiles with persistence
@MainActor
public final class AudienceProfileManager: ObservableObject {
    // MARK: - Published State

    /// All saved profiles
    @Published public private(set) var profiles: [AudienceProfile] = []

    /// Currently active profile
    @Published public private(set) var activeProfile: AudienceProfile?

    // MARK: - Storage

    private let userDefaultsKey = "voicelearn.audience.profiles"
    private let activeProfileKey = "voicelearn.audience.activeProfileId"

    // MARK: - Singleton

    public static let shared = AudienceProfileManager()

    // MARK: - Initialization

    private init() {
        loadProfiles()
    }

    // MARK: - Public Methods

    /// Get the active profile or default
    public func getActiveProfile() -> AudienceProfile {
        activeProfile ?? AudienceProfile.defaultProfile
    }

    /// Save a new profile
    public func saveProfile(_ profile: AudienceProfile) {
        var updatedProfile = profile
        updatedProfile.modifiedAt = Date()

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updatedProfile
        } else {
            profiles.append(updatedProfile)
        }

        persistProfiles()
    }

    /// Delete a profile
    public func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }

        // If we deleted the active profile, clear it
        if activeProfile?.id == id {
            activeProfile = nil
            UserDefaults.standard.removeObject(forKey: activeProfileKey)
        }

        persistProfiles()
    }

    /// Set the active profile
    public func setActiveProfile(_ profile: AudienceProfile?) {
        // Deactivate current
        if let currentIndex = profiles.firstIndex(where: { $0.isActive }) {
            profiles[currentIndex].isActive = false
        }

        // Activate new
        if let profile = profile,
           let newIndex = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[newIndex].isActive = true
            activeProfile = profiles[newIndex]
            UserDefaults.standard.set(profile.id.uuidString, forKey: activeProfileKey)
        } else {
            activeProfile = nil
            UserDefaults.standard.removeObject(forKey: activeProfileKey)
        }

        persistProfiles()
    }

    /// Create a new profile from a preset
    public func createFromPreset(_ preset: AudienceProfile, name: String? = nil) -> AudienceProfile {
        var newProfile = preset
        newProfile = AudienceProfile(
            id: UUID(),
            name: name ?? preset.name,
            ageGroup: preset.ageGroup,
            learningContext: preset.learningContext,
            audienceBreadth: preset.audienceBreadth,
            narrativeStyle: preset.narrativeStyle,
            voicePersonality: preset.voicePersonality,
            speakingRateOverride: preset.speakingRateOverride,
            customInstructions: preset.customInstructions,
            isActive: false,
            createdAt: Date(),
            modifiedAt: Date()
        )

        saveProfile(newProfile)
        return newProfile
    }

    /// Initialize with presets if no profiles exist
    public func initializeWithPresetsIfNeeded() {
        guard profiles.isEmpty else { return }

        // Add default profile as active
        var defaultProfile = AudienceProfile.defaultProfile
        defaultProfile = AudienceProfile(
            id: UUID(),
            name: defaultProfile.name,
            ageGroup: defaultProfile.ageGroup,
            learningContext: defaultProfile.learningContext,
            audienceBreadth: defaultProfile.audienceBreadth,
            narrativeStyle: defaultProfile.narrativeStyle,
            voicePersonality: defaultProfile.voicePersonality,
            isActive: true,
            createdAt: Date(),
            modifiedAt: Date()
        )

        profiles = [defaultProfile]
        activeProfile = defaultProfile
        persistProfiles()
    }

    // MARK: - Private Methods

    private func loadProfiles() {
        // Load profiles from UserDefaults
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([AudienceProfile].self, from: data) {
            profiles = decoded
        }

        // Load active profile ID
        if let activeIdString = UserDefaults.standard.string(forKey: activeProfileKey),
           let activeId = UUID(uuidString: activeIdString) {
            activeProfile = profiles.first { $0.id == activeId }
        }

        // If no active profile but we have profiles, activate the first
        if activeProfile == nil && !profiles.isEmpty {
            if let index = profiles.firstIndex(where: { $0.isActive }) {
                activeProfile = profiles[index]
            } else {
                profiles[0].isActive = true
                activeProfile = profiles[0]
                persistProfiles()
            }
        }
    }

    private func persistProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
}

// MARK: - Convenience Extensions for Prompt Generation

extension AudienceProfile {
    /// Generate voice configuration recommendations based on profile
    public func recommendedVoiceConfig() -> VoiceConfigRecommendation {
        VoiceConfigRecommendation(
            speakingRate: effectiveSpeakingRate,
            voiceTraits: voicePersonality.voiceTraits,
            personality: voicePersonality,
            ageGroup: ageGroup
        )
    }
}

/// Voice configuration recommendations based on audience
public struct VoiceConfigRecommendation: Sendable {
    /// Recommended speaking rate (0.5 - 2.0)
    public let speakingRate: Double

    /// Desired voice traits for selection
    public let voiceTraits: [String]

    /// Voice personality
    public let personality: VoicePersonality

    /// Target age group
    public let ageGroup: AgeGroup

    /// Description for voice selection
    public var voiceSelectionHint: String {
        "Looking for a \(voiceTraits.joined(separator: ", ")) voice suitable for \(ageGroup.displayName) audience."
    }
}

// MARK: - Integration with ContentDepth

extension AudienceProfile {
    /// Generate combined instructions for both content depth and audience
    /// This merges the "what" (depth) with the "how" (audience)
    public func generateCombinedInstructions(for depth: ContentDepth) -> String {
        var combined: [String] = []

        combined.append("# DELIVERY GUIDELINES")
        combined.append("")
        combined.append("## CONTENT DEPTH: \(depth.displayName)")
        combined.append(depth.aiInstructions)
        combined.append("")
        combined.append("### Mathematical Content")
        combined.append(depth.mathPresentationStyle)
        combined.append("")
        combined.append(generateAIInstructions())

        return combined.joined(separator: "\n")
    }
}
