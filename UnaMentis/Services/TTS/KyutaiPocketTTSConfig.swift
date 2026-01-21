// UnaMentis - Kyutai Pocket TTS Configuration
// Configuration struct for Kyutai Pocket TTS on-device model
//
// Part of Services/TTS

import Foundation

// MARK: - Kyutai Pocket TTS Configuration

/// Configuration for Kyutai Pocket TTS on-device model
///
/// Kyutai Pocket TTS is a 100M parameter on-device text-to-speech model with:
/// - 8 built-in voices (alba, marius, javert, jean, fantine, cosette, eponine, azelma)
/// - 5-second voice cloning capability
/// - 24kHz high-quality output
/// - 1.84% WER (best in class for on-device)
/// - ~200ms time to first audio
/// - MIT licensed (code and weights)
public struct KyutaiPocketTTSConfig: Codable, Sendable, Equatable {

    // MARK: - Voice Selection

    /// Index of the built-in voice to use (0-7)
    /// - 0: Alba (female, warm)
    /// - 1: Marius (male, clear)
    /// - 2: Javert (male, authoritative)
    /// - 3: Jean (male, gentle)
    /// - 4: Fantine (female, soft)
    /// - 5: Cosette (female, bright)
    /// - 6: Eponine (female, expressive)
    /// - 7: Azelma (female, youthful)
    public var voiceIndex: Int

    /// Path to reference audio for voice cloning (optional)
    /// Requires 5+ seconds of clean speech
    /// Set to nil to use a built-in voice
    public var referenceAudioPath: String?

    // MARK: - Sampling Control

    /// Sampling temperature
    /// Controls randomness in generation
    /// - 0.0: Deterministic (same input = same output)
    /// - 0.7: Balanced quality and variation (default)
    /// - 1.0+: More random, potentially less coherent
    /// Range: 0.0 to 1.5
    public var temperature: Float

    /// Top-p (nucleus) sampling threshold
    /// Controls diversity by limiting to top cumulative probability
    /// - 0.1: Very focused, predictable
    /// - 0.9: Diverse but coherent (default)
    /// - 1.0: No filtering
    /// Range: 0.1 to 1.0
    public var topP: Float

    // MARK: - Speed Control

    /// Speaking speed multiplier
    /// - 0.5: Half speed (slower)
    /// - 1.0: Normal speed (default)
    /// - 2.0: Double speed (faster)
    /// Range: 0.5 to 2.0
    public var speed: Float

    // MARK: - Quality Control

    /// Number of consistency sampling steps
    /// Higher values improve quality at cost of latency
    /// - 1: Fastest, lowest quality
    /// - 2: Good balance (default)
    /// - 4: Highest quality, slower
    /// Range: 1 to 4
    public var consistencySteps: Int

    // MARK: - Performance

    /// Use Neural Engine for inference
    /// - true: Neural Engine + GPU (fastest, default)
    /// - false: CPU only (more compatible, slower)
    public var useNeuralEngine: Bool

    /// Enable prefetching for lower latency
    /// Pre-loads next likely tokens during streaming
    /// - true: Lower latency to first byte (default)
    /// - false: Lower memory usage
    public var enablePrefetch: Bool

    // MARK: - Advanced

    /// Random seed for reproducible generation
    /// Set to nil for random (non-reproducible) generation
    /// Set to a specific value for reproducible output
    public var seed: Int?

    // MARK: - Initialization

    public init(
        voiceIndex: Int = 0,
        referenceAudioPath: String? = nil,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        speed: Float = 1.0,
        consistencySteps: Int = 2,
        useNeuralEngine: Bool = true,
        enablePrefetch: Bool = true,
        seed: Int? = nil
    ) {
        self.voiceIndex = voiceIndex.clamped(to: 0...7)
        self.referenceAudioPath = referenceAudioPath
        self.temperature = temperature.clamped(to: 0.0...1.5)
        self.topP = topP.clamped(to: 0.1...1.0)
        self.speed = speed.clamped(to: 0.5...2.0)
        self.consistencySteps = consistencySteps.clamped(to: 1...4)
        self.useNeuralEngine = useNeuralEngine
        self.enablePrefetch = enablePrefetch
        self.seed = seed
    }

    // MARK: - Presets

    /// Default balanced configuration
    public static let `default` = KyutaiPocketTTSConfig(
        voiceIndex: 0,
        referenceAudioPath: nil,
        temperature: 0.7,
        topP: 0.9,
        speed: 1.0,
        consistencySteps: 2,
        useNeuralEngine: true,
        enablePrefetch: true,
        seed: nil
    )

    /// Low latency preset optimized for voice agents
    /// Fastest time to first byte, slight quality tradeoff
    public static let lowLatency = KyutaiPocketTTSConfig(
        voiceIndex: 0,
        referenceAudioPath: nil,
        temperature: 0.5,
        topP: 0.85,
        speed: 1.1,
        consistencySteps: 1,
        useNeuralEngine: true,
        enablePrefetch: true,
        seed: nil
    )

    /// High quality preset for pre-rendered content
    /// Best quality, higher latency
    public static let highQuality = KyutaiPocketTTSConfig(
        voiceIndex: 0,
        referenceAudioPath: nil,
        temperature: 0.7,
        topP: 0.95,
        speed: 1.0,
        consistencySteps: 4,
        useNeuralEngine: true,
        enablePrefetch: false,
        seed: nil
    )

    /// Battery saver preset
    /// CPU-only inference for lower power consumption
    public static let batterySaver = KyutaiPocketTTSConfig(
        voiceIndex: 0,
        referenceAudioPath: nil,
        temperature: 0.6,
        topP: 0.9,
        speed: 1.0,
        consistencySteps: 1,
        useNeuralEngine: false,
        enablePrefetch: false,
        seed: nil
    )
}

// MARK: - Voice Enum

/// Built-in voices for Kyutai Pocket TTS
public enum KyutaiPocketVoice: Int, Codable, CaseIterable, Sendable {
    case alba = 0
    case marius = 1
    case javert = 2
    case jean = 3
    case fantine = 4
    case cosette = 5
    case eponine = 6
    case azelma = 7

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .alba: return "Alba"
        case .marius: return "Marius"
        case .javert: return "Javert"
        case .jean: return "Jean"
        case .fantine: return "Fantine"
        case .cosette: return "Cosette"
        case .eponine: return "Eponine"
        case .azelma: return "Azelma"
        }
    }

    /// Voice characteristics description
    public var description: String {
        switch self {
        case .alba: return "Female, warm and welcoming"
        case .marius: return "Male, clear and articulate"
        case .javert: return "Male, authoritative and firm"
        case .jean: return "Male, gentle and compassionate"
        case .fantine: return "Female, soft and tender"
        case .cosette: return "Female, bright and optimistic"
        case .eponine: return "Female, expressive and dynamic"
        case .azelma: return "Female, youthful and energetic"
        }
    }

    /// Voice gender for filtering
    public var gender: VoiceGender {
        switch self {
        case .alba, .fantine, .cosette, .eponine, .azelma:
            return .female
        case .marius, .javert, .jean:
            return .male
        }
    }

    /// Sample audio URL for preview
    public var sampleAudioName: String {
        "kyutai_pocket_\(rawValue)_sample"
    }
}

/// Voice gender for filtering UI
public enum VoiceGender: String, Codable, CaseIterable, Sendable {
    case female = "female"
    case male = "male"
    case all = "all"

    public var displayName: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .all: return "All"
        }
    }
}

// MARK: - Preset Enum

/// Kyutai Pocket configuration presets
public enum KyutaiPocketPreset: String, Codable, CaseIterable, Sendable {
    case `default` = "default"
    case lowLatency = "lowLatency"
    case highQuality = "highQuality"
    case batterySaver = "batterySaver"
    case custom = "custom"

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .default: return "Default"
        case .lowLatency: return "Low Latency"
        case .highQuality: return "High Quality"
        case .batterySaver: return "Battery Saver"
        case .custom: return "Custom"
        }
    }

    /// Get the configuration for this preset
    public var config: KyutaiPocketTTSConfig {
        switch self {
        case .default: return .default
        case .lowLatency: return .lowLatency
        case .highQuality: return .highQuality
        case .batterySaver: return .batterySaver
        case .custom: return .default
        }
    }

    /// Description for UI
    public var description: String {
        switch self {
        case .default:
            return "Balanced quality and latency for general use"
        case .lowLatency:
            return "Fastest response for voice agents and conversations"
        case .highQuality:
            return "Best quality for pre-rendered content and narration"
        case .batterySaver:
            return "CPU-only mode for extended battery life"
        case .custom:
            return "Your custom configuration"
        }
    }
}

// MARK: - UserDefaults Keys

/// UserDefaults keys for Kyutai Pocket settings
extension KyutaiPocketTTSConfig {

    private enum UserDefaultsKey {
        static let voiceIndex = "kyutai_pocket_voice_index"
        static let referenceAudioPath = "kyutai_pocket_reference_audio"
        static let temperature = "kyutai_pocket_temperature"
        static let topP = "kyutai_pocket_top_p"
        static let speed = "kyutai_pocket_speed"
        static let consistencySteps = "kyutai_pocket_consistency_steps"
        static let useNeuralEngine = "kyutai_pocket_use_neural_engine"
        static let enablePrefetch = "kyutai_pocket_enable_prefetch"
        static let useFixedSeed = "kyutai_pocket_use_fixed_seed"
        static let seed = "kyutai_pocket_seed"
        static let preset = "kyutai_pocket_preset"
    }

    /// Load configuration from UserDefaults with proper default values
    public static func fromUserDefaults() -> KyutaiPocketTTSConfig {
        let defaults = UserDefaults.standard

        let voiceIndex: Int = defaults.object(forKey: UserDefaultsKey.voiceIndex) != nil
            ? defaults.integer(forKey: UserDefaultsKey.voiceIndex)
            : 0

        let referenceAudioPath = defaults.string(forKey: UserDefaultsKey.referenceAudioPath)

        let temperature: Float = defaults.object(forKey: UserDefaultsKey.temperature) != nil
            ? Float(defaults.double(forKey: UserDefaultsKey.temperature))
            : 0.7

        let topP: Float = defaults.object(forKey: UserDefaultsKey.topP) != nil
            ? Float(defaults.double(forKey: UserDefaultsKey.topP))
            : 0.9

        let speed: Float = defaults.object(forKey: UserDefaultsKey.speed) != nil
            ? Float(defaults.double(forKey: UserDefaultsKey.speed))
            : 1.0

        let consistencySteps: Int = defaults.object(forKey: UserDefaultsKey.consistencySteps) != nil
            ? defaults.integer(forKey: UserDefaultsKey.consistencySteps)
            : 2

        // Neural Engine defaults to true
        let useNeuralEngine: Bool = defaults.object(forKey: UserDefaultsKey.useNeuralEngine) != nil
            ? defaults.bool(forKey: UserDefaultsKey.useNeuralEngine)
            : true

        // Prefetch defaults to true
        let enablePrefetch: Bool = defaults.object(forKey: UserDefaultsKey.enablePrefetch) != nil
            ? defaults.bool(forKey: UserDefaultsKey.enablePrefetch)
            : true

        let useFixedSeed = defaults.bool(forKey: UserDefaultsKey.useFixedSeed)
        let seed = useFixedSeed ? defaults.integer(forKey: UserDefaultsKey.seed) : nil

        return KyutaiPocketTTSConfig(
            voiceIndex: voiceIndex,
            referenceAudioPath: referenceAudioPath,
            temperature: temperature,
            topP: topP,
            speed: speed,
            consistencySteps: consistencySteps,
            useNeuralEngine: useNeuralEngine,
            enablePrefetch: enablePrefetch,
            seed: seed
        )
    }

    /// Save configuration to UserDefaults
    public func saveToUserDefaults() {
        let defaults = UserDefaults.standard

        defaults.set(voiceIndex, forKey: UserDefaultsKey.voiceIndex)
        defaults.set(referenceAudioPath, forKey: UserDefaultsKey.referenceAudioPath)
        defaults.set(Double(temperature), forKey: UserDefaultsKey.temperature)
        defaults.set(Double(topP), forKey: UserDefaultsKey.topP)
        defaults.set(Double(speed), forKey: UserDefaultsKey.speed)
        defaults.set(consistencySteps, forKey: UserDefaultsKey.consistencySteps)
        defaults.set(useNeuralEngine, forKey: UserDefaultsKey.useNeuralEngine)
        defaults.set(enablePrefetch, forKey: UserDefaultsKey.enablePrefetch)

        if let seed = seed {
            defaults.set(true, forKey: UserDefaultsKey.useFixedSeed)
            defaults.set(seed, forKey: UserDefaultsKey.seed)
        } else {
            defaults.set(false, forKey: UserDefaultsKey.useFixedSeed)
        }
    }

    /// Get the current preset from UserDefaults
    public static func currentPreset() -> KyutaiPocketPreset {
        let defaults = UserDefaults.standard
        let rawValue = defaults.string(forKey: UserDefaultsKey.preset) ?? "default"
        return KyutaiPocketPreset(rawValue: rawValue) ?? .default
    }

    /// Save the current preset to UserDefaults
    public static func savePreset(_ preset: KyutaiPocketPreset) {
        UserDefaults.standard.set(preset.rawValue, forKey: UserDefaultsKey.preset)
    }
}

// MARK: - Model Info

/// Static information about the Kyutai Pocket TTS model
public enum KyutaiPocketModelInfo {
    /// Total model size in MB (all components)
    public static let totalSizeMB: Int = 100

    /// Sample rate of generated audio
    public static let sampleRate: Int = 24000

    /// Word Error Rate (WER) benchmark
    public static let wordErrorRate: Float = 0.0184

    /// Typical time to first audio (ms)
    public static let typicalLatencyMS: Int = 200

    /// Minimum iOS version required
    public static let minimumIOSVersion: String = "17.0"

    /// License type
    public static let license: String = "MIT"

    /// Model components with sizes
    public static let components: [(name: String, sizeMB: Int)] = [
        ("Transformer Backbone", 70),
        ("MLP Sampler", 10),
        ("Mimi VAE Decoder", 20),
    ]

    /// Required device memory (MB)
    public static let requiredMemoryMB: Int = 300
}

// MARK: - Comparable Extensions

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
