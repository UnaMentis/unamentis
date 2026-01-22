// UnaMentis - Kyutai Pocket Settings ViewModel
// ViewModel for Kyutai Pocket TTS settings UI
//
// Part of UI/Settings

import AVFoundation
import Combine
import Foundation
import SwiftUI

/// ViewModel for Kyutai Pocket TTS settings
@MainActor
final class KyutaiPocketSettingsViewModel: ObservableObject {

    // MARK: - Model State

    @Published var modelState: KyutaiPocketModelManager.ModelState = .notDownloaded
    @Published var isLoading = false

    // MARK: - Preset Selection

    @Published var selectedPreset: KyutaiPocketPreset = .default {
        didSet {
            if selectedPreset != .custom {
                applyPreset(selectedPreset)
            }
            KyutaiPocketTTSConfig.savePreset(selectedPreset)
        }
    }

    var availablePresets: [KyutaiPocketPreset] = KyutaiPocketPreset.allCases

    // MARK: - Voice Selection

    @Published var selectedVoice: KyutaiPocketVoice = .alba {
        didSet {
            voiceIndex = selectedVoice.rawValue
            saveSettings()
        }
    }

    @Published var voiceGenderFilter: VoiceGender = .all

    var filteredVoices: [KyutaiPocketVoice] {
        switch voiceGenderFilter {
        case .all:
            return KyutaiPocketVoice.allCases
        case .female:
            return KyutaiPocketVoice.allCases.filter { $0.gender == .female }
        case .male:
            return KyutaiPocketVoice.allCases.filter { $0.gender == .male }
        }
    }

    // MARK: - Configuration Properties

    @AppStorage("kyutai_pocket_voice_index") var voiceIndex: Int = 0
    @AppStorage("kyutai_pocket_temperature") var temperature: Double = 0.7
    @AppStorage("kyutai_pocket_top_p") var topP: Double = 0.9
    @AppStorage("kyutai_pocket_speed") var speed: Double = 1.0
    @AppStorage("kyutai_pocket_consistency_steps") var consistencySteps: Int = 2
    @AppStorage("kyutai_pocket_use_neural_engine") var useNeuralEngine: Bool = true
    @AppStorage("kyutai_pocket_enable_prefetch") var enablePrefetch: Bool = true
    @AppStorage("kyutai_pocket_use_fixed_seed") var useFixedSeed: Bool = false
    @AppStorage("kyutai_pocket_seed") var seed: Int = 42

    // MARK: - Voice Cloning

    @Published var voiceCloningEnabled = false
    @Published var referenceAudioPath: String?
    @Published var showAudioPicker = false
    @Published var showAudioRecorder = false

    var hasReferenceAudio: Bool {
        referenceAudioPath != nil
    }

    var referenceAudioFileName: String {
        guard let path = referenceAudioPath else { return "" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: - Testing

    @Published var testText = "Hello, this is a test of the Kyutai Pocket text to speech system."
    @Published var isTesting = false
    @Published var testResult: String?

    // MARK: - Services

    private var modelManager: KyutaiPocketModelManager?
    private var ttsService: KyutaiPocketTTSService?
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Initialization

    init() {
        // Initialize model manager and load saved settings
        Task {
            await setupModelManager()
            await loadSavedSettings()
        }
    }

    /// Load saved settings from UserDefaults after init completes
    private func loadSavedSettings() async {
        // Load current preset
        selectedPreset = KyutaiPocketTTSConfig.currentPreset()

        // Load selected voice from saved index
        selectedVoice = KyutaiPocketVoice(rawValue: voiceIndex) ?? .alba
    }

    // MARK: - Model Management

    private func setupModelManager() async {
        modelManager = KyutaiPocketModelManager()
        await refreshModelState()
    }

    func refreshModelState() async {
        guard let manager = modelManager else { return }
        modelState = await manager.currentState()
    }

    func loadModels() async {
        guard let manager = modelManager else { return }
        isLoading = true

        do {
            let config = buildConfig()
            try await manager.loadModels(config: config)
            modelState = .loaded
        } catch {
            modelState = .error(error.localizedDescription)
        }

        isLoading = false
    }

    func unloadModels() async {
        guard let manager = modelManager else { return }
        await manager.unloadModels()
        modelState = .available
    }

    // MARK: - Configuration

    private func buildConfig() -> KyutaiPocketTTSConfig {
        KyutaiPocketTTSConfig(
            voiceIndex: voiceIndex,
            referenceAudioPath: voiceCloningEnabled ? referenceAudioPath : nil,
            temperature: Float(temperature),
            topP: Float(topP),
            speed: Float(speed),
            consistencySteps: consistencySteps,
            useNeuralEngine: useNeuralEngine,
            enablePrefetch: enablePrefetch,
            seed: useFixedSeed ? seed : nil
        )
    }

    func saveSettings() {
        let config = buildConfig()
        config.saveToUserDefaults()
    }

    private func applyPreset(_ preset: KyutaiPocketPreset) {
        let config = preset.config
        temperature = Double(config.temperature)
        topP = Double(config.topP)
        speed = Double(config.speed)
        consistencySteps = config.consistencySteps
        useNeuralEngine = config.useNeuralEngine
        enablePrefetch = config.enablePrefetch
        useFixedSeed = config.seed != nil
        seed = config.seed ?? 42
    }

    func onSliderValueChanged() {
        // Switch to custom preset when user adjusts sliders
        if selectedPreset != .custom {
            selectedPreset = .custom
        }
        saveSettings()
    }

    func resetToDefaults() {
        selectedPreset = .default
        selectedVoice = .alba
        voiceCloningEnabled = false
        referenceAudioPath = nil
        applyPreset(.default)
        saveSettings()
    }

    // MARK: - Voice Cloning

    func clearReferenceAudio() {
        referenceAudioPath = nil
        voiceCloningEnabled = false
    }

    // MARK: - Testing

    func testSynthesis() async {
        guard modelState == .loaded else {
            testResult = "Error: Models not loaded"
            return
        }

        isTesting = true
        testResult = nil

        do {
            // Create or get TTS service
            if ttsService == nil {
                ttsService = KyutaiPocketTTSService(
                    config: buildConfig(),
                    modelManager: modelManager
                )
            }

            guard let service = ttsService else {
                testResult = "Error: Could not create TTS service"
                isTesting = false
                return
            }

            // Update config
            await service.configurePocket(buildConfig())

            let startTime = Date()

            // Synthesize
            let stream = try await service.synthesize(text: testText)

            // Collect audio data
            var audioData = Data()
            for await chunk in stream {
                audioData.append(chunk.audioData)
            }

            let totalTime = Date().timeIntervalSince(startTime)

            // Play audio
            try await playAudio(data: audioData)

            testResult = String(format: "Success: %.2fs synthesis time, %d bytes", totalTime, audioData.count)

        } catch {
            testResult = "Error: \(error.localizedDescription)"
        }

        isTesting = false
    }

    private func playAudio(data: Data) async throws {
        // Convert float32 PCM to audio player compatible format
        // This is a simplified implementation
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_audio.wav")

        // Create WAV header for 24kHz mono float32
        let wavData = createWAVFile(from: data, sampleRate: 24000, channels: 1)
        try wavData.write(to: tempURL)

        audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
        audioPlayer?.play()
    }

    private func createWAVFile(from pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        let fileSize = UInt32(36 + pcmData.count)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // Format chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // Chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // Format: IEEE float
        data.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        let byteRate = UInt32(sampleRate * channels * 4) // 4 bytes per float32 sample
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = UInt16(channels * 4)
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(32).littleEndian) { Array($0) }) // Bits per sample

        // Data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(pcmData.count).littleEndian) { Array($0) })
        data.append(pcmData)

        return data
    }

    // MARK: - Descriptions

    var temperatureDescription: String {
        switch temperature {
        case 0.0..<0.3: return "Deterministic"
        case 0.3..<0.6: return "Consistent"
        case 0.6..<0.8: return "Balanced"
        case 0.8..<1.0: return "Creative"
        default: return "Random"
        }
    }

    var topPDescription: String {
        switch topP {
        case 0.0..<0.5: return "Focused"
        case 0.5..<0.8: return "Moderate"
        case 0.8..<0.95: return "Diverse"
        default: return "Unrestricted"
        }
    }

    var speedDescription: String {
        switch speed {
        case 0.0..<0.7: return "Slow"
        case 0.7..<0.95: return "Relaxed"
        case 0.95..<1.05: return "Normal"
        case 1.05..<1.3: return "Brisk"
        default: return "Fast"
        }
    }

    var consistencyStepsDescription: String {
        switch consistencySteps {
        case 1: return "Fast"
        case 2: return "Balanced"
        case 3: return "High Quality"
        case 4: return "Best Quality"
        default: return "Unknown"
        }
    }

    // MARK: - Model Info

    var totalDownloadSizeMB: String {
        String(format: "%.0f MB", KyutaiPocketModelInfo.totalSizeMB)
    }

    var modelStateDescription: String {
        modelState.displayText
    }
}
