# Accessibility

**Version:** 1.0.0
**Last Updated:** 2026-01-16
**Platform:** iOS (Swift/SwiftUI)

---

## Overview

UnaMentis is designed to be fully accessible, supporting VoiceOver, Dynamic Type, Switch Control, Voice Control, and other iOS accessibility features. This document outlines accessibility requirements and implementation patterns.

---

## Accessibility Standards

### Compliance Targets

- WCAG 2.1 Level AA
- iOS Human Interface Guidelines (Accessibility)
- Apple App Store accessibility requirements

### Key Principles

1. **Perceivable**: All content available to all senses
2. **Operable**: All functions accessible via multiple input methods
3. **Understandable**: Clear, consistent interface
4. **Robust**: Works with current and future assistive technologies

---

## VoiceOver Support

### Navigation

| Element | VoiceOver Behavior |
|---------|-------------------|
| Tab bar | "Session, tab 1 of 5" |
| Back button | "Back, button" |
| List items | "Item name, button" + custom traits |
| Headings | Announced as headings for navigation |

### Custom Labels

```swift
// Bad
Button(action: { }) {
    Image(systemName: "mic.fill")
}

// Good
Button(action: { }) {
    Image(systemName: "mic.fill")
}
.accessibilityLabel("Start session")
.accessibilityHint("Double-tap to begin a voice conversation")
```

### Screen-Specific Announcements

| Screen | Announcement |
|--------|--------------|
| Session (idle) | "Voice Session, idle. Ready to start a conversation." |
| Session (recording) | "Recording. Speak now." |
| Session (playing) | "AI is speaking." |
| Curriculum list | "Curriculum, {N} items" |
| Empty state | "{Title}, {description}" |

### Live Regions

For dynamic content updates:

```swift
Text(statusMessage)
    .accessibilityAddTraits(.updatesFrequently)

// For important announcements
UIAccessibility.post(
    notification: .announcement,
    argument: "Recording stopped"
)
```

### Rotor Support

Custom rotor actions:

| Rotor Item | Action |
|------------|--------|
| Headings | Navigate section headers |
| Buttons | Navigate interactive elements |
| Links | Navigate to external content |
| Custom: Topics | Navigate curriculum topics |

---

## Dynamic Type

### Text Scaling

All text must scale with system text size:

```swift
Text("Session")
    .font(.headline) // Automatically scales
```

### Layout Adaptation

| Text Size | Adaptation |
|-----------|------------|
| xSmall - Large | Standard layout |
| xLarge - xxxLarge | Expanded spacing, stacked layouts |
| Accessibility sizes | Single-column, larger targets |

### Implementation

```swift
@Environment(\.sizeCategory) var sizeCategory

var body: some View {
    if sizeCategory.isAccessibilityCategory {
        // Vertical stack layout
        VStack { content }
    } else {
        // Horizontal layout
        HStack { content }
    }
}
```

### Minimum Sizes

- Body text: 17pt minimum
- Captions: 12pt minimum
- Never use fixed font sizes

---

## Touch Targets

### Minimum Sizes

| Element | Minimum Size |
|---------|--------------|
| Buttons | 44pt × 44pt |
| List rows | 44pt height |
| Tab bar items | 44pt × 44pt |
| Sliders | 44pt height |

### Implementation

```swift
Button("Action") { }
    .frame(minWidth: 44, minHeight: 44)

// Or use padding
Image(systemName: "gear")
    .padding()
    .contentShape(Rectangle())
```

### Touch Target Spacing

Minimum 8pt between adjacent targets.

---

## Reduce Motion

### Respecting User Preference

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

var body: some View {
    Circle()
        .animation(reduceMotion ? .none : .spring(), value: isActive)
}
```

### Affected Animations

| Animation | Standard | Reduced Motion |
|-----------|----------|----------------|
| Tab switching | Slide | Instant |
| Sheet presentation | Slide up | Fade |
| Recording pulse | Pulse | Static |
| Progress bars | Animated | Instant |
| Loading spinners | Spinning | Static or slower |

---

## Color and Contrast

### Contrast Ratios

| Element | Minimum Ratio |
|---------|---------------|
| Body text | 4.5:1 |
| Large text (18pt+) | 3:1 |
| UI components | 3:1 |
| Icons | 3:1 |

### Color Independence

Never convey information through color alone:

```swift
// Bad: Only color indicates error
TextField("Email", text: $email)
    .foregroundColor(isValid ? .primary : .red)

// Good: Color + icon + text
TextField("Email", text: $email)
    .foregroundColor(isValid ? .primary : .red)
if !isValid {
    Label("Invalid email", systemImage: "exclamationmark.circle")
        .foregroundColor(.red)
}
```

### High Contrast Support

```swift
@Environment(\.colorSchemeContrast) var contrast

var backgroundColor: Color {
    contrast == .increased ? .black : .gray
}
```

---

## Switch Control

### Full Functionality

All features accessible via Switch Control:
- Single-switch scanning
- Point scanning
- Head tracking

### Implementation

- All interactive elements focusable
- Logical focus order
- No timing-dependent interactions

### Focus Order

```swift
VStack {
    header
    content
    footer
}
.accessibilityElement(children: .contain)
.accessibilitySortPriority(1)
```

---

## Voice Control

### Supported Commands

| Command | Action |
|---------|--------|
| "Tap [label]" | Activates element |
| "Show names" | Displays element labels |
| "Show numbers" | Displays numbered overlays |
| "Swipe left/right" | Performs swipe |
| "Go back" | Navigates back |

### Element Naming

```swift
Button("Start Session") { }
    .accessibilityLabel("Start Session")
    .accessibilityInputLabels(["Start", "Begin", "Start Session"])
```

---

## Audio & Haptics

### Audio Cues

| Event | Sound |
|-------|-------|
| Recording start | Beep |
| Recording stop | Beep |
| Error | Alert sound |
| Success | Success sound |

### Haptic Feedback

```swift
// Light impact for selection
UIImpactFeedbackGenerator(style: .light).impactOccurred()

// Success notification
UINotificationFeedbackGenerator().notificationOccurred(.success)
```

### Respect System Settings

```swift
@AppStorage("UIAccessibilityIsVoiceOverRunning") var voiceOverRunning = false

// Don't play sounds that conflict with VoiceOver
if !voiceOverRunning {
    playSound()
}
```

---

## Keyboard Support

### iPad Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘1-5 | Switch tabs |
| ⌘N | New item |
| ⌘F | Search |
| ⌘, | Settings |
| Escape | Dismiss/Go back |
| Space | Start/Stop recording |

### Implementation

```swift
.keyboardShortcut("1", modifiers: .command)
.keyboardShortcut(.escape, modifiers: [])
```

### Focus Management

```swift
@FocusState private var isSearchFocused: Bool

TextField("Search", text: $query)
    .focused($isSearchFocused)

Button("Search") {
    isSearchFocused = true
}
```

---

## Testing

### Automated Testing

```swift
func testAccessibility() throws {
    let app = XCUIApplication()
    app.launch()

    // Test VoiceOver labels
    XCTAssertTrue(app.buttons["Start session"].exists)

    // Test element traits
    let header = app.staticTexts["Curriculum"]
    XCTAssertTrue(header.isHeader)
}
```

### Manual Testing Checklist

- [ ] VoiceOver navigation (all screens)
- [ ] Dynamic Type (all sizes)
- [ ] Reduce Motion enabled
- [ ] High Contrast enabled
- [ ] Switch Control scanning
- [ ] Voice Control commands
- [ ] Keyboard navigation (iPad)
- [ ] Color blindness simulation

### Accessibility Inspector

Use Xcode's Accessibility Inspector to:
- Audit accessibility issues
- Test VoiceOver announcements
- Verify contrast ratios
- Check touch target sizes

---

## Common Issues & Solutions

### Issue: Decorative Images Announced

```swift
// Bad
Image("decorative-background")

// Good
Image("decorative-background")
    .accessibilityHidden(true)
```

### Issue: Custom Controls Not Accessible

```swift
// Bad
Rectangle()
    .onTapGesture { toggle() }

// Good
Button(action: toggle) {
    Rectangle()
}
.accessibilityLabel("Toggle")
.accessibilityAddTraits(.isButton)
```

### Issue: State Changes Not Announced

```swift
// Add announcement
func updateStatus(_ newStatus: String) {
    status = newStatus
    UIAccessibility.post(
        notification: .announcement,
        argument: newStatus
    )
}
```

### Issue: Complex Layouts Confusing

```swift
// Group related elements
HStack {
    icon
    VStack {
        title
        subtitle
    }
}
.accessibilityElement(children: .combine)
.accessibilityLabel("\(title), \(subtitle)")
```

---

## Related Documentation

- [09-UI_COMPONENTS.md](09-UI_COMPONENTS.md) - Component accessibility
- [02-SESSION_TAB.md](02-SESSION_TAB.md) - Session accessibility
- [Apple: Accessibility](https://developer.apple.com/accessibility/)
