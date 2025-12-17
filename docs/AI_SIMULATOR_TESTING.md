# AI-Driven iOS Simulator Testing Guide

**Purpose:** Guide for using Claude Code with the iOS Simulator MCP server to autonomously test and iterate on VoiceLearn iOS.

**Last Updated:** December 2025

---

## Table of Contents

1. [Overview](#1-overview)
2. [MCP Server Setup](#2-mcp-server-setup)
3. [Available Capabilities](#3-available-capabilities)
4. [Testing Workflow](#4-testing-workflow)
5. [Common Operations](#5-common-operations)
6. [Limitations](#6-limitations)
7. [Best Practices](#7-best-practices)

---

## 1. Overview

### 1.1 What is AI Simulator Testing?

VoiceLearn uses the **ios-simulator-mcp** server to enable Claude Code to directly interact with the iOS Simulator. This allows:

- **Autonomous UI testing** - Navigate, tap, type without human intervention
- **Visual verification** - Take screenshots to verify UI state
- **Iterative development** - Make changes, test, iterate automatically
- **Regression testing** - Verify UI changes haven't broken existing features

### 1.2 What Can Be Tested

| Feature | AI Testable | Notes |
|---------|-------------|-------|
| UI Navigation | Yes | Tap, swipe, scroll |
| Form Input | Yes | Type text, select options |
| Visual Layout | Yes | Screenshot comparison |
| Curriculum Display | Yes | Verify topics, progress |
| Settings | Yes | Configure options |
| History View | Yes | Verify session history |
| Analytics View | Yes | Check charts, data |
| Voice Features | Limited | Requires human for real speech |
| API Responses | Limited | Can verify UI after mock responses |

### 1.3 What Requires Human Testing

- **Real voice input** - Microphone requires human speech
- **Audio output quality** - TTS playback needs human evaluation
- **Accessibility** - VoiceOver testing with real screen reader
- **Haptic feedback** - Physical device required

---

## 2. MCP Server Setup

### 2.1 Installation

The ios-simulator-mcp server is already installed:

```bash
# Already added to project config
claude mcp add ios-simulator npx ios-simulator-mcp
```

Configuration stored in: `/Users/ramerman/.claude.json`

### 2.2 Verification

After restarting Claude Code, verify the MCP server is active:

1. Check for new tools in Claude's capabilities
2. Try listing available simulators
3. Boot a simulator

### 2.3 Requirements

- **Node.js** - Required for npx
- **Xcode** - Provides simctl
- **iOS Simulator** - Included with Xcode

---

## 3. Available Capabilities

### 3.1 Simulator Management

| Capability | Description |
|------------|-------------|
| List simulators | Get available simulator devices |
| Boot simulator | Start a simulator by name/UDID |
| Shutdown simulator | Stop a running simulator |
| Get simulator state | Check if booted/shutdown |

### 3.2 App Operations

| Capability | Description |
|------------|-------------|
| Install app | Install .app bundle |
| Launch app | Start app by bundle ID |
| Terminate app | Stop running app |
| Uninstall app | Remove app from simulator |

### 3.3 UI Interactions

| Capability | Description |
|------------|-------------|
| Tap | Tap at coordinates (x, y) |
| Long press | Press and hold |
| Swipe | Swipe in direction |
| Type text | Enter text input |
| Press button | Hardware buttons (home, lock) |

### 3.4 Screen Capture

| Capability | Description |
|------------|-------------|
| Screenshot | Capture current screen |
| Record video | Record simulator screen |
| Get UI hierarchy | Accessibility element tree |

### 3.5 Accessibility Inspection

| Capability | Description |
|------------|-------------|
| Get elements | List all UI elements |
| Find element | Search by label/identifier |
| Get element properties | Position, size, value |

---

## 4. Testing Workflow

### 4.1 Standard Testing Cycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    AI Testing Workflow                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. BUILD                                                       │
│     ├─ xcodebuild -scheme VoiceLearn                           │
│     └─ Verify build succeeds                                    │
│                                                                 │
│  2. PREPARE                                                     │
│     ├─ Boot simulator (iPhone 17 Pro)                          │
│     ├─ Install app                                              │
│     └─ Launch app                                               │
│                                                                 │
│  3. TEST                                                        │
│     ├─ Take screenshot (verify initial state)                  │
│     ├─ Perform UI actions (tap, type, swipe)                   │
│     ├─ Take screenshot (verify result)                         │
│     └─ Repeat for each test case                               │
│                                                                 │
│  4. EVALUATE                                                    │
│     ├─ Compare screenshots to expected state                   │
│     ├─ Check for visual regressions                            │
│     └─ Verify data displays correctly                          │
│                                                                 │
│  5. ITERATE                                                     │
│     ├─ If issues found: make code changes                      │
│     ├─ Rebuild app                                              │
│     └─ Return to step 2                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Example Test Session

**Goal:** Verify curriculum view displays topics correctly

```
1. Build the app
   → xcodebuild build -scheme VoiceLearn

2. Boot simulator
   → ios-simulator: boot "iPhone 17 Pro"

3. Install and launch
   → ios-simulator: install /path/to/VoiceLearn.app
   → ios-simulator: launch com.voicelearn.VoiceLearn

4. Navigate to Curriculum
   → ios-simulator: screenshot (capture home screen)
   → ios-simulator: tap on "Curriculum" tab (find coordinates)

5. Verify display
   → ios-simulator: screenshot (capture curriculum view)
   → Analyze: Are topics showing? Is progress visible?

6. Test interaction
   → ios-simulator: tap on first topic
   → ios-simulator: screenshot (verify topic detail)

7. Document results
   → Note any issues found
   → Create todo items for fixes
```

### 4.3 Regression Testing

When making UI changes:

1. **Before changes:** Take baseline screenshots
2. **Make changes:** Edit SwiftUI views
3. **After rebuild:** Take new screenshots
4. **Compare:** Verify expected changes, no regressions

---

## 5. Common Operations

### 5.1 Building the App

```bash
# Debug build for simulator
xcodebuild build \
    -scheme VoiceLearn \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug

# Find the built app
find ~/Library/Developer/Xcode/DerivedData -name "VoiceLearn.app" -type d
```

### 5.2 Simulator Commands

```bash
# List available simulators
xcrun simctl list devices

# Boot specific simulator
xcrun simctl boot "iPhone 17 Pro"

# Install app
xcrun simctl install booted /path/to/VoiceLearn.app

# Launch app
xcrun simctl launch booted com.voicelearn.VoiceLearn

# Take screenshot
xcrun simctl io booted screenshot screenshot.png

# Open URL in app
xcrun simctl openurl booted "voicelearn://curriculum/topic1"
```

### 5.3 Finding UI Elements

To interact with UI, you need coordinates. Methods:

1. **Accessibility inspection** - Get element positions from UI hierarchy
2. **Manual calculation** - Use known screen dimensions
3. **Screenshot analysis** - Claude can analyze images to find elements

### 5.4 Handling Different Screen Sizes

| Device | Screen Size | Scale |
|--------|-------------|-------|
| iPhone 17 Pro | 393 x 852 | 3x |
| iPhone 17 Pro Max | 430 x 932 | 3x |
| iPhone SE 3 | 375 x 667 | 2x |

Adjust tap coordinates based on device.

---

## 6. Limitations

### 6.1 What the AI Cannot Do

| Limitation | Reason | Workaround |
|------------|--------|------------|
| Voice input | No microphone | Use mock audio or text input |
| Evaluate audio | No hearing | User must evaluate TTS quality |
| Physical gestures | Simulator limitation | Use simctl commands |
| Real network | May need VPN | Configure test endpoints |
| Push notifications | Requires setup | Use local notifications |

### 6.2 Simulator vs Device Differences

| Aspect | Simulator | Real Device |
|--------|-----------|-------------|
| Performance | Slower | Accurate |
| Neural Engine | Not available | Full support |
| Camera/Mic | Simulated | Real hardware |
| Thermal | No throttling | Real thermal behavior |
| Battery | N/A | Real battery drain |

### 6.3 MCP Server Limitations

- **No complex gestures** - Multi-touch limited
- **Coordinate-based** - Must know exact tap locations
- **One simulator at a time** - Sequential testing
- **Latency** - Commands have round-trip time

---

## 7. Best Practices

### 7.1 Test Structure

1. **Start clean** - Fresh simulator state for each test session
2. **Take screenshots liberally** - Document each step
3. **Use accessibility identifiers** - Add to SwiftUI views for reliable element finding
4. **Handle async** - Wait for UI updates after actions

### 7.2 Accessibility Identifiers

Add identifiers to SwiftUI views for easier testing:

```swift
Button("Start Session") {
    viewModel.startSession()
}
.accessibilityIdentifier("start-session-button")

Text(topic.title)
    .accessibilityIdentifier("topic-title-\(topic.id)")
```

### 7.3 Error Recovery

When tests fail:

1. **Take screenshot** - Capture error state
2. **Check logs** - Console output
3. **Restart clean** - Kill app, relaunch
4. **Document** - Note what failed and why

### 7.4 Parallel Development

While AI tests UI:

- User can work on voice features (requires real speech)
- AI handles visual regression testing
- Both can commit to same branch (coordinate changes)

### 7.5 CI Integration

For automated testing in CI:

```yaml
# .github/workflows/ui-tests.yml
- name: Boot Simulator
  run: xcrun simctl boot "iPhone 17 Pro"

- name: Run UI Tests
  run: xcodebuild test -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## Test Scenarios

### A. Navigation Tests

| Test | Steps | Expected |
|------|-------|----------|
| Tab navigation | Tap each tab | Correct view displays |
| Back navigation | Tap back button | Returns to previous |
| Deep linking | Open URL | Navigates to content |

### B. Curriculum Tests

| Test | Steps | Expected |
|------|-------|----------|
| List topics | Open Curriculum | Topics listed |
| Topic detail | Tap topic | Detail view shows |
| Progress display | Check progress | Correct percentages |

### C. Settings Tests

| Test | Steps | Expected |
|------|-------|----------|
| Change preset | Select preset | Settings update |
| API key entry | Enter key | Key saved |
| Toggle switch | Tap toggle | State changes |

### D. History Tests

| Test | Steps | Expected |
|------|-------|----------|
| View history | Open History | Sessions listed |
| Session detail | Tap session | Detail displays |
| Export | Tap export | Share sheet appears |

---

## Troubleshooting

### Issue: Simulator won't boot

```bash
# Kill all simulators
killall "Simulator"

# Reset simulator
xcrun simctl erase all

# Try booting again
xcrun simctl boot "iPhone 17 Pro"
```

### Issue: App won't install

```bash
# Check app is built
ls ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug-iphonesimulator/*.app

# Uninstall first
xcrun simctl uninstall booted com.voicelearn.VoiceLearn

# Install again
xcrun simctl install booted /path/to/VoiceLearn.app
```

### Issue: Tap not registering

1. Verify coordinates are within screen bounds
2. Check element is visible (not hidden or off-screen)
3. Wait for animations to complete
4. Try longer tap (100ms+)

### Issue: Screenshots are blank

```bash
# Ensure simulator is in foreground
open -a Simulator

# Take screenshot with full path
xcrun simctl io booted screenshot ~/Desktop/screenshot.png
```

---

## Related Documentation

- [TESTING.md](TESTING.md) - General testing guide
- [DEBUG_TESTING_UI.md](DEBUG_TESTING_UI.md) - Built-in debug tools
- [SETUP.md](SETUP.md) - Development setup

---

**Document History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | December 2025 | Claude | Initial document |
