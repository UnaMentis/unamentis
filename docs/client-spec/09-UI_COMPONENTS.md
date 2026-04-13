# UI Components

**Version:** 1.0.0
**Last Updated:** 2026-01-16
**Platform:** iOS (Swift/SwiftUI)

---

## Overview

This document catalogs the reusable UI components used throughout the UnaMentis iOS app. Consistent use of these components ensures visual coherence and maintainability.

---

## Design Tokens

### Colors

| Token | Light Mode | Dark Mode | Usage |
|-------|------------|-----------|-------|
| `primary` | #007AFF | #0A84FF | Primary actions, links |
| `secondary` | #5856D6 | #5E5CE6 | Secondary actions |
| `accent` | #FF9500 | #FF9F0A | Highlights, warnings |
| `success` | #34C759 | #32D74B | Success states |
| `error` | #FF3B30 | #FF453A | Error states |
| `background` | #FFFFFF | #000000 | Main background |
| `secondaryBackground` | #F2F2F7 | #1C1C1E | Card backgrounds |
| `text` | #000000 | #FFFFFF | Primary text |
| `secondaryText` | #8E8E93 | #8E8E93 | Secondary text |

### Typography

| Style | Font | Size | Weight | Usage |
|-------|------|------|--------|-------|
| `largeTitle` | System | 34pt | Bold | Screen titles |
| `title1` | System | 28pt | Bold | Section headers |
| `title2` | System | 22pt | Bold | Card titles |
| `title3` | System | 20pt | Semibold | Subsection headers |
| `headline` | System | 17pt | Semibold | Emphasized body |
| `body` | System | 17pt | Regular | Body text |
| `callout` | System | 16pt | Regular | Supplementary text |
| `subheadline` | System | 15pt | Regular | Metadata |
| `footnote` | System | 13pt | Regular | Captions |
| `caption1` | System | 12pt | Regular | Labels |
| `caption2` | System | 11pt | Regular | Small labels |

### Spacing

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4pt | Minimal spacing |
| `sm` | 8pt | Tight spacing |
| `md` | 16pt | Standard spacing |
| `lg` | 24pt | Section spacing |
| `xl` | 32pt | Large gaps |
| `xxl` | 48pt | Major sections |

### Corner Radius

| Token | Value | Usage |
|-------|-------|-------|
| `small` | 8pt | Buttons, pills |
| `medium` | 12pt | Cards, inputs |
| `large` | 16pt | Modals, sheets |
| `full` | 9999pt | Circular elements |

---

## Buttons

### Primary Button

```swift
Button("Start Session") {
    // Action
}
.buttonStyle(PrimaryButtonStyle())
```

Appearance:
- Blue background (#007AFF)
- White text
- 44pt minimum height
- Full width or intrinsic width
- 12pt corner radius

### Secondary Button

```swift
Button("Cancel") {
    // Action
}
.buttonStyle(SecondaryButtonStyle())
```

Appearance:
- Transparent background
- Blue text (#007AFF)
- Blue border
- Same sizing as primary

### Destructive Button

```swift
Button("Delete") {
    // Action
}
.buttonStyle(DestructiveButtonStyle())
```

Appearance:
- Red background (#FF3B30)
- White text
- Used for irreversible actions

### Icon Button

```swift
Button {
    // Action
} label: {
    Image(systemName: "gear")
}
.buttonStyle(IconButtonStyle())
```

Appearance:
- 44pt tap target
- Icon only
- Subtle background on press

### Microphone Button

Custom component for voice recording:

```swift
MicrophoneButton(
    state: $recordingState,
    onTap: { /* toggle */ },
    onLongPress: { /* push-to-talk */ }
)
```

States:
- Idle: Blue with mic icon
- Recording: Red with pulsing animation
- Processing: Gray with spinner
- Disabled: Grayed out

---

## Cards

### Basic Card

```swift
CardView {
    // Content
}
```

Appearance:
- White background (dark: #1C1C1E)
- 12pt corner radius
- Subtle shadow
- 16pt internal padding

### Curriculum Card

```swift
CurriculumCard(
    curriculum: curriculum,
    progress: 0.5
)
```

Components:
- Icon or emoji
- Title
- Subtitle (topic count)
- Progress bar
- Disclosure indicator

### Session Card

```swift
SessionCard(session: session)
```

Components:
- Topic title
- Curriculum name
- Duration
- Turn count
- Timestamp

### Stat Card

```swift
StatCard(
    value: "42",
    label: "Sessions",
    icon: "chart.bar"
)
```

Components:
- Large value
- Label
- Optional icon
- Optional trend indicator

---

## Lists

### Standard List

```swift
List {
    ForEach(items) { item in
        ListRow(item: item)
    }
}
.listStyle(.insetGrouped)
```

Styling:
- Inset grouped by default
- Separator between rows
- Section headers supported

### List Row

```swift
ListRow(
    title: "Newton's Laws",
    subtitle: "Physics",
    leading: Image(systemName: "book"),
    trailing: Image(systemName: "chevron.right")
)
```

Components:
- Leading icon/image
- Title
- Subtitle
- Trailing accessory

### Swipe Actions

```swift
ListRow(item: item)
    .swipeActions(edge: .trailing) {
        Button("Delete", role: .destructive) { }
    }
    .swipeActions(edge: .leading) {
        Button("Complete") { }
            .tint(.green)
    }
```

---

## Form Elements

### Text Field

```swift
TextField("API Key", text: $apiKey)
    .textFieldStyle(RoundedTextFieldStyle())
```

Appearance:
- Gray background
- 12pt corner radius
- 44pt height
- Clear button when not empty

### Secure Field

```swift
SecureField("Password", text: $password)
    .textFieldStyle(RoundedTextFieldStyle())
```

Same as text field with password masking.

### Toggle

```swift
Toggle("Enable Notifications", isOn: $enabled)
    .toggleStyle(SwitchToggleStyle(tint: .blue))
```

Standard iOS toggle with custom tint.

### Picker

```swift
Picker("Voice", selection: $selectedVoice) {
    ForEach(voices) { voice in
        Text(voice.name).tag(voice)
    }
}
.pickerStyle(.menu)
```

Styles:
- Menu (default)
- Segmented (for few options)
- Wheel (for many options)

### Slider

```swift
Slider(value: $speed, in: 0.5...2.0, step: 0.25)
    .accentColor(.blue)
```

Used for speed, volume, etc.

---

## Navigation

### Navigation Bar

```swift
NavigationStack {
    ContentView()
        .navigationTitle("Curriculum")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") { }
            }
        }
}
```

### Tab Bar

```swift
TabView(selection: $selectedTab) {
    SessionView()
        .tabItem {
            Label("Session", systemImage: "waveform")
        }
        .tag(Tab.session)
    // ...
}
```

Custom tab bar with:
- 5 tabs
- SF Symbols icons
- Selection indicator

### Back Button

Standard iOS back button with custom behavior if needed.

---

## Feedback

### Progress Indicator

```swift
ProgressView()
    .progressViewStyle(CircularProgressViewStyle())
```

Types:
- Circular (indeterminate)
- Linear (determinate)
- Custom (branded)

### Progress Bar

```swift
ProgressBar(value: 0.5)
```

Appearance:
- 8pt height
- Rounded ends
- Animated fill

### Toast/Snackbar

```swift
Toast(
    message: "Session saved",
    type: .success
)
```

Types:
- Success (green)
- Error (red)
- Warning (orange)
- Info (blue)

### Empty State

```swift
EmptyStateView(
    icon: "book",
    title: "No Curricula",
    message: "Import a curriculum to get started.",
    action: ("Import", { })
)
```

Components:
- Large icon
- Title
- Description
- Optional action button

---

## Overlays

### Sheet

```swift
.sheet(isPresented: $showSheet) {
    SheetContent()
}
```

Presentation:
- Slides up from bottom
- Drag to dismiss
- Detents supported (medium, large)

### Alert

```swift
.alert("Delete Session?", isPresented: $showAlert) {
    Button("Cancel", role: .cancel) { }
    Button("Delete", role: .destructive) { }
}
```

Standard iOS alert style.

### Confirmation Dialog

```swift
.confirmationDialog("Options", isPresented: $showOptions) {
    Button("Edit") { }
    Button("Share") { }
    Button("Delete", role: .destructive) { }
}
```

Action sheet style.

---

## Animations

### Standard Transitions

```swift
.transition(.opacity)
.transition(.slide)
.transition(.scale)
.transition(.move(edge: .bottom))
```

### Custom Animations

```swift
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
.animation(.easeInOut(duration: 0.2), value: state)
```

### Reduce Motion

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

.animation(reduceMotion ? .none : .default, value: state)
```

---

## Accessibility

### All Components Support

- VoiceOver labels and hints
- Dynamic Type scaling
- Minimum 44pt touch targets
- High contrast support
- Reduce motion respect

### Component Examples

```swift
Button("Start") { }
    .accessibilityLabel("Start learning session")
    .accessibilityHint("Double-tap to begin a voice conversation")

ProgressBar(value: 0.5)
    .accessibilityLabel("Progress")
    .accessibilityValue("50 percent")
```

---

## Related Documentation

- [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md) - Navigation patterns
- [10-ACCESSIBILITY.md](10-ACCESSIBILITY.md) - Full accessibility guide
