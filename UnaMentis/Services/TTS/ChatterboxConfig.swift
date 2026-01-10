// UnaMentis - Chatterbox TTS Configuration
// Configuration struct for Chatterbox TTS provider (Resemble AI)
//
// Part of Services/TTS

import Foundation

// MARK: - Chatterbox Configuration

/// Configuration for Chatterbox TTS provider
///
/// Chatterbox is an open-source TTS model from Resemble AI with unique features:
/// - Emotion control via exaggeration parameter
/// - CFG (Classifier-Free Guidance) weight for generation fidelity
/// - Paralinguistic tags for natural reactions ([laugh], [cough], etc.)
/// - Zero-shot voice cloning from reference audio
/// - Multilingual support (23 languages)
public struct ChatterboxConfig: Codable, Sendable, Equatable {

    // MARK: - Emotion Control

    /// Emotion exaggeration level
    /// - 0.0: Monotone, flat delivery
    /// - 0.5: Balanced, natural expressiveness (default)
    /// - 1.0+: Dramatic, highly expressive
    /// Range: 0.0 to 1.5
    public var exaggeration: Float

    /// Classifier-Free Guidance weight
    /// Controls generation fidelity and style adherence
    /// - Lower values (~0.3): Better for fast speakers or dramatic content
    /// - Higher values (~0.7): More controlled, consistent output
    /// Range: 0.0 to 1.0
    public var cfgWeight: Float

    // MARK: - Speed Control

    /// Speaking speed multiplier
    /// - 0.5: Half speed (slower)
    /// - 1.0: Normal speed (default)
    /// - 2.0: Double speed (faster)
    /// Range: 0.5 to 2.0
    public var speed: Float

    // MARK: - Paralinguistic Tags

    /// Enable paralinguistic tag processing
    /// When enabled, tags like [laugh], [cough], [sigh], [chuckle], [gasp]
    /// in the text will trigger natural vocal reactions.
    /// When disabled, these tags are stripped from the text.
    public var enableParalinguisticTags: Bool

    // MARK: - Multilingual Support

    /// Use the multilingual model (500M parameters, 23 languages)
    /// instead of the Turbo model (350M, English-only)
    public var useMultilingual: Bool

    /// Language code for multilingual synthesis
    /// Only used when useMultilingual is true
    /// Supported: ar, da, de, el, en, es, fi, fr, he, hi, it, ja, ko, ms, nl, no, pl, pt, ru, sv, sw, tr, zh
    public var language: String

    // MARK: - Performance

    /// Use streaming endpoint for lower latency to first byte
    /// - true: Streaming mode (~472ms TTFB, audio chunks delivered progressively)
    /// - false: Non-streaming (complete audio returned at once)
    public var useStreaming: Bool

    // MARK: - Advanced

    /// Random seed for reproducible generation
    /// Set to nil for random (non-reproducible) generation
    /// Set to a specific value (0-999999) for reproducible output
    public var seed: Int?

    // MARK: - Voice Cloning (DEFERRED)

    /// Path to reference audio for zero-shot voice cloning
    /// Requires 5+ seconds of clean speech
    /// Set to nil to use the default voice
    /// NOTE: Voice cloning UI is deferred for future implementation
    public var referenceAudioPath: String?

    // MARK: - Initialization

    public init(
        exaggeration: Float = 0.5,
        cfgWeight: Float = 0.5,
        speed: Float = 1.0,
        enableParalinguisticTags: Bool = false,
        useMultilingual: Bool = false,
        language: String = "en",
        useStreaming: Bool = true,
        seed: Int? = nil,
        referenceAudioPath: String? = nil
    ) {
        self.exaggeration = exaggeration
        self.cfgWeight = cfgWeight
        self.speed = speed
        self.enableParalinguisticTags = enableParalinguisticTags
        self.useMultilingual = useMultilingual
        self.language = language
        self.useStreaming = useStreaming
        self.seed = seed
        self.referenceAudioPath = referenceAudioPath
    }

    // MARK: - Presets

    /// Default balanced configuration
    public static let `default` = ChatterboxConfig(
        exaggeration: 0.5,
        cfgWeight: 0.5,
        speed: 1.0,
        enableParalinguisticTags: false,
        useMultilingual: false,
        language: "en",
        useStreaming: true,
        seed: nil,
        referenceAudioPath: nil
    )

    /// Natural, conversational preset
    /// Lower exaggeration and CFG for more natural flow
    public static let natural = ChatterboxConfig(
        exaggeration: 0.3,
        cfgWeight: 0.3,
        speed: 1.0,
        enableParalinguisticTags: true,
        useMultilingual: false,
        language: "en",
        useStreaming: true,
        seed: nil,
        referenceAudioPath: nil
    )

    /// Expressive, dramatic preset
    /// Higher exaggeration for storytelling, lectures
    public static let expressive = ChatterboxConfig(
        exaggeration: 0.8,
        cfgWeight: 0.3,
        speed: 0.9,
        enableParalinguisticTags: true,
        useMultilingual: false,
        language: "en",
        useStreaming: true,
        seed: nil,
        referenceAudioPath: nil
    )

    /// Low latency preset optimized for voice agents
    public static let lowLatency = ChatterboxConfig(
        exaggeration: 0.4,
        cfgWeight: 0.4,
        speed: 1.1,
        enableParalinguisticTags: false,
        useMultilingual: false,
        language: "en",
        useStreaming: true,
        seed: nil,
        referenceAudioPath: nil
    )
}

// MARK: - Preset Enum

/// Chatterbox configuration presets
public enum ChatterboxPreset: String, Codable, CaseIterable, Sendable {
    case `default` = "default"
    case natural = "natural"
    case expressive = "expressive"
    case lowLatency = "lowLatency"
    case custom = "custom"

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .default: return "Default"
        case .natural: return "Natural"
        case .expressive: return "Expressive"
        case .lowLatency: return "Low Latency"
        case .custom: return "Custom"
        }
    }

    /// Get the configuration for this preset
    public var config: ChatterboxConfig {
        switch self {
        case .default: return .default
        case .natural: return .natural
        case .expressive: return .expressive
        case .lowLatency: return .lowLatency
        case .custom: return .default // Custom uses user's saved values
        }
    }

    /// Description for UI
    public var description: String {
        switch self {
        case .default:
            return "Balanced settings for general use"
        case .natural:
            return "Conversational, relaxed delivery with natural reactions"
        case .expressive:
            return "Dramatic, engaging delivery for storytelling"
        case .lowLatency:
            return "Optimized for fast response in voice agents"
        case .custom:
            return "Your custom configuration"
        }
    }
}

// MARK: - Supported Languages

/// Languages supported by Chatterbox Multilingual model
public enum ChatterboxLanguage: String, Codable, CaseIterable, Sendable {
    case arabic = "ar"
    case chinese = "zh"
    case danish = "da"
    case dutch = "nl"
    case english = "en"
    case finnish = "fi"
    case french = "fr"
    case german = "de"
    case greek = "el"
    case hebrew = "he"
    case hindi = "hi"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case malay = "ms"
    case norwegian = "no"
    case polish = "pl"
    case portuguese = "pt"
    case russian = "ru"
    case spanish = "es"
    case swahili = "sw"
    case swedish = "sv"
    case turkish = "tr"

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .arabic: return "Arabic"
        case .chinese: return "Chinese"
        case .danish: return "Danish"
        case .dutch: return "Dutch"
        case .english: return "English"
        case .finnish: return "Finnish"
        case .french: return "French"
        case .german: return "German"
        case .greek: return "Greek"
        case .hebrew: return "Hebrew"
        case .hindi: return "Hindi"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .malay: return "Malay"
        case .norwegian: return "Norwegian"
        case .polish: return "Polish"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .spanish: return "Spanish"
        case .swahili: return "Swahili"
        case .swedish: return "Swedish"
        case .turkish: return "Turkish"
        }
    }

    /// Native name for the language
    public var nativeName: String {
        switch self {
        case .arabic: return "العربية"
        case .chinese: return "中文"
        case .danish: return "Dansk"
        case .dutch: return "Nederlands"
        case .english: return "English"
        case .finnish: return "Suomi"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .greek: return "Ελληνικά"
        case .hebrew: return "עברית"
        case .hindi: return "हिन्दी"
        case .italian: return "Italiano"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .malay: return "Bahasa Melayu"
        case .norwegian: return "Norsk"
        case .polish: return "Polski"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .spanish: return "Español"
        case .swahili: return "Kiswahili"
        case .swedish: return "Svenska"
        case .turkish: return "Türkçe"
        }
    }
}

// MARK: - UserDefaults Keys

/// UserDefaults keys for Chatterbox settings
extension ChatterboxConfig {

    private enum UserDefaultsKey {
        static let exaggeration = "chatterbox_exaggeration"
        static let cfgWeight = "chatterbox_cfg_weight"
        static let speed = "chatterbox_speed"
        static let paralinguisticTags = "chatterbox_paralinguistic_tags"
        static let useMultilingual = "chatterbox_use_multilingual"
        static let language = "chatterbox_language"
        static let streaming = "chatterbox_streaming"
        static let useFixedSeed = "chatterbox_use_fixed_seed"
        static let seed = "chatterbox_seed"
    }

    /// Load configuration from UserDefaults with proper default values
    ///
    /// This method safely reads from UserDefaults, using the correct defaults
    /// when values haven't been explicitly set.
    public static func fromUserDefaults() -> ChatterboxConfig {
        let defaults = UserDefaults.standard

        // For numeric values, check if the key exists to use proper defaults
        let exaggeration: Float = defaults.object(forKey: UserDefaultsKey.exaggeration) != nil
            ? Float(defaults.double(forKey: UserDefaultsKey.exaggeration))
            : 0.5

        let cfgWeight: Float = defaults.object(forKey: UserDefaultsKey.cfgWeight) != nil
            ? Float(defaults.double(forKey: UserDefaultsKey.cfgWeight))
            : 0.5

        let speed: Float = defaults.object(forKey: UserDefaultsKey.speed) != nil
            ? Float(defaults.double(forKey: UserDefaultsKey.speed))
            : 1.0

        // Bool defaults to false if not set, which matches some but not all settings
        let enableParalinguisticTags = defaults.bool(forKey: UserDefaultsKey.paralinguisticTags)
        let useMultilingual = defaults.bool(forKey: UserDefaultsKey.useMultilingual)

        let language = defaults.string(forKey: UserDefaultsKey.language) ?? "en"

        // Streaming defaults to true, but UserDefaults.bool returns false if not set
        let useStreaming: Bool = defaults.object(forKey: UserDefaultsKey.streaming) != nil
            ? defaults.bool(forKey: UserDefaultsKey.streaming)
            : true

        let useFixedSeed = defaults.bool(forKey: UserDefaultsKey.useFixedSeed)
        let seed = useFixedSeed ? defaults.integer(forKey: UserDefaultsKey.seed) : nil

        return ChatterboxConfig(
            exaggeration: exaggeration,
            cfgWeight: cfgWeight,
            speed: speed,
            enableParalinguisticTags: enableParalinguisticTags,
            useMultilingual: useMultilingual,
            language: language,
            useStreaming: useStreaming,
            seed: seed,
            referenceAudioPath: nil
        )
    }
}

// MARK: - Paralinguistic Tags

/// Supported paralinguistic tags in Chatterbox
public enum ChatterboxParalinguisticTag: String, CaseIterable, Sendable {
    case laugh = "[laugh]"
    case cough = "[cough]"
    case chuckle = "[chuckle]"
    case sigh = "[sigh]"
    case gasp = "[gasp]"

    /// Description for UI
    public var description: String {
        switch self {
        case .laugh: return "Natural laughter"
        case .cough: return "Throat clearing or cough"
        case .chuckle: return "Light, brief laugh"
        case .sigh: return "Breath release, exhaustion"
        case .gasp: return "Sharp intake of breath, surprise"
        }
    }
}
