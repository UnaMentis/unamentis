// UnaMentis - Help Components
// Reusable UI components for in-app help, tooltips, and documentation
//
// Provides accessible, native help throughout the application

import SwiftUI

// MARK: - Info Button with Popover

/// A small info button that shows a help popover when tapped
/// Usage: InfoButton(title: "Temperature", help: HelpContent.Settings.temperature)
struct InfoButton: View {
    let title: String
    let content: String
    var learnMoreURL: URL?

    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Help for \(title)")
        .accessibilityHint("Double-tap to learn more about \(title)")
        .popover(isPresented: $showingPopover) {
            HelpPopoverContent(
                title: title,
                content: content,
                learnMoreURL: learnMoreURL
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Content view for help popovers
/// Note: Keep tooltip content brief (2-3 sentences max). For detailed help, use the Help section.
struct HelpPopoverContent: View {
    let title: String
    let content: String
    var learnMoreURL: URL?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close help")
            }

            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let url = learnMoreURL {
                Link(destination: url) {
                    HStack {
                        Text("Learn More")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
        .frame(minWidth: 280, maxWidth: 340)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(content)")
    }
}

// MARK: - Inline Help Text

/// Subtle inline help text that appears below a control
struct InlineHelp: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(text)
    }
}

// MARK: - Help Section Header

/// A section header with an info button
struct HelpSectionHeader: View {
    let title: String
    let helpTitle: String
    let helpContent: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            InfoButton(title: helpTitle, content: helpContent)
        }
    }
}

// MARK: - Setting Row with Help

/// A setting row that includes an info button for context
struct SettingRowWithHelp<Content: View>: View {
    let title: String
    let helpContent: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(title)
            InfoButton(title: title, content: helpContent)
            Spacer()
            content()
        }
    }
}

// MARK: - Slider with Help

/// A slider control with title, value display, and help button
struct SliderWithHelp: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let helpContent: String
    var valueFormatter: ((Double) -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                InfoButton(title: title, content: helpContent)
                Spacer()
                Text(formattedValue)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(formattedValue)
                .accessibilityHint(helpContent)
        }
    }

    private var formattedValue: String {
        if let formatter = valueFormatter {
            return formatter(value)
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - Feature Tooltip

/// A tooltip that can be attached to any view to explain a feature
struct FeatureTooltip: ViewModifier {
    let title: String
    let message: String
    let showOnFirstAppear: Bool

    @State private var showingTooltip = false
    @AppStorage private var hasShownTooltip: Bool

    init(title: String, message: String, showOnFirstAppear: Bool = false, storageKey: String) {
        self.title = title
        self.message = message
        self.showOnFirstAppear = showOnFirstAppear
        self._hasShownTooltip = AppStorage(wrappedValue: false, "tooltip_shown_\(storageKey)")
    }

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.5) {
                showingTooltip = true
            }
            .popover(isPresented: $showingTooltip) {
                TooltipContent(title: title, message: message)
                    .presentationCompactAdaptation(.popover)
            }
            .onAppear {
                if showOnFirstAppear && !hasShownTooltip {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showingTooltip = true
                        hasShownTooltip = true
                    }
                }
            }
    }
}

struct TooltipContent: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.yellow)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 260, maxWidth: 320)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip: \(title). \(message)")
    }
}

extension View {
    /// Adds a tooltip that shows on long press
    func featureTooltip(title: String, message: String, showOnFirstAppear: Bool = false, storageKey: String) -> some View {
        modifier(FeatureTooltip(title: title, message: message, showOnFirstAppear: showOnFirstAppear, storageKey: storageKey))
    }
}

// MARK: - Quick Help Card

/// A card that displays help information prominently
struct QuickHelpCard: View {
    let icon: String
    let title: String
    let description: String
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

// MARK: - Contextual Help Banner

/// A dismissible banner that provides contextual help at the top of a screen
struct ContextualHelpBanner: View {
    let message: String
    let storageKey: String

    @AppStorage private var isDismissed: Bool

    init(message: String, storageKey: String) {
        self.message = message
        self.storageKey = storageKey
        self._isDismissed = AppStorage(wrappedValue: false, "help_banner_dismissed_\(storageKey)")
    }

    var body: some View {
        if !isDismissed {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss tip")
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.yellow.opacity(0.1))
            }
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tip: \(message)")
        }
    }
}

// MARK: - Help Content Storage

/// Centralized storage for all help text content
/// Organized by screen and feature for easy maintenance
enum HelpContent {

    // MARK: - Session View Help
    enum Session {
        static let overview = """
        This is your voice conversation interface. Speak naturally and the AI will respond.
        """

        static let statusIndicator = """
        Shows the conversation state: gray (idle), green (listening), orange (thinking), blue (speaking), or yellow (interrupted).
        """

        static let progressBar = """
        Shows your progress through the current lesson. Each segment represents a topic or concept being covered.
        """

        static let vuMeter = """
        Shows audio levels. Blue indicates AI speaking, green indicates your voice. Higher bars mean louder audio.
        """

        static let interrupt = """
        You can interrupt the AI at any time by simply speaking. The AI will pause and listen to your question or comment.
        """

        static let visualAssets = """
        Visual aids appear when they help explain a concept. They sync with the audio narration automatically.
        """

        static let pauseResume = """
        Pause to take a break without ending the session. Resume to continue where you left off.
        """

        static let latencyMetric = """
        Response latency shows how quickly the system responds. Lower is better. Target: under 500ms.
        """

        static let costMetric = """
        Estimated cost for this session based on API usage. On-device and self-hosted options are free.
        """
    }

    // MARK: - Curriculum View Help
    enum Curriculum {
        static let overview = """
        Browse and select structured learning content. Each curriculum contains multiple topics organized for progressive learning.
        """

        static let curriculumVsTopic = """
        A Curriculum is a complete course containing multiple Topics. Each Topic is a focused lesson on a specific concept.
        """

        static let mastery = """
        Mastery percentage reflects your understanding based on study time, correct answers, and content covered.
        """

        static let topicStatus = """
        Tracks whether a topic is not started, in progress, completed, or being reviewed for reinforcement.
        """

        static let importing = """
        Import curricula from the server or load built-in sample content for testing.
        """

        static let startLesson = """
        Tap "Start Lesson" to begin a voice-guided session. The AI will speak first, introducing the topic.
        """
    }

    // MARK: - History View Help
    enum History {
        static let overview = """
        Review your past learning sessions. Each entry shows duration, turn count, and cost.
        """

        static let turns = """
        A "turn" is one exchange: you speak, then the AI responds. More turns indicate a longer, more interactive conversation.
        """

        static let avgLatency = """
        Average response time for this session. Lower latency means faster, more natural conversations.
        """

        static let totalCost = """
        Total API costs for this session. Includes speech recognition, language model, and text-to-speech fees.
        """

        static let export = """
        Export your session history as JSON for backup or analysis.
        """
    }

    // MARK: - Analytics View Help
    enum Analytics {
        static let overview = """
        Track your learning progress and system performance metrics. Use this data to optimize your experience.
        """

        static let sttLatency = """
        Speech-to-Text (STT) latency measures how long it takes to convert your speech to text. Target: under 150ms.
        """

        static let llmTTFT = """
        Time-To-First-Token (TTFT) measures how quickly the language model starts generating a response. Target: under 200ms.
        """

        static let ttsTTFB = """
        Time-To-First-Byte (TTFB) measures how quickly text-to-speech audio starts playing. Target: under 100ms.
        """

        static let e2eLatency = """
        End-to-End latency is the total time from when you stop speaking to when you hear a response. Target: under 500ms (median), under 1000ms (P99).
        """

        static let medianVsP99 = """
        Median is the typical response time; P99 is the worst-case (99% of responses are faster).
        """

        static let costPerHour = """
        Estimated hourly cost based on your usage patterns. Use on-device or self-hosted providers to reduce costs.
        """

        static let interruptions = """
        Times you interrupted the AI while it was speaking. Interruptions are normal and show active engagement.
        """

        static let throttleEvents = """
        Times the device reduced performance due to heat. High counts may indicate the device needs to cool down.
        """
    }

    // MARK: - Settings Help
    enum Settings {
        // Audio Section
        static let sampleRate = """
        Audio quality setting. 24 kHz is recommended for balanced quality and bandwidth usage.
        """

        static let voiceProcessing = """
        Enhances voice clarity using Apple's audio processing. Keep enabled unless troubleshooting.
        """

        static let echoCancellation = """
        Prevents the microphone from picking up the AI's voice playing through speakers. Essential when not using headphones.
        """

        static let noiseSuppression = """
        Filters background noise like fans, traffic, or keyboard sounds. Keep enabled in noisy environments.
        """

        // VAD Section
        static let vadThreshold = """
        Voice detection sensitivity. Lower values detect quieter speech but may pick up noise. Start at 0.5 and adjust.
        """

        static let interruptionThreshold = """
        How loud you need to speak to interrupt the AI. Higher values prevent accidental interruptions.
        """

        static let enableInterruptions = """
        When enabled, speaking while the AI talks will pause the AI so it can listen to you. Disable for lecture-style sessions where you prefer not to interrupt.
        """

        // STT Section
        static let sttProvider = """
        Speech recognition service. On-device options are free and private; cloud options offer higher accuracy.
        """

        // LLM Section
        static let llmProvider = """
        Language model for AI responses. On-device is free and private; cloud options offer higher quality.
        """

        static let llmModel = """
        Specific model to use. Larger models are smarter but slower and more expensive. Smaller models are faster and cheaper.
        """

        static let temperature = """
        Controls response creativity. Lower values (0.0) are factual; higher values (1.0) are more creative. 0.5 is recommended.
        """

        static let maxTokens = """
        Maximum response length. 1024 tokens recommended for detailed explanations. Longer responses cost more.
        """

        // TTS Section
        static let ttsProvider = """
        Text-to-speech service. Apple TTS is free on-device; self-hosted and cloud options sound more natural.
        """

        static let ttsVoice = """
        Choose the AI's voice. Different voices have different characteristics and personalities.
        """

        static let speakingRate = """
        How fast the AI speaks. 1.0x is normal; use slower for complex topics or faster for review.
        """

        // Presets Section
        static let presets = """
        Quick configurations optimized for different priorities: speed, quality, cost, or self-hosted privacy.
        """

        // Self-Hosted Section
        static let selfHosted = """
        Run AI services on your own Mac for free, unlimited usage with full privacy. Requires setting up Ollama and optionally Piper/VibeVoice on your computer.
        """

        static let serverIP = """
        Enter your Mac's IP address or hostname (e.g., 192.168.1.100 or macbook.local). The app will connect to Ollama on port 11434.
        """
    }

    // MARK: - Reading List Help
    enum ReadingList {
        static let overview = """
        Import PDFs, text files, markdown, or web articles and listen to them read aloud with AI-powered text-to-speech.
        """

        static let importing = """
        Tap the + button to import documents. Supported formats: PDF, plain text, markdown, and web URLs. PDFs are chunked into audio segments automatically.
        """

        static let playback = """
        Tap the headphones icon to listen. Use skip controls to move between segments, and add bookmarks to save your place.
        """

        static let inlineImages = """
        Images extracted from PDFs appear alongside the text as each segment plays. Tap an image to view it fullscreen.
        """

        static let bookmarks = """
        Add bookmarks during playback to save your place. Access saved bookmarks from the menu button in the top right.
        """

        static let formats = """
        Supported formats: PDF (with image extraction and OCR), plain text, markdown (formatting stripped for natural speech), and web URLs (article text extracted automatically).
        """

        static let progress = """
        Swipe right on an item to mark it complete. Swipe left to archive or delete. Your reading position is saved automatically.
        """
    }

    // MARK: - General Help
    enum General {
        static let onboarding = """
        Learn through voice conversations with AI. Configure settings, import a curriculum, and start a lesson.
        """

        static let accessibility = """
        UnaMentis supports VoiceOver and other accessibility features. All controls have descriptive labels and hints.
        """
    }
}

// MARK: - Previews

#Preview("Info Button") {
    VStack(spacing: 20) {
        HStack {
            Text("Temperature")
            InfoButton(title: "Temperature", content: HelpContent.Settings.temperature)
        }

        SliderWithHelp(
            title: "Speaking Rate",
            value: .constant(1.0),
            range: 0.5...2.0,
            step: 0.1,
            helpContent: HelpContent.Settings.speakingRate,
            valueFormatter: { String(format: "%.1fx", $0) }
        )
    }
    .padding()
}

#Preview("Quick Help Card") {
    QuickHelpCard(
        icon: "waveform.circle.fill",
        title: "Voice Commands",
        description: "Use Siri to start learning sessions hands-free.",
        action: {},
        actionLabel: "Learn More"
    )
    .padding()
}

#Preview("Contextual Help Banner") {
    VStack {
        ContextualHelpBanner(
            message: "Tip: Long press any setting to see a helpful explanation.",
            storageKey: "preview_banner"
        )
        Spacer()
    }
}
