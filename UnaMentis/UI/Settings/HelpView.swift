// UnaMentis - Help View
// In-app help following iOS best practices
//
// Provides user guidance for voice commands and app features

import SwiftUI

/// Main help view with organized sections for app features
public struct HelpView: View {
    public init() {}

    public var body: some View {
        List {
            // Voice Commands Section - Primary feature
            Section {
                NavigationLink {
                    VoiceCommandsHelpView()
                } label: {
                    HelpRow(
                        icon: "waveform.circle.fill",
                        iconColor: .blue,
                        title: "Siri Voice Commands",
                        subtitle: "Control UnaMentis hands-free"
                    )
                }
            } header: {
                Text("Getting Started")
            } footer: {
                Text("Use Siri to start conversations and lessons without touching your phone.")
            }

            // Learning Section
            Section("Learning") {
                NavigationLink {
                    FreeformChatHelpView()
                } label: {
                    HelpRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        iconColor: .green,
                        title: "Voice Conversations",
                        subtitle: "Spontaneous learning sessions"
                    )
                }

                NavigationLink {
                    CurriculumHelpView()
                } label: {
                    HelpRow(
                        icon: "book.fill",
                        iconColor: .orange,
                        title: "Curriculum Lessons",
                        subtitle: "Structured topic-based learning"
                    )
                }
            }

            // Reading List Section
            Section("Reading List") {
                NavigationLink {
                    ReadingListHelpView()
                } label: {
                    HelpRow(
                        icon: "book.pages.fill",
                        iconColor: .indigo,
                        title: "Reading List",
                        subtitle: "Import and listen to documents"
                    )
                }
            }

            // Knowledge Bowl Section
            Section("Knowledge Bowl") {
                NavigationLink {
                    KBHelpSheet()
                } label: {
                    HelpRow(
                        icon: "trophy.fill",
                        iconColor: .yellow,
                        title: "Knowledge Bowl Training",
                        subtitle: "Competition prep and strategy"
                    )
                }
            }

            // Tips Section
            Section("Tips") {
                NavigationLink {
                    HandsFreeHelpView()
                } label: {
                    HelpRow(
                        icon: "hand.raised.slash.fill",
                        iconColor: .purple,
                        title: "Hands-Free Learning",
                        subtitle: "Learn while walking or exercising"
                    )
                }
            }

            // Settings Section
            Section("Settings Reference") {
                NavigationLink {
                    SettingsHelpView()
                } label: {
                    HelpRow(
                        icon: "gearshape.fill",
                        iconColor: .gray,
                        title: "Settings Guide",
                        subtitle: "Detailed explanation of all settings"
                    )
                }
            }
        }
        .navigationTitle("Help")
    }
}

// MARK: - Voice Commands Help

struct VoiceCommandsHelpView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("UnaMentis responds to Siri voice commands, letting you start learning sessions without touching your phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Start a Conversation") {
                VoiceCommandRow(command: "Hey Siri, talk to UnaMentis")
                VoiceCommandRow(command: "Hey Siri, chat with UnaMentis")
                VoiceCommandRow(command: "Hey Siri, start a conversation with UnaMentis")

                Text("Opens the app and immediately starts a voice session. Perfect for spontaneous questions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section("Start a Lesson") {
                VoiceCommandRow(command: "Hey Siri, start a lesson in UnaMentis")
                VoiceCommandRow(command: "Hey Siri, teach me about Physics in UnaMentis")
                VoiceCommandRow(command: "Hey Siri, study Quantum Mechanics with UnaMentis")

                Text("Starts a structured lesson from your curriculum library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section("Resume & Progress") {
                VoiceCommandRow(command: "Hey Siri, resume learning in UnaMentis")
                VoiceCommandRow(command: "Hey Siri, continue my lesson in UnaMentis")
                VoiceCommandRow(command: "Hey Siri, show my progress in UnaMentis")

                Text("Pick up where you left off or check your learning statistics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("First Time Setup", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium))

                    Text("After installing UnaMentis, open it once so Siri can recognize the voice commands. You may need to wait a few minutes for Siri to learn the new shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Voice Commands")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Freeform Chat Help

struct FreeformChatHelpView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Voice conversations let you explore any topic spontaneously. Just start talking and the AI will respond.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("How It Works") {
                HelpStepRow(number: 1, text: "Say \"Hey Siri, talk to UnaMentis\" or tap the microphone button")
                HelpStepRow(number: 2, text: "Wait for the session to start (you'll see the waveform indicator)")
                HelpStepRow(number: 3, text: "Ask any question or request to learn about a topic")
                HelpStepRow(number: 4, text: "The AI responds with voice, and you can continue the conversation naturally")
            }

            Section("Tips") {
                Label("Speak clearly and at a normal pace", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green, .primary)
                Label("You can interrupt the AI by speaking", systemImage: "hand.raised.fill")
                    .foregroundStyle(.orange, .primary)
                Label("Sessions work offline with on-device AI", systemImage: "wifi.slash")
                    .foregroundStyle(.blue, .primary)
            }
        }
        .navigationTitle("Voice Conversations")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Curriculum Help

struct CurriculumHelpView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Curriculum lessons provide structured learning with topics organized into courses. Each lesson covers specific concepts with visual aids.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Starting a Lesson") {
                HelpStepRow(number: 1, text: "Go to the Curriculum tab")
                HelpStepRow(number: 2, text: "Browse or search for a topic")
                HelpStepRow(number: 3, text: "Tap a topic to start the lesson")
                HelpStepRow(number: 4, text: "Or say \"Hey Siri, teach me about [topic] in UnaMentis\"")
            }

            Section("During a Lesson") {
                Label("Progress bar shows your position in the lesson", systemImage: "chart.bar.fill")
                Label("Visual aids appear when relevant", systemImage: "photo.fill")
                Label("Pause/resume controls at the bottom", systemImage: "playpause.fill")
                Label("Ask questions anytime by speaking", systemImage: "bubble.left.fill")
            }

            Section("Tracking Progress") {
                Text("Your mastery level is tracked for each topic. Complete lessons to improve your mastery percentage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Curriculum Lessons")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Hands-Free Help

struct HandsFreeHelpView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("UnaMentis is designed for hands-free learning. Start a session with Siri and continue without ever touching your phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Perfect For") {
                HandsFreeUseCase(icon: "figure.walk", title: "Walking", description: "Learn during your daily walk or commute")
                HandsFreeUseCase(icon: "car.fill", title: "Driving", description: "Safe, voice-only interaction while driving")
                HandsFreeUseCase(icon: "dumbbell.fill", title: "Exercise", description: "Keep your mind active during workouts")
                HandsFreeUseCase(icon: "house.fill", title: "Housework", description: "Learn while doing chores")
            }

            Section("Best Practices") {
                Label("Use AirPods or headphones for best audio", systemImage: "airpodspro")
                Label("Position phone within speaking distance", systemImage: "iphone.gen3.radiowaves.left.and.right")
                Label("Reduce background noise when possible", systemImage: "speaker.wave.2.fill")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Quick Start", systemImage: "bolt.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.yellow)

                    Text("Just say \"Hey Siri, talk to UnaMentis\" and start asking questions. No setup required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Hands-Free Learning")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Reading List Help

struct ReadingListHelpView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(HelpContent.ReadingList.overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Importing Content") {
                HelpStepRow(number: 1, text: "Tap the + button in the Reading List tab")
                HelpStepRow(number: 2, text: "Choose \"Import File\" for PDFs, text, or markdown")
                HelpStepRow(number: 3, text: "Or choose \"Import URL\" to paste a web article link")
                HelpStepRow(number: 4, text: "The document is processed into audio segments automatically")

                Text(HelpContent.ReadingList.formats)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section("Listening to Documents") {
                HelpStepRow(number: 1, text: "Tap the headphones icon on any item to start playback")
                HelpStepRow(number: 2, text: "Text appears on screen as each segment plays")
                HelpStepRow(number: 3, text: "Use skip controls to jump between segments")
                HelpStepRow(number: 4, text: "Tap the menu button to add bookmarks")

                Text(HelpContent.ReadingList.bookmarks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section("PDF Images") {
                Label("Images are extracted from PDFs automatically", systemImage: "photo.fill")
                    .foregroundStyle(.indigo, .primary)
                Label("Images appear alongside text during playback", systemImage: "text.below.photo.fill")
                    .foregroundStyle(.blue, .primary)
                Label("Tap any image to view it fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.green, .primary)

                Text("Images are mapped to the closest text segment so they appear at the right time during listening.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section("Managing Items") {
                Label("Swipe right to mark complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green, .primary)
                Label("Swipe left to archive or delete", systemImage: "archivebox.fill")
                    .foregroundStyle(.gray, .primary)
                Label("Tap an item to read it as text", systemImage: "doc.text")
                    .foregroundStyle(.blue, .primary)
                Label("Pull down to refresh your list", systemImage: "arrow.clockwise")
                    .foregroundStyle(.blue, .primary)
            }
        }
        .navigationTitle("Reading List")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Helper Views

struct HelpRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

struct VoiceCommandRow: View {
    let command: String

    var body: some View {
        HStack {
            Image(systemName: "mic.fill")
                .foregroundStyle(.blue)
                .font(.caption)

            Text(command)
                .font(.subheadline.monospaced())
        }
        .padding(.vertical, 2)
        .accessibilityLabel("Voice command: \(command)")
    }
}

struct HelpStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}

struct HandsFreeUseCase: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

// MARK: - Settings Help

struct SettingsHelpView: View {
    var body: some View {
        List {
            // Audio Settings
            Section("Audio Settings") {
                SettingsHelpItem(
                    title: "Sample Rate",
                    details: """
                    Audio quality setting that affects bandwidth and sound quality:
                    • 16 kHz: Lower quality, less data usage
                    • 24 kHz: Balanced quality and bandwidth (recommended)
                    • 48 kHz: Highest quality, more data usage
                    """
                )

                SettingsHelpItem(
                    title: "Voice Processing",
                    details: "Enhances voice clarity using Apple's audio processing. Keep enabled unless troubleshooting audio issues."
                )

                SettingsHelpItem(
                    title: "Echo Cancellation",
                    details: "Prevents the microphone from picking up the AI's voice playing through speakers. Essential when not using headphones."
                )

                SettingsHelpItem(
                    title: "Noise Suppression",
                    details: "Filters background noise like fans, traffic, or keyboard sounds. Keep enabled in noisy environments."
                )
            }

            // Voice Detection
            Section("Voice Detection (VAD)") {
                SettingsHelpItem(
                    title: "VAD Threshold",
                    details: """
                    How sensitive voice detection is:
                    • Lower (0.3): Detects quieter speech, may pick up noise
                    • Higher (0.9): Requires clearer speech, ignores noise

                    Start at 0.5 and adjust based on your environment.
                    """
                )

                SettingsHelpItem(
                    title: "Interruption Threshold",
                    details: """
                    How loud you need to speak to interrupt the AI:
                    • Lower values: Easier to interrupt
                    • Higher values: Requires deliberate speech to interrupt

                    Higher values prevent accidental interruptions from background noise.
                    """
                )

                SettingsHelpItem(
                    title: "Enable Interruptions",
                    details: "When enabled, speaking while the AI talks will pause the AI so it can listen to you. Disable for lecture-style sessions where you prefer not to interrupt."
                )
            }

            // Speech Recognition
            Section("Speech Recognition (STT)") {
                SettingsHelpItem(
                    title: "STT Provider",
                    details: """
                    Speech recognition service options:
                    • GLM-ASR (On-Device): Free, private, works offline
                    • Deepgram Nova-3: Cloud-based, fast, highly accurate
                    • AssemblyAI: Cloud-based, good accuracy
                    • Apple Speech: On-device, good for iOS, free
                    """
                )
            }

            // Language Model
            Section("Language Model (LLM)") {
                SettingsHelpItem(
                    title: "LLM Provider",
                    details: """
                    Language model for AI responses:
                    • On-Device: Free, private, works offline (slower)
                    • Anthropic Claude: High quality reasoning, paid
                    • OpenAI: Fast and versatile, paid
                    • Self-Hosted: Free with your own Ollama server
                    """
                )

                SettingsHelpItem(
                    title: "Model Selection",
                    details: "Specific model to use. Larger models are smarter but slower and more expensive. Smaller models are faster and cheaper but may be less capable."
                )

                SettingsHelpItem(
                    title: "Temperature",
                    details: """
                    Controls response creativity:
                    • 0.0: Factual, deterministic responses
                    • 0.5: Balanced (recommended for learning)
                    • 1.0: Creative, varied responses

                    Use lower values for factual topics, higher for creative discussions.
                    """
                )

                SettingsHelpItem(
                    title: "Max Tokens",
                    details: """
                    Maximum response length (1 token ≈ 4 characters):
                    • 256: Short, concise answers
                    • 1024: Detailed explanations (recommended)
                    • 4096: Very long, comprehensive responses

                    Longer responses cost more and take more time to generate.
                    """
                )
            }

            // Text-to-Speech
            Section("Text-to-Speech (TTS)") {
                SettingsHelpItem(
                    title: "TTS Provider",
                    details: """
                    Text-to-speech voice options:
                    • Apple TTS: Free, on-device, functional but robotic
                    • Piper: Free with self-hosted server, natural sounding
                    • VibeVoice: Free with self-hosted server, high quality
                    • ElevenLabs: Paid, very natural and expressive
                    • Deepgram Aura: Paid, fast and clear
                    """
                )

                SettingsHelpItem(
                    title: "Speaking Rate",
                    details: """
                    How fast the AI speaks:
                    • 0.5x: Half speed (good for complex topics)
                    • 1.0x: Normal conversational speed
                    • 2.0x: Double speed (good for review)
                    """
                )
            }

            // Presets
            Section("Presets") {
                SettingsHelpItem(
                    title: "Configuration Presets",
                    details: """
                    Quick configurations for different use cases:
                    • Balanced: Good quality and reasonable speed
                    • Low Latency: Fastest possible responses
                    • High Quality: Best audio and AI quality
                    • Cost Optimized: Minimize API costs
                    • Self-Hosted: Use your own servers for privacy
                    """
                )
            }

            // Self-Hosted
            Section("Self-Hosted") {
                SettingsHelpItem(
                    title: "Self-Hosted Mode",
                    details: "Run AI services on your own Mac for free, unlimited usage with full privacy. Requires setting up Ollama and optionally Piper or VibeVoice on your computer."
                )

                SettingsHelpItem(
                    title: "Server IP",
                    details: "Enter your Mac's IP address (e.g., 192.168.1.100) or hostname (e.g., macbook.local). The app connects to Ollama on port 11434."
                )
            }
        }
        .navigationTitle("Settings Guide")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Helper view for settings help items
struct SettingsHelpItem: View {
    let title: String
    let details: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(details)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(details)")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HelpView()
    }
}

#Preview("Settings Help") {
    NavigationStack {
        SettingsHelpView()
    }
}

#Preview("Voice Commands") {
    NavigationStack {
        VoiceCommandsHelpView()
    }
}
