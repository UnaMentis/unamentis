// UnaMentis - Kyutai Pocket Settings View
// Advanced settings UI for Kyutai Pocket TTS on-device model
//
// Part of UI/Settings

import SwiftUI

/// Advanced settings view for Kyutai Pocket TTS
///
/// Exposes all Kyutai Pocket TTS configuration options:
/// - Model download/load management
/// - Voice selection (8 built-in voices)
/// - Sampling parameters (temperature, top-p)
/// - Speed control
/// - Quality settings (consistency steps)
/// - Performance options (Neural Engine, prefetch)
/// - Voice cloning
/// - Test synthesis
struct KyutaiPocketSettingsView: View {

    @StateObject private var viewModel = KyutaiPocketSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Helper binding to convert String? to String for AudioFilePickerView and AudioRecorderView
    private var referenceAudioPathBinding: Binding<String> {
        Binding(
            get: { viewModel.referenceAudioPath ?? "" },
            set: { viewModel.referenceAudioPath = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        List {
            // Model Status
            modelStatusSection

            // Quick Presets
            presetsSection

            // Voice Selection
            voiceSelectionSection

            // Sampling Control
            samplingSection

            // Speed Control
            speedSection

            // Quality Settings
            qualitySection

            // Performance
            performanceSection

            // Voice Cloning
            voiceCloningSection

            // Advanced
            advancedSection

            // Test
            testSection

            // Reset
            resetSection

            // Model Info
            modelInfoSection
        }
        .navigationTitle("Kyutai Pocket TTS")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task {
                await viewModel.refreshModelState()
            }
        }
    }

    // MARK: - Model Status Section

    private var modelStatusSection: some View {
        Section {
            HStack {
                modelStatusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.modelStateDescription)
                        .font(.subheadline)
                    Text(modelStatusSubtext)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Loading progress
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            // Action buttons based on state
            switch viewModel.modelState {
            case .notDownloaded:
                // Models should be bundled; show error state
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Models not bundled. Build configuration error.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

            case .downloading:
                EmptyView()

            case .available:
                Button {
                    Task {
                        await viewModel.loadModels()
                    }
                } label: {
                    Label("Load Models", systemImage: "cpu")
                }
                .disabled(viewModel.isLoading)

            case .loaded:
                Button {
                    Task {
                        await viewModel.unloadModels()
                    }
                } label: {
                    Label("Unload Models", systemImage: "cpu.fill")
                }

            case .loading:
                EmptyView()

            case .error:
                Button {
                    Task {
                        await viewModel.refreshModelState()
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("Model Status")
        } footer: {
            Text("Kyutai Pocket TTS runs entirely on-device. Models are bundled with the app.")
        }
    }

    private var modelStatusIcon: some View {
        Group {
            switch viewModel.modelState {
            case .notDownloaded:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            case .downloading:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
            case .available:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            case .loading:
                Image(systemName: "cpu")
                    .foregroundStyle(.blue)
            case .loaded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.title2)
    }

    private var modelStatusSubtext: String {
        switch viewModel.modelState {
        case .notDownloaded:
            return "Build configuration error"
        case .downloading:
            return "Downloading models..."
        case .available:
            return "Bundled models ready to load"
        case .loading:
            return "Loading into memory..."
        case .loaded:
            return "Ready for synthesis"
        case .error(let message):
            return message
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        Section {
            Picker("Preset", selection: $viewModel.selectedPreset) {
                ForEach(viewModel.availablePresets, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)

            if viewModel.selectedPreset != .custom {
                Text(viewModel.selectedPreset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Quick Settings")
        } footer: {
            Text("Presets configure sampling and performance. Adjusting sliders switches to Custom.")
        }
    }

    // MARK: - Voice Selection Section

    private var voiceSelectionSection: some View {
        Section {
            // Gender filter
            Picker("Filter", selection: $viewModel.voiceGenderFilter) {
                ForEach(VoiceGender.allCases, id: \.self) { gender in
                    Text(gender.displayName).tag(gender)
                }
            }
            .pickerStyle(.segmented)

            // Voice picker
            ForEach(viewModel.filteredVoices, id: \.self) { voice in
                Button {
                    viewModel.selectedVoice = voice
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.displayName)
                                .foregroundStyle(.primary)
                            Text(voice.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.selectedVoice == voice {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("8 built-in voices named after Les Misérables characters. All voices support \(KyutaiPocketModelInfo.sampleRate / 1000)kHz output.")
        }
    }

    // MARK: - Sampling Section

    private var samplingSection: some View {
        Section {
            // Temperature slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", viewModel.temperature))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("(\(viewModel.temperatureDescription))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $viewModel.temperature, in: 0.0...1.5, step: 0.05) {
                    Text("Temperature")
                } onEditingChanged: { _ in
                    viewModel.onSliderValueChanged()
                }

                HStack {
                    Text("Deterministic")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Random")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Top-p slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top-P (Nucleus)")
                    Spacer()
                    Text(String(format: "%.2f", viewModel.topP))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("(\(viewModel.topPDescription))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $viewModel.topP, in: 0.1...1.0, step: 0.05) {
                    Text("Top-P")
                } onEditingChanged: { _ in
                    viewModel.onSliderValueChanged()
                }

                HStack {
                    Text("Focused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Diverse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sampling")
        } footer: {
            Text("Temperature controls randomness. Top-P limits vocabulary to the most probable tokens. Lower values produce more consistent output.")
        }
    }

    // MARK: - Speed Section

    private var speedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.1fx", viewModel.speed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("(\(viewModel.speedDescription))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $viewModel.speed, in: 0.5...2.0, step: 0.1) {
                    Text("Speed")
                } onEditingChanged: { _ in
                    viewModel.onSliderValueChanged()
                }

                HStack {
                    Text("0.5x")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("2.0x")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Speed")
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Consistency Steps")
                    Spacer()
                    Text("\(viewModel.consistencySteps)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("(\(viewModel.consistencyStepsDescription))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Steps", selection: $viewModel.consistencySteps) {
                    Text("1 (Fast)").tag(1)
                    Text("2 (Balanced)").tag(2)
                    Text("3 (High)").tag(3)
                    Text("4 (Best)").tag(4)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.consistencySteps) {
                    viewModel.onSliderValueChanged()
                }
            }
        } header: {
            Text("Quality")
        } footer: {
            Text("More consistency steps improve audio quality at the cost of latency. 2 steps offers a good balance.")
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        Section {
            Toggle("Use Neural Engine", isOn: $viewModel.useNeuralEngine)
                .onChange(of: viewModel.useNeuralEngine) {
                    viewModel.saveSettings()
                }

            Toggle("Enable Prefetch", isOn: $viewModel.enablePrefetch)
                .onChange(of: viewModel.enablePrefetch) {
                    viewModel.saveSettings()
                }

            HStack {
                Image(systemName: viewModel.useNeuralEngine ? "cpu.fill" : "cpu")
                    .foregroundStyle(viewModel.useNeuralEngine ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(viewModel.useNeuralEngine ? "Neural Engine + GPU" : "CPU Only")
                        .font(.subheadline)
                    Text(viewModel.useNeuralEngine ? "Fastest inference" : "Lower power, slower")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Performance")
        } footer: {
            Text("Neural Engine provides fastest inference on A12+ chips. Disable for CPU-only mode to save battery. Prefetch reduces latency by pre-loading tokens.")
        }
    }

    // MARK: - Voice Cloning Section

    private var voiceCloningSection: some View {
        Section {
            Toggle("Enable Voice Cloning", isOn: $viewModel.voiceCloningEnabled)

            if viewModel.voiceCloningEnabled {
                // Reference audio status
                if viewModel.hasReferenceAudio {
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("Reference Audio Loaded")
                                .font(.subheadline)
                            Text(viewModel.referenceAudioFileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.clearReferenceAudio()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack {
                        Image(systemName: "waveform.circle")
                            .foregroundStyle(.secondary)
                        Text("No reference audio selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    viewModel.showAudioPicker = true
                } label: {
                    Label("Select Audio File", systemImage: "folder")
                }

                Button {
                    viewModel.showAudioRecorder = true
                } label: {
                    Label("Record Reference Audio", systemImage: "mic.circle")
                }

                if !viewModel.hasReferenceAudio {
                    Text("Requires 5+ seconds of clear speech")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Voice Cloning")
        } footer: {
            if viewModel.voiceCloningEnabled {
                Text("Clone any voice from a 5-second audio sample. For best results, use clear speech without background noise.")
            } else {
                Text("Enable to use a custom voice based on a reference audio sample.")
            }
        }
        .sheet(isPresented: $viewModel.showAudioPicker) {
            AudioFilePickerView(selectedPath: referenceAudioPathBinding)
        }
        .sheet(isPresented: $viewModel.showAudioRecorder) {
            AudioRecorderView(outputPath: referenceAudioPathBinding)
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section {
            Toggle("Reproducible Output", isOn: $viewModel.useFixedSeed)
                .onChange(of: viewModel.useFixedSeed) {
                    viewModel.saveSettings()
                }

            if viewModel.useFixedSeed {
                Stepper("Seed: \(viewModel.seed)", value: $viewModel.seed, in: 0...999999)
                    .onChange(of: viewModel.seed) {
                        viewModel.saveSettings()
                    }

                Text("Same text + seed = same audio output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Enable reproducible output for identical audio from the same text and settings.")
        }
    }

    // MARK: - Test Section

    private var testSection: some View {
        Section {
            TextField("Test Text", text: $viewModel.testText, axis: .vertical)
                .lineLimit(2...4)

            Button {
                Task {
                    await viewModel.testSynthesis()
                }
            } label: {
                HStack {
                    Label("Test Voice", systemImage: "play.circle")
                    Spacer()
                    if viewModel.isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(viewModel.isTesting || viewModel.modelState != .loaded)

            if let result = viewModel.testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.starts(with: "Error") ? .red : .green)
            }
        } header: {
            Text("Test")
        } footer: {
            if viewModel.modelState != .loaded {
                Text("Load the models first to test synthesis.")
            }
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.resetToDefaults()
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
            }
        }
    }

    // MARK: - Model Info Section

    private var modelInfoSection: some View {
        Section {
            InfoRow(label: "Model Size", value: "\(KyutaiPocketModelInfo.totalSizeMB) MB")
            InfoRow(label: "Sample Rate", value: "\(KyutaiPocketModelInfo.sampleRate / 1000) kHz")
            InfoRow(label: "Word Error Rate", value: String(format: "%.2f%%", KyutaiPocketModelInfo.wordErrorRate * 100))
            InfoRow(label: "Typical Latency", value: "~\(KyutaiPocketModelInfo.typicalLatencyMS) ms")
            InfoRow(label: "Min iOS Version", value: KyutaiPocketModelInfo.minimumIOSVersion)
            InfoRow(label: "License", value: KyutaiPocketModelInfo.license)
        } header: {
            Text("Model Information")
        } footer: {
            Text("Kyutai Pocket TTS is a 100M parameter model from Kyutai (MIT license). Models are bundled with the app for instant use.")
        }
    }
}

// MARK: - Helper Views

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KyutaiPocketSettingsView()
    }
}
