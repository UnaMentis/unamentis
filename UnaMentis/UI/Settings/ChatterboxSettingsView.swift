// UnaMentis - Chatterbox Settings View
// Advanced settings UI for Chatterbox TTS provider
//
// Part of UI/Settings

import SwiftUI

/// Advanced settings view for Chatterbox TTS provider
///
/// Exposes all Chatterbox "nerd knobs" for experimentation:
/// - Emotion control (exaggeration, CFG weight)
/// - Speed control
/// - Paralinguistic tags
/// - Multilingual language selection
/// - Streaming mode
/// - Seed for reproducibility
struct ChatterboxSettingsView: View {

    @StateObject private var viewModel = ChatterboxSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Connection Status
            connectionStatusSection

            // Quick Presets
            presetsSection

            // Emotion Control
            emotionControlSection

            // Speed Control
            speedSection

            // Paralinguistic Tags
            paralinguisticTagsSection

            // Multilingual Support
            multilingualSection

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
        }
        .navigationTitle("Chatterbox Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task {
                await viewModel.checkServerHealth()
            }
        }
    }

    // MARK: - Connection Status Section

    private var connectionStatusSection: some View {
        Section {
            HStack {
                Label("Server Status", systemImage: viewModel.isServerReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(viewModel.isServerReachable ? .green : .red)
                Spacer()
                if let lastCheck = viewModel.lastHealthCheck {
                    Text(lastCheck, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isMultilingualAvailable {
                HStack {
                    Label("Multilingual Model", systemImage: "globe")
                        .foregroundStyle(.blue)
                    Spacer()
                    Text("Available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    await viewModel.checkServerHealth()
                }
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Connection")
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
            Text("Presets configure emotion and speed settings. Adjusting sliders switches to Custom.")
        }
    }

    // MARK: - Emotion Control Section

    private var emotionControlSection: some View {
        Section {
            // Exaggeration slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Exaggeration")
                    Spacer()
                    Text(String(format: "%.2f", viewModel.exaggeration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("(\(viewModel.exaggerationDescription))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $viewModel.exaggeration, in: 0.0...1.5, step: 0.05) {
                    Text("Exaggeration")
                } onEditingChanged: { _ in
                    viewModel.onSliderValueChanged()
                }

                HStack {
                    Text("Monotone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Dramatic")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // CFG Weight slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CFG Weight")
                    Spacer()
                    Text(String(format: "%.2f", viewModel.cfgWeight))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("(\(viewModel.cfgWeightDescription))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $viewModel.cfgWeight, in: 0.0...1.0, step: 0.05) {
                    Text("CFG Weight")
                } onEditingChanged: { _ in
                    viewModel.onSliderValueChanged()
                }

                HStack {
                    Text("Creative")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Controlled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Emotion Control")
        } footer: {
            Text("Exaggeration controls expressiveness. CFG Weight controls generation fidelity. Lower CFG works better for fast or dramatic speech.")
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

    // MARK: - Paralinguistic Tags Section

    private var paralinguisticTagsSection: some View {
        Section {
            Toggle("Enable Paralinguistic Tags", isOn: $viewModel.enableParalinguisticTags)

            if viewModel.enableParalinguisticTags {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supported tags:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(ChatterboxParalinguisticTag.allCases, id: \.self) { tag in
                        HStack {
                            Text(tag.rawValue)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)

                            Text(tag.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Natural Reactions")
        } footer: {
            Text("When enabled, tags like [laugh] or [sigh] in the text will trigger natural vocal reactions.")
        }
    }

    // MARK: - Multilingual Section

    private var multilingualSection: some View {
        Section {
            Toggle("Use Multilingual Model", isOn: $viewModel.useMultilingual)
                .disabled(!viewModel.isMultilingualAvailable && !viewModel.useMultilingual)

            if viewModel.useMultilingual {
                Picker("Language", selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.availableLanguages, id: \.self) { language in
                        HStack {
                            Text(language.displayName)
                            Text(language.nativeName)
                                .foregroundStyle(.secondary)
                        }
                        .tag(language)
                    }
                }
                .pickerStyle(.navigationLink)
            }
        } header: {
            Text("Multilingual")
        } footer: {
            if !viewModel.isMultilingualAvailable {
                Text("Multilingual model not detected on server. Install chatterbox-multilingual to enable.")
            } else {
                Text("The multilingual model (500M) supports 23 languages. The Turbo model (350M) is English-only but faster.")
            }
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        Section {
            Toggle("Streaming Mode", isOn: $viewModel.useStreaming)

            HStack {
                Image(systemName: viewModel.useStreaming ? "waveform.path" : "doc.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(viewModel.useStreaming ? "Streaming" : "Non-Streaming")
                        .font(.subheadline)
                    Text(viewModel.useStreaming ? "~472ms to first audio, progressive delivery" : "Complete audio returned at once")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Performance")
        } footer: {
            Text("Streaming mode delivers audio progressively for lower perceived latency. Non-streaming returns complete audio in one response.")
        }
    }

    // MARK: - Voice Cloning Section

    private var voiceCloningSection: some View {
        Section {
            // Voice cloning toggle
            Toggle("Enable Voice Cloning", isOn: $viewModel.voiceCloningEnabled)

            if viewModel.voiceCloningEnabled {
                // Current reference audio status
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

                // Select audio file button
                Button {
                    viewModel.showAudioPicker = true
                } label: {
                    Label("Select Audio File", systemImage: "folder")
                }

                // Record audio button
                Button {
                    viewModel.showAudioRecorder = true
                } label: {
                    Label("Record Reference Audio", systemImage: "mic.circle")
                }

                // Duration requirement note
                if !viewModel.hasReferenceAudio {
                    Text("Requires 5+ seconds of clear speech for best results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Voice Cloning")
        } footer: {
            if viewModel.voiceCloningEnabled {
                Text("Zero-shot voice cloning uses a reference audio sample to match the voice style. For best results, use clear speech without background noise.")
            } else {
                Text("Enable to use a custom voice based on a reference audio sample.")
            }
        }
        .sheet(isPresented: $viewModel.showAudioPicker) {
            AudioFilePickerView(selectedPath: $viewModel.referenceAudioPath)
        }
        .sheet(isPresented: $viewModel.showAudioRecorder) {
            AudioRecorderView(outputPath: $viewModel.referenceAudioPath)
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section {
            Toggle("Reproducible Output", isOn: $viewModel.useFixedSeed)

            if viewModel.useFixedSeed {
                Stepper("Seed: \(viewModel.seed)", value: $viewModel.seed, in: 0...999999)

                Text("Same text + seed = same audio output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Enable reproducible output to get identical audio from the same text and settings. Useful for testing and comparison.")
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
            .disabled(viewModel.isTesting || !viewModel.isServerReachable)

            if let result = viewModel.testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.starts(with: "Error") ? .red : .green)
            }
        } header: {
            Text("Test")
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
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatterboxSettingsView()
    }
}
