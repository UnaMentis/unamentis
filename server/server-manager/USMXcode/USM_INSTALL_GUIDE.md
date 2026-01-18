# USM (UnaMentis Server Manager) - Definitive Install Guide

## Overview

USM is a macOS menu bar app (MenuBarExtra) that manages UnaMentis services. It runs as an LSUIElement (no Dock icon) and provides an API server on port 8767.

**Bundle ID:** `com.unamentis.server-manager2`

---

## Complete Uninstall

Run these steps in order before a fresh install:

### 1. Quit Application Gracefully
```bash
# CORRECT: Graceful quit via AppleScript
osascript -e 'tell application "USM" to quit'

# Only if unresponsive (last resort):
killall USM 2>/dev/null
```

### 2. Remove App Bundles
```bash
rm -rf /Applications/USM.app
rm -rf ~/Applications/USM.app
```

### 3. Remove Xcode Build Artifacts
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/USM-*
rm -rf "$PROJECT_ROOT/server/server-manager/USMXcode/build"  # Or use relative path from repo root
```

### 4. Clear Preferences
```bash
defaults delete com.unamentis.server-manager 2>/dev/null
defaults delete com.unamentis.server-manager2 2>/dev/null
```

### 5. Remove LaunchAgents (if any)
```bash
rm -f ~/Library/LaunchAgents/com.unamentis.server-manager*.plist
```

### 6. Unregister from Launch Services (CRITICAL)

First, find all registered paths:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -B20 "com.unamentis.server-manager" | grep "path:"
```

Then unregister each path found:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/path/to/USM.app"
```

Verify removal (should return 0):
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -c "com.unamentis.server-manager"
```

### 7. Restart System UI
```bash
killall SystemUIServer ControlCenter cfprefsd 2>/dev/null
```

### 8. Verify Clean State
- Check System Settings > Menu Bar - USM should not appear
- If USM still appears after all above steps, reboot

---

## Build

### Prerequisites
- Xcode installed
- XcodeBuildMCP configured

### Build Steps

1. **Set MCP session defaults:**
```
mcp__XcodeBuildMCP__session-set-defaults({
  projectPath: "$PROJECT_ROOT/server/server-manager/USMXcode/USM.xcodeproj",
  scheme: "USM"
})
```
Note: Replace `$PROJECT_ROOT` with your actual repository path.

2. **Build for macOS:**
```
mcp__XcodeBuildMCP__build_macos()
```

3. **Get the built app path:**
```
mcp__XcodeBuildMCP__get_mac_app_path()
```

The app will be at:
`~/Library/Developer/Xcode/DerivedData/USM-{hash}/Build/Products/Debug/USM.app`

---

## Install

### Option A: Run from DerivedData (Development)
```bash
open ~/Library/Developer/Xcode/DerivedData/USM-*/Build/Products/Debug/USM.app
```

### Option B: Install to /Applications (Production)
```bash
cp -R ~/Library/Developer/Xcode/DerivedData/USM-*/Build/Products/Debug/USM.app /Applications/
open /Applications/USM.app
```

---

## Verify Installation

1. **Check process is running:**
```bash
pgrep -f "USM.app"
```

2. **Check API server responds:**
```bash
curl -s http://localhost:8767/api/health
```
Expected: `{"status": "ok", "service": "USM API Server", "port": 8767}`

3. **Check menu bar icon appears** (look for "UM" icon in menu bar)

4. **Check System Settings > Menu Bar** - USM should be listed with toggle ON

---

## Troubleshooting

### App exits immediately
- Check LSUIElement setting in `Config/Shared.xcconfig`
- Temporarily set `INFOPLIST_KEY_LSUIElement = NO` to debug (shows in Dock)

### Menu bar icon doesn't appear
- Verify `MenuBarIcon.imageset` exists in Assets.xcassets
- Check System Settings > Menu Bar - ensure USM toggle is ON
- **Toggle workaround**: If USM is listed but icon doesn't appear, toggle OFF, wait 2 seconds, toggle back ON. This resets the menu bar permission state.

### Ghost entry in Menu Bar settings after uninstall
- Launch Services has stale registration
- Run unregister steps from "Complete Uninstall" section
- Reboot if necessary

### API not responding
- Check if another process is using port 8767
- Check Console.app for USM logs

---

## Configuration Files

| File | Purpose |
|------|---------|
| `Config/Shared.xcconfig` | Build settings (bundle ID, LSUIElement, etc.) |
| `Config/USM.entitlements` | App capabilities |
| `USM/Assets.xcassets/MenuBarIcon.imageset/` | Menu bar icon |

---

## Key Learnings

1. **Launch Services is the source of truth** for the Menu Bar settings list. Deleting an app doesn't remove its Launch Services registration.

2. **Multiple build locations** can exist (DerivedData, local build folder). All must be cleaned.

3. **Spotlight indexes apps** via bundle ID. Use `mdfind "kMDItemCFBundleIdentifier == 'com.unamentis.server-manager2'"` to find all instances.

4. **System UI processes cache state**. Restart SystemUIServer, ControlCenter, and cfprefsd after cleanup.
