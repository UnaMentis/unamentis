// UnaMentis - Chatterbox Settings ViewModel
// ViewModel for managing Chatterbox TTS settings with persistence
//
// Part of UI/Settings

import SwiftUI
import Combine
import AVFoundation

/// ViewModel for Chatterbox TTS settings
///
/// Provides @AppStorage-backed properties for all Chatterbox configuration options.
/// Changes are automatically persisted to UserDefaults.
@MainActor
final class ChatterboxSettingsViewModel: ObservableObject {

    // MARK: - Preset Selection

    /// Selected preset
    @AppStorage("chatterbox_preset") var selectedPresetRaw: String = ChatterboxPreset.default.rawValue

    var selectedPreset: ChatterboxPreset {
        get { ChatterboxPreset(rawValue: selectedPresetRaw) ?? .default }
        set {
            selectedPresetRaw = newValue.rawValue
            if newValue != .custom {
                applyPreset(newValue)
            }
        }
    }

    // MARK: - Emotion Control

    /// Exaggeration level (0.0 to 1.5)
    @AppStorage("chatterbox_exaggeration") var exaggeration: Double = 0.5

    /// CFG weight (0.0 to 1.0)
    @AppStorage("chatterbox_cfg_weight") var cfgWeight: Double = 0.5

    // MARK: - Speed Control

    /// Speaking speed (0.5 to 2.0)
    @AppStorage("chatterbox_speed") var speed: Double = 1.0

    // MARK: - Paralinguistic Tags

    /// Enable paralinguistic tag processing
    @AppStorage("chatterbox_paralinguistic_tags") var enableParalinguisticTags: Bool = false

    // MARK: - Multilingual Support

    /// Use multilingual model
    @AppStorage("chatterbox_use_multilingual") var useMultilingual: Bool = false

    /// Selected language code
    @AppStorage("chatterbox_language") var languageCode: String = "en"

    var selectedLanguage: ChatterboxLanguage {
        get { ChatterboxLanguage(rawValue: languageCode) ?? .english }
        set { languageCode = newValue.rawValue }
    }

    // MARK: - Performance

    /// Use streaming mode
    @AppStorage("chatterbox_streaming") var useStreaming: Bool = true

    // MARK: - Advanced

    /// Use fixed seed for reproducibility
    @AppStorage("chatterbox_use_fixed_seed") var useFixedSeed: Bool = false

    /// Seed value (only used when useFixedSeed is true)
    @AppStorage("chatterbox_seed") var seed: Int = 42

    // MARK: - Voice Cloning

    /// Whether voice cloning is enabled
    @AppStorage("chatterbox_voice_cloning_enabled") var voiceCloningEnabled: Bool = false

    /// Reference audio path for voice cloning
    @AppStorage("chatterbox_reference_audio") var referenceAudioPath: String = ""

    /// Show audio file picker sheet
    @Published var showAudioPicker: Bool = false

    /// Show audio recorder sheet
    @Published var showAudioRecorder: Bool = false

    /// Whether reference audio is configured
    var hasReferenceAudio: Bool {
        !referenceAudioPath.isEmpty && FileManager.default.fileExists(atPath: referenceAudioPath)
    }

    /// File name of reference audio
    var referenceAudioFileName: String {
        guard !referenceAudioPath.isEmpty else { return "" }
        return URL(fileURLWithPath: referenceAudioPath).lastPathComponent
    }

    /// Clear reference audio
    func clearReferenceAudio() {
        referenceAudioPath = ""
    }

    // MARK: - Server Connection

    /// Whether server is reachable
    @Published var isServerReachable: Bool = false

    /// Whether multilingual model is available
    @Published var isMultilingualAvailable: Bool = false

    /// Last health check time
    @Published var lastHealthCheck: Date?

    // MARK: - Test Synthesis

    /// Whether test synthesis is in progress
    @Published var isTesting: Bool = false

    /// Test result message
    @Published var testResult: String?

    /// Test sample text
    var testText: String = "Hello! This is a test of the Chatterbox text-to-speech system."

    /// Audio player for test playback
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Computed Properties

    /// Current configuration as ChatterboxConfig
    var currentConfig: ChatterboxConfig {
        ChatterboxConfig(
            exaggeration: Float(exaggeration),
            cfgWeight: Float(cfgWeight),
            speed: Float(speed),
            enableParalinguisticTags: enableParalinguisticTags,
            useMultilingual: useMultilingual,
            language: languageCode,
            useStreaming: useStreaming,
            seed: useFixedSeed ? seed : nil,
            referenceAudioPath: referenceAudioPath.isEmpty ? nil : referenceAudioPath
        )
    }

    /// Preset display name
    var presetDisplayName: String {
        selectedPreset.displayName
    }

    /// All available languages
    var availableLanguages: [ChatterboxLanguage] {
        ChatterboxLanguage.allCases
    }

    /// All available presets
    var availablePresets: [ChatterboxPreset] {
        ChatterboxPreset.allCases
    }

    /// Exaggeration description based on current value
    var exaggerationDescription: String {
        switch exaggeration {
        case 0..<0.2:
            return "Monotone"
        case 0.2..<0.4:
            return "Subdued"
        case 0.4..<0.6:
            return "Balanced"
        case 0.6..<0.8:
            return "Expressive"
        case 0.8..<1.0:
            return "Dramatic"
        default:
            return "Very Dramatic"
        }
    }

    /// CFG weight description based on current value
    var cfgWeightDescription: String {
        switch cfgWeight {
        case 0..<0.3:
            return "Creative"
        case 0.3..<0.5:
            return "Natural"
        case 0.5..<0.7:
            return "Balanced"
        default:
            return "Controlled"
        }
    }

    /// Speed description based on current value
    var speedDescription: String {
        switch speed {
        case 0.5..<0.8:
            return "Slow"
        case 0.8..<1.1:
            return "Normal"
        case 1.1..<1.5:
            return "Fast"
        default:
            return "Very Fast"
        }
    }

    // MARK: - Initialization

    init() {
        // Check server health on init
        Task {
            await checkServerHealth()
        }
    }

    // MARK: - Preset Application

    /// Apply a preset configuration
    func applyPreset(_ preset: ChatterboxPreset) {
        guard preset != .custom else { return }

        let config = preset.config
        exaggeration = Double(config.exaggeration)
        cfgWeight = Double(config.cfgWeight)
        speed = Double(config.speed)
        enableParalinguisticTags = config.enableParalinguisticTags
        useStreaming = config.useStreaming
    }

    /// Mark current settings as custom
    func markAsCustom() {
        if selectedPreset != .custom {
            selectedPresetRaw = ChatterboxPreset.custom.rawValue
        }
    }

    // MARK: - Server Health

    /// Check if Chatterbox server is reachable
    func checkServerHealth() async {
        // Get server IP from settings
        let serverIP = UserDefaults.standard.string(forKey: "selfHostedServerIP") ?? "localhost"
        let port = TTSProvider.chatterbox.defaultPort

        // Use /api/model-info instead of /health since ChatterBox server doesn't have a /health endpoint
        let healthURL = URL(string: "http://\(serverIP):\(port)/api/model-info")!

        do {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                isServerReachable = httpResponse.statusCode == 200
            }

            // Check for multilingual model
            await checkMultilingualAvailability(serverIP: serverIP, port: port)

        } catch {
            isServerReachable = false
        }

        lastHealthCheck = Date()
    }

    /// Check if multilingual model is available
    private func checkMultilingualAvailability(serverIP: String, port: Int) async {
        let modelsURL = URL(string: "http://\(serverIP):\(port)/v1/models")!

        do {
            let (data, response) = try await URLSession.shared.data(from: modelsURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isMultilingualAvailable = false
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [String] {
                isMultilingualAvailable = models.contains { $0.lowercased().contains("multilingual") }
            }
        } catch {
            isMultilingualAvailable = false
        }
    }

    // MARK: - Test Synthesis

    /// Run a test synthesis and play the audio
    func testSynthesis() async {
        isTesting = true
        testResult = nil

        // Stop any existing playback
        audioPlayer?.stop()
        audioPlayer = nil

        let serverIP = UserDefaults.standard.string(forKey: "selfHostedServerIP") ?? "localhost"
        let service = ChatterboxTTSService.chatterbox(
            host: serverIP,
            config: currentConfig
        )

        do {
            let startTime = Date()
            let stream = try await service.synthesize(text: testText)

            var audioData = Data()
            var chunkCount = 0

            // Collect all audio chunks
            for await chunk in stream {
                audioData.append(chunk.audioData)
                chunkCount += 1
            }

            let elapsed = Date().timeIntervalSince(startTime)

            guard !audioData.isEmpty else {
                testResult = "Error: No audio data received"
                isTesting = false
                return
            }

            // Play the audio
            do {
                // Configure audio session for playback
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)

                // Check if it's WAV format (starts with RIFF header)
                let isWav = audioData.count > 4 &&
                    audioData[0] == 0x52 && // R
                    audioData[1] == 0x49 && // I
                    audioData[2] == 0x46 && // F
                    audioData[3] == 0x46    // F

                if isWav {
                    // WAV data can be played directly
                    audioPlayer = try AVAudioPlayer(data: audioData)
                } else {
                    // Raw PCM data - wrap in WAV header
                    let wavData = createWavData(from: audioData, sampleRate: 24000, channels: 1, bitsPerSample: 16)
                    audioPlayer = try AVAudioPlayer(data: wavData)
                }

                audioPlayer?.prepareToPlay()
                audioPlayer?.play()

                testResult = "Playing: \(audioData.count) bytes, \(chunkCount) chunks, \(String(format: "%.2f", elapsed))s"

            } catch {
                testResult = "Playback error: \(error.localizedDescription)"
            }

        } catch {
            testResult = "Error: \(error.localizedDescription)"
        }

        isTesting = false
    }

    /// Create WAV file data from raw PCM samples
    private func createWavData(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var wavData = Data()

        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcmData.count
        let chunkSize = 36 + dataSize

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(chunkSize).littleEndian) { Array($0) })
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // Subchunk1Size (16 for PCM)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // AudioFormat (1 = PCM)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data subchunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        wavData.append(pcmData)

        return wavData
    }

    // MARK: - Reset

    /// Reset all settings to defaults
    func resetToDefaults() {
        selectedPresetRaw = ChatterboxPreset.default.rawValue
        exaggeration = 0.5
        cfgWeight = 0.5
        speed = 1.0
        enableParalinguisticTags = false
        useMultilingual = false
        languageCode = "en"
        useStreaming = true
        useFixedSeed = false
        seed = 42
        referenceAudioPath = ""
    }
}

// MARK: - Slider Value Change Detection

extension ChatterboxSettingsViewModel {

    /// Called when any slider value changes
    func onSliderValueChanged() {
        // Mark as custom preset when user adjusts sliders
        markAsCustom()
    }
}
