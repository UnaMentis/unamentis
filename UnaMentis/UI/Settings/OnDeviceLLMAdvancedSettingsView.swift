// UnaMentis - On-Device LLM Advanced Settings View
// Runtime-adjustable "nerd knobs" for experimentation without redeployment
//
// Part of UI/Settings

import SwiftUI

/// Advanced settings for on-device LLM experimentation
///
/// Exposes tunable parameters for:
/// - LLM inference (context window, temperature, GPU layers, threads)
/// - FOV context management (per-buffer token budgets)
/// - Zero-latency response system (canned responses, pre-generation)
/// - Thermal management (monitoring, fallback thresholds)
///
/// All settings persisted via @AppStorage (UserDefaults) for instant effect.
struct OnDeviceLLMAdvancedSettingsView: View {

    // MARK: - LLM Inference Knobs

    @AppStorage("ondevice_llm_contextSize") private var contextSize: Double = 8192
    @AppStorage("ondevice_llm_maxTokens") private var maxTokens: Double = 256
    @AppStorage("ondevice_llm_temperature") private var temperature: Double = 0.7
    @AppStorage("ondevice_llm_gpuLayers") private var gpuLayers: Double = 99
    @AppStorage("ondevice_llm_threads") private var threads: Double = 0 // 0 = auto

    // MARK: - FOV Context Knobs

    @AppStorage("fov_enabled") private var fovEnabled: Bool = true
    @AppStorage("fov_immediateTokens") private var immediateTokens: Double = 1500
    @AppStorage("fov_workingTokens") private var workingTokens: Double = 1500
    @AppStorage("fov_episodicTokens") private var episodicTokens: Double = 600
    @AppStorage("fov_semanticTokens") private var semanticTokens: Double = 400

    // MARK: - Zero-Latency Knobs

    @AppStorage("zerolatency_cannedEnabled") private var cannedEnabled: Bool = true
    @AppStorage("zerolatency_pregenEnabled") private var pregenEnabled: Bool = true
    @AppStorage("zerolatency_pregenMaxTokens") private var pregenMaxTokens: Double = 30
    @AppStorage("zerolatency_pregenCount") private var pregenCount: Double = 3

    // MARK: - Thermal Knobs

    @AppStorage("thermal_monitorEnabled") private var thermalMonitorEnabled: Bool = true
    @AppStorage("thermal_cloudFallback") private var thermalCloudFallback: Bool = true
    @AppStorage("thermal_throttleAtFair") private var thermalThrottleAtFair: Bool = true

    var body: some View {
        List {
            inferenceSection
            fovContextSection
            zeroLatencySection
            thermalSection
            resetSection
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Inference Section

    private var inferenceSection: some View {
        Section {
            // Context Window
            sliderRow(
                label: "Context Window",
                value: $contextSize,
                range: 1024...32768,
                step: 1024,
                format: "%.0f tokens"
            )

            // Max Response Tokens
            sliderRow(
                label: "Max Response Tokens",
                value: $maxTokens,
                range: 32...2048,
                step: 32,
                format: "%.0f"
            )

            // Temperature
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", temperature))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("(\(temperatureDescription))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $temperature, in: 0.0...1.5, step: 0.05) {
                    Text("Temperature")
                }

                HStack {
                    Text("Deterministic")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Creative")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // GPU Layers
            sliderRow(
                label: "GPU Layers",
                value: $gpuLayers,
                range: 0...99,
                step: 1,
                format: "%.0f"
            )

            // Thread Count
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CPU Threads")
                    Spacer()
                    Text(threads == 0 ? "Auto" : String(format: "%.0f", threads))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: $threads, in: 0...8, step: 1) {
                    Text("Threads")
                }

                HStack {
                    Text("Auto")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("8 threads")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("LLM Inference")
        } footer: {
            Text("Context window controls how much conversation history the model sees. GPU layers = 0 runs CPU-only (cooler, slower). Auto threads uses cores minus 2.")
        }
    }

    // MARK: - FOV Context Section

    private var fovContextSection: some View {
        Section {
            Toggle("FOV Context Enabled", isOn: $fovEnabled)

            if fovEnabled {
                sliderRow(
                    label: "Immediate Buffer",
                    value: $immediateTokens,
                    range: 400...4000,
                    step: 100,
                    format: "%.0f tokens"
                )

                sliderRow(
                    label: "Working Buffer",
                    value: $workingTokens,
                    range: 400...4000,
                    step: 100,
                    format: "%.0f tokens"
                )

                sliderRow(
                    label: "Episodic Buffer",
                    value: $episodicTokens,
                    range: 200...2500,
                    step: 100,
                    format: "%.0f tokens"
                )

                sliderRow(
                    label: "Semantic Buffer",
                    value: $semanticTokens,
                    range: 100...1500,
                    step: 50,
                    format: "%.0f tokens"
                )

                HStack {
                    Text("Total FOV Budget")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(immediateTokens + workingTokens + episodicTokens + semanticTokens)) tokens")
                        .font(.subheadline.monospacedDigit())
                }
            }
        } header: {
            Text("FOV Context Management")
        } footer: {
            if fovEnabled {
                Text("Field of View context provides hierarchical detail: full resolution near the current position, compressed summaries further out. Disable to send raw conversation history instead (for A/B testing).")
            } else {
                Text("FOV disabled. Raw conversation history will be sent to the LLM.")
            }
        }
    }

    // MARK: - Zero-Latency Section

    private var zeroLatencySection: some View {
        Section {
            Toggle("Canned Acknowledgments", isOn: $cannedEnabled)

            Toggle("Pre-Generation", isOn: $pregenEnabled)

            if pregenEnabled {
                sliderRow(
                    label: "Pre-Gen Max Tokens",
                    value: $pregenMaxTokens,
                    range: 10...100,
                    step: 5,
                    format: "%.0f"
                )

                sliderRow(
                    label: "Pre-Gen Scenarios",
                    value: $pregenCount,
                    range: 1...5,
                    step: 1,
                    format: "%.0f"
                )
            }
        } header: {
            Text("Zero-Latency Response")
        } footer: {
            Text("Canned acknowledgments play instantly on barge-in. Pre-generation speculatively generates probable response starters during idle time.")
        }
    }

    // MARK: - Thermal Section

    private var thermalSection: some View {
        Section {
            Toggle("Thermal Monitoring", isOn: $thermalMonitorEnabled)

            if thermalMonitorEnabled {
                Toggle("Cloud Fallback at Serious", isOn: $thermalCloudFallback)
                Toggle("Throttle at Fair", isOn: $thermalThrottleAtFair)
            }
        } header: {
            Text("Thermal Management")
        } footer: {
            Text("Monitors ProcessInfo.thermalState. At Fair, reduces max tokens. At Serious, routes to cloud LLM to let the device cool.")
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
            Button("Reset All to Defaults") {
                resetToDefaults()
            }
            .foregroundStyle(.red)
        } footer: {
            Text("Restores all advanced settings to their default values.")
        }
    }

    // MARK: - Helpers

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: step) {
                Text(label)
            }
        }
    }

    private var temperatureDescription: String {
        switch temperature {
        case 0.0: return "Greedy"
        case 0.01..<0.3: return "Focused"
        case 0.3..<0.7: return "Balanced"
        case 0.7..<1.0: return "Creative"
        case 1.0...: return "Wild"
        default: return "Balanced"
        }
    }

    private func resetToDefaults() {
        contextSize = 8192
        maxTokens = 256
        temperature = 0.7
        gpuLayers = 99
        threads = 0
        fovEnabled = true
        immediateTokens = 1500
        workingTokens = 1500
        episodicTokens = 600
        semanticTokens = 400
        cannedEnabled = true
        pregenEnabled = true
        pregenMaxTokens = 30
        pregenCount = 3
        thermalMonitorEnabled = true
        thermalCloudFallback = true
        thermalThrottleAtFair = true
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OnDeviceLLMAdvancedSettingsView()
    }
}
