// UnaMentis - Voice Cloning Views
// Audio file picker and recorder views for voice cloning reference audio
//
// Part of UI/Settings

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Audio File Picker View

/// View for selecting an audio file for voice cloning reference
struct AudioFilePickerView: View {
    @Binding var selectedPath: String
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon and description
                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)

                    Text("Select Reference Audio")
                        .font(.title2.bold())

                    Text("Choose an audio file containing 5+ seconds of clear speech to use as a voice reference.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 32)

                // Supported formats
                VStack(alignment: .leading, spacing: 8) {
                    Text("Supported formats:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(["WAV", "MP3", "M4A", "AAC"], id: \.self) { format in
                            Text(format)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                Spacer()

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }

                // Select file button
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Browse Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Select Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio, .wav, .mp3, .mpeg4Audio, .aiff],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Copy file to app's documents directory for persistent access
            do {
                let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let voiceCloningDir = documentsDir.appendingPathComponent("VoiceCloning", isDirectory: true)

                // Create directory if needed
                try FileManager.default.createDirectory(at: voiceCloningDir, withIntermediateDirectories: true)

                let destURL = voiceCloningDir.appendingPathComponent(url.lastPathComponent)

                // Remove existing file if present
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }

                // Copy file (need to start/stop security-scoped access)
                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "Could not access the selected file"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                try FileManager.default.copyItem(at: url, to: destURL)

                // Validate audio duration
                let asset = AVURLAsset(url: destURL)
                let duration = CMTimeGetSeconds(asset.duration)

                if duration < 5.0 {
                    errorMessage = "Audio must be at least 5 seconds long (got \(String(format: "%.1f", duration))s)"
                    try? FileManager.default.removeItem(at: destURL)
                    return
                }

                selectedPath = destURL.path
                dismiss()

            } catch {
                errorMessage = "Failed to import file: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "Selection failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Audio Recorder View

/// View for recording audio for voice cloning reference
struct AudioRecorderView: View {
    @Binding var outputPath: String
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = AudioRecorderViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Recording visualization
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red.opacity(0.2) : Color.secondary.opacity(0.1))
                        .frame(width: 160, height: 160)

                    Circle()
                        .fill(recorder.isRecording ? Color.red.opacity(0.3) : Color.secondary.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(recorder.isRecording ? 1.0 + CGFloat(recorder.audioLevel) * 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: recorder.audioLevel)

                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(recorder.isRecording ? .red : .blue)
                }
                .padding(.top, 32)

                // Status and duration
                VStack(spacing: 8) {
                    Text(recorder.isRecording ? "Recording..." : "Tap to Record")
                        .font(.title2.bold())

                    Text(recorder.formattedDuration)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(recorder.isRecording ? .red : .primary)

                    if recorder.recordingDuration > 0 && !recorder.isRecording {
                        Text("Recording saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // Instructions
                if !recorder.isRecording && recorder.recordingDuration == 0 {
                    VStack(spacing: 8) {
                        Text("Recording Tips:")
                            .font(.subheadline.bold())

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Speak clearly for 5-15 seconds", systemImage: "clock")
                            Label("Use a quiet environment", systemImage: "speaker.slash")
                            Label("Hold device 6-12 inches away", systemImage: "iphone")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }

                Spacer()

                // Error message
                if let error = recorder.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }

                // Action buttons
                VStack(spacing: 12) {
                    // Record/Stop button
                    Button {
                        if recorder.isRecording {
                            recorder.stopRecording()
                        } else {
                            recorder.startRecording()
                        }
                    } label: {
                        Label(
                            recorder.isRecording ? "Stop Recording" : "Start Recording",
                            systemImage: recorder.isRecording ? "stop.fill" : "mic.fill"
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(recorder.isRecording ? Color.red : Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }

                    // Use recording button (only shown after recording)
                    if recorder.recordingDuration >= 5.0 && !recorder.isRecording {
                        Button {
                            if let path = recorder.recordingPath {
                                outputPath = path
                                dismiss()
                            }
                        } label: {
                            Label("Use This Recording", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                    }

                    // Duration warning
                    if recorder.recordingDuration > 0 && recorder.recordingDuration < 5.0 && !recorder.isRecording {
                        Text("Recording must be at least 5 seconds (\(String(format: "%.1f", recorder.recordingDuration))s recorded)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Record Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.cancelRecording()
                        dismiss()
                    }
                }
            }
            .onAppear {
                recorder.requestPermission()
            }
        }
    }
}

// MARK: - Audio Recorder ViewModel

@MainActor
final class AudioRecorderViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?
    @Published var recordingPath: String?

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var levelTimer: Timer?

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        let tenths = Int((recordingDuration - floor(recordingDuration)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    func requestPermission() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                if !granted {
                    self?.errorMessage = "Microphone access denied. Enable in Settings."
                }
            }
        }
    }

    func startRecording() {
        errorMessage = nil

        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "Failed to configure audio: \(error.localizedDescription)"
            return
        }

        // Create recording URL
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let voiceCloningDir = documentsDir.appendingPathComponent("VoiceCloning", isDirectory: true)
        try? FileManager.default.createDirectory(at: voiceCloningDir, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970)
        let recordingURL = voiceCloningDir.appendingPathComponent("recording_\(timestamp).wav")

        // Recording settings (high quality WAV)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            recordingDuration = 0
            recordingPath = recordingURL.path

            // Start duration timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += 0.1
                }
            }

            // Start level metering
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.audioRecorder?.updateMeters()
                    let level = self?.audioRecorder?.averagePower(forChannel: 0) ?? -160
                    // Normalize from dB (-160 to 0) to 0-1 range
                    self?.audioLevel = max(0, (level + 50) / 50)
                }
            }

        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0
    }

    func cancelRecording() {
        stopRecording()

        // Delete recording file
        if let path = recordingPath {
            try? FileManager.default.removeItem(atPath: path)
        }

        recordingPath = nil
        recordingDuration = 0
    }
}

// MARK: - Preview

#Preview("Audio File Picker") {
    AudioFilePickerView(selectedPath: .constant(""))
}

#Preview("Audio Recorder") {
    AudioRecorderView(outputPath: .constant(""))
}
