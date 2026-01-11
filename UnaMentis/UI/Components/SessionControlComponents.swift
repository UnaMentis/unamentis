// UnaMentis - Session Control Components
// Reusable session control buttons for tutoring and curriculum interfaces
//
// Part of UI/UX (TDD Section 10)

import SwiftUI

// MARK: - Slide to Stop Button

/// A slide gesture button where user must hold and slide to stop the session.
/// This prevents accidental stops during tutoring sessions.
///
/// Standard iOS pattern: user must drag the thumb across the track to confirm action.
public struct SlideToStopButton: View {
    /// Callback when slide action completes
    let onStop: () -> Void

    /// Current drag offset
    @State private var dragOffset: CGFloat = 0

    /// Whether the button is being dragged
    @State private var isDragging: Bool = false

    /// Track width (computed from geometry)
    @State private var trackWidth: CGFloat = 200

    /// Thumb size
    private let thumbSize: CGFloat = 44

    /// Padding inside the track
    private let trackPadding: CGFloat = 4

    /// Completion threshold (percentage of track)
    private let completionThreshold: CGFloat = 0.85

    /// Maximum drag distance
    private var maxDragDistance: CGFloat {
        trackWidth - thumbSize - (trackPadding * 2)
    }

    /// Current completion percentage (0-1)
    private var completionProgress: CGFloat {
        guard maxDragDistance > 0 else { return 0 }
        return max(0, min(1, dragOffset / maxDragDistance))
    }

    /// Whether the drag has passed the completion threshold
    private var isComplete: Bool {
        completionProgress >= completionThreshold
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }

    public var body: some View {
        GeometryReader { geometry in
            let calculatedWidth = min(geometry.size.width, 280)

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: calculatedWidth, height: thumbSize + (trackPadding * 2))

                // Progress fill (shows slide progress)
                Capsule()
                    .fill(Color.red.opacity(0.3))
                    .frame(
                        width: dragOffset + thumbSize + trackPadding,
                        height: thumbSize + (trackPadding * 2)
                    )
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: dragOffset)

                // Instruction text (fades as user slides)
                HStack {
                    Spacer()
                    Text("Slide to Stop")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.red.opacity(1 - completionProgress))
                    Spacer()
                }
                .frame(width: calculatedWidth)

                // Thumb
                Circle()
                    .fill(Color.red)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color.red.opacity(0.3), radius: isDragging ? 8 : 4)
                    .scaleEffect(isDragging ? 1.1 : 1.0)
                    .offset(x: trackPadding + dragOffset)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                let newOffset = max(0, min(maxDragDistance, value.translation.width))
                                dragOffset = newOffset
                            }
                            .onEnded { _ in
                                isDragging = false
                                if isComplete {
                                    // Trigger haptic feedback and complete
                                    triggerSuccessFeedback()
                                    onStop()
                                    // Reset after completion
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                } else {
                                    // Snap back to start
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(width: calculatedWidth, height: thumbSize + (trackPadding * 2))
            .onAppear {
                trackWidth = calculatedWidth
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                trackWidth = min(newWidth, 280)
            }
        }
        .frame(height: thumbSize + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide to stop session")
        .accessibilityHint("Slide right to end the tutoring session")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func triggerSuccessFeedback() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}

// MARK: - Session Mute Button

/// A button to mute the microphone during sessions.
/// When muted, the user can listen without risk of barge-in or triggering speech detection.
public struct SessionMuteButton: View {
    /// Whether the microphone is muted
    @Binding var isMuted: Bool

    /// Optional callback when mute state changes
    var onMuteChanged: ((Bool) -> Void)?

    /// Button size
    private let buttonSize: CGFloat = 44

    public init(isMuted: Binding<Bool>, onMuteChanged: ((Bool) -> Void)? = nil) {
        self._isMuted = isMuted
        self.onMuteChanged = onMuteChanged
    }

    public var body: some View {
        Button {
            isMuted.toggle()
            onMuteChanged?(isMuted)
            triggerFeedback()
        } label: {
            ZStack {
                Circle()
                    .fill(isMuted ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isMuted ? .red : .secondary)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isMuted)
        .accessibilityLabel(isMuted ? "Microphone muted" : "Microphone on")
        .accessibilityHint(isMuted ? "Double-tap to unmute microphone" : "Double-tap to mute microphone")
        .accessibilityAddTraits(.isButton)
    }

    private func triggerFeedback() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Session Pause Button

/// A button to pause/resume the session.
/// When paused, all audio stops and session state is preserved.
public struct SessionPauseButton: View {
    /// Whether the session is paused
    @Binding var isPaused: Bool

    /// Callback when pause state changes
    var onPauseChanged: ((Bool) -> Void)?

    /// Button size
    private let buttonSize: CGFloat = 50

    public init(isPaused: Binding<Bool>, onPauseChanged: ((Bool) -> Void)? = nil) {
        self._isPaused = isPaused
        self.onPauseChanged = onPauseChanged
    }

    public var body: some View {
        Button {
            isPaused.toggle()
            onPauseChanged?(isPaused)
            triggerFeedback()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: buttonSize, height: buttonSize)
                    .shadow(color: Color.blue.opacity(0.4), radius: 6)

                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPaused)
        .accessibilityLabel(isPaused ? "Resume session" : "Pause session")
        .accessibilityHint(isPaused ? "Double-tap to resume the tutoring session" : "Double-tap to pause the tutoring session")
        .accessibilityAddTraits(.isButton)
    }

    private func triggerFeedback() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Shared Haptic Feedback

#if os(iOS)
/// Shared haptic feedback generators for curriculum control buttons
@MainActor
private enum HapticFeedback {
    static let light = UIImpactFeedbackGenerator(style: .light)
    static let medium = UIImpactFeedbackGenerator(style: .medium)
}
#endif

// MARK: - Go Back Segment Button

/// A button to go back one segment in curriculum playback.
/// Like a rewind button, allows user to replay the previous segment.
@MainActor
public struct GoBackSegmentButton: View {
    /// Whether the button is enabled (can go back)
    let isEnabled: Bool

    /// Callback when button is tapped
    let action: @MainActor () -> Void

    /// Button size
    private let buttonSize: CGFloat = 44

    public init(isEnabled: Bool, action: @escaping @MainActor () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: {
            action()
            triggerFeedback()
        }) {
            ZStack {
                Circle()
                    .fill(isEnabled ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: "gobackward.10")
                    .font(.system(size: 18))
                    .foregroundStyle(isEnabled ? .blue : .gray.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Go back one segment")
        .accessibilityHint("Replays the previous segment of the lesson")
        .accessibilityAddTraits(.isButton)
    }

    @MainActor
    private func triggerFeedback() {
        #if os(iOS)
        HapticFeedback.light.impactOccurred()
        #endif
    }
}

// MARK: - Replay Topic Button

/// A button to replay the entire current topic from the beginning.
@MainActor
public struct ReplayTopicButton: View {
    /// Callback when button is tapped
    let action: @MainActor () -> Void

    /// Button size
    private let buttonSize: CGFloat = 44

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: {
            action()
            triggerFeedback()
        }) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replay topic")
        .accessibilityHint("Starts the current topic from the beginning")
        .accessibilityAddTraits(.isButton)
    }

    @MainActor
    private func triggerFeedback() {
        #if os(iOS)
        HapticFeedback.medium.impactOccurred()
        #endif
    }
}

// MARK: - Next Topic Button

/// A button to skip to the next topic in the curriculum.
@MainActor
public struct NextTopicButton: View {
    /// Whether the button is enabled (has next topic)
    let isEnabled: Bool

    /// Title of the next topic (for accessibility)
    let nextTopicTitle: String?

    /// Callback when button is tapped
    let action: @MainActor () -> Void

    /// Button size
    private let buttonSize: CGFloat = 44

    public init(isEnabled: Bool, nextTopicTitle: String? = nil, action: @escaping @MainActor () -> Void) {
        self.isEnabled = isEnabled
        self.nextTopicTitle = nextTopicTitle
        self.action = action
    }

    public var body: some View {
        Button(action: {
            action()
            triggerFeedback()
        }) {
            ZStack {
                Circle()
                    .fill(isEnabled ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isEnabled ? .green : .gray.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(isEnabled ? "Next topic\(nextTopicTitle.map { ": \($0)" } ?? "")" : "No next topic")
        .accessibilityHint(isEnabled ? "Skips to the next topic in the curriculum" : "This is the last topic in the curriculum")
        .accessibilityAddTraits(.isButton)
    }

    @MainActor
    private func triggerFeedback() {
        #if os(iOS)
        HapticFeedback.medium.impactOccurred()
        #endif
    }
}

// MARK: - Session Control Bar

/// A low-profile control bar for tutoring sessions containing all session controls.
/// Positioned at the bottom of the screen during active sessions.
public struct SessionControlBar: View {
    /// Whether the session is paused
    @Binding var isPaused: Bool

    /// Whether the microphone is muted
    @Binding var isMuted: Bool

    /// Callback when stop action completes
    let onStop: () -> Void

    /// Callback when pause state changes
    var onPauseChanged: ((Bool) -> Void)?

    /// Callback when mute state changes
    var onMuteChanged: ((Bool) -> Void)?

    public init(
        isPaused: Binding<Bool>,
        isMuted: Binding<Bool>,
        onStop: @escaping () -> Void,
        onPauseChanged: ((Bool) -> Void)? = nil,
        onMuteChanged: ((Bool) -> Void)? = nil
    ) {
        self._isPaused = isPaused
        self._isMuted = isMuted
        self.onStop = onStop
        self.onPauseChanged = onPauseChanged
        self.onMuteChanged = onMuteChanged
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Mute button (left)
            SessionMuteButton(isMuted: $isMuted, onMuteChanged: onMuteChanged)

            // Pause button (center-left)
            SessionPauseButton(isPaused: $isPaused, onPauseChanged: onPauseChanged)

            // Slide to stop (center-right, takes remaining space)
            SlideToStopButton(onStop: onStop)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session controls")
    }
}

// MARK: - Curriculum Control Bar

/// A control bar for curriculum playback with segment navigation.
/// Extends SessionControlBar with go-back, replay, and next topic buttons.
@MainActor
public struct CurriculumControlBar: View {
    /// Whether the session is paused
    @Binding var isPaused: Bool

    /// Whether the microphone is muted
    @Binding var isMuted: Bool

    /// Current segment index (for enabling go-back button)
    let currentSegmentIndex: Int

    /// Whether there is a next topic available
    let hasNextTopic: Bool

    /// Title of the next topic (for accessibility)
    let nextTopicTitle: String?

    /// Callback when stop action completes
    let onStop: @MainActor () -> Void

    /// Callback when go-back button is tapped
    let onGoBack: @MainActor () -> Void

    /// Callback when replay button is tapped
    let onReplay: @MainActor () -> Void

    /// Callback when next topic button is tapped
    let onNextTopic: @MainActor () -> Void

    /// Callback when pause state changes
    var onPauseChanged: (@MainActor (Bool) -> Void)?

    /// Callback when mute state changes
    var onMuteChanged: (@MainActor (Bool) -> Void)?

    public init(
        isPaused: Binding<Bool>,
        isMuted: Binding<Bool>,
        currentSegmentIndex: Int,
        hasNextTopic: Bool,
        nextTopicTitle: String? = nil,
        onStop: @escaping @MainActor () -> Void,
        onGoBack: @escaping @MainActor () -> Void,
        onReplay: @escaping @MainActor () -> Void,
        onNextTopic: @escaping @MainActor () -> Void,
        onPauseChanged: (@MainActor (Bool) -> Void)? = nil,
        onMuteChanged: (@MainActor (Bool) -> Void)? = nil
    ) {
        self._isPaused = isPaused
        self._isMuted = isMuted
        self.currentSegmentIndex = currentSegmentIndex
        self.hasNextTopic = hasNextTopic
        self.nextTopicTitle = nextTopicTitle
        self.onStop = onStop
        self.onGoBack = onGoBack
        self.onReplay = onReplay
        self.onNextTopic = onNextTopic
        self.onPauseChanged = onPauseChanged
        self.onMuteChanged = onMuteChanged
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Navigation controls row
            HStack(spacing: 20) {
                // Go back one segment
                GoBackSegmentButton(
                    isEnabled: currentSegmentIndex > 0,
                    action: onGoBack
                )

                // Replay topic from beginning
                ReplayTopicButton(action: onReplay)

                // Skip to next topic
                NextTopicButton(
                    isEnabled: hasNextTopic,
                    nextTopicTitle: nextTopicTitle,
                    action: onNextTopic
                )
            }

            // Standard session controls row
            HStack(spacing: 16) {
                // Mute button
                SessionMuteButton(isMuted: $isMuted, onMuteChanged: onMuteChanged)

                // Pause button
                SessionPauseButton(isPaused: $isPaused, onPauseChanged: onPauseChanged)

                // Slide to stop
                SlideToStopButton(onStop: onStop)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Curriculum playback controls")
    }
}

// MARK: - Previews

#Preview("Slide to Stop") {
    VStack(spacing: 40) {
        Text("Slide to Stop Button")
            .font(.headline)

        SlideToStopButton {
            print("Stop triggered!")
        }
        .padding(.horizontal, 40)
    }
    .padding()
}

#Preview("Mute Button") {
    struct PreviewWrapper: View {
        @State private var isMuted = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Mute Button")
                    .font(.headline)
                Text(isMuted ? "Muted" : "Unmuted")
                    .foregroundStyle(.secondary)
                SessionMuteButton(isMuted: $isMuted)
            }
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("Pause Button") {
    struct PreviewWrapper: View {
        @State private var isPaused = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Pause Button")
                    .font(.headline)
                Text(isPaused ? "Paused" : "Playing")
                    .foregroundStyle(.secondary)
                SessionPauseButton(isPaused: $isPaused)
            }
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("Session Control Bar") {
    struct PreviewWrapper: View {
        @State private var isPaused = false
        @State private var isMuted = false

        var body: some View {
            VStack {
                Spacer()
                Text("Session in progress...")
                    .foregroundStyle(.secondary)
                Spacer()

                SessionControlBar(
                    isPaused: $isPaused,
                    isMuted: $isMuted,
                    onStop: {
                        print("Session stopped!")
                    },
                    onPauseChanged: { paused in
                        print("Pause changed: \(paused)")
                    },
                    onMuteChanged: { muted in
                        print("Mute changed: \(muted)")
                    }
                )
                .padding()
            }
        }
    }

    return PreviewWrapper()
}
