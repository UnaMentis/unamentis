# USM Menu Bar App - Fresh Session Task List

**Purpose:** Clean restart to build a working macOS 26 menu bar app

---

## FIRST: Read the Technical Design Document

**BEFORE DOING ANYTHING ELSE**, read this document:

```
/Users/ramerman/dev/unamentis/server/server-manager/MACOS26_MENUBAR_TDD.md
```

⚠️ **IMPORTANT:** This TDD is currently a DRAFT based on research. It is NOT verified.

The TDD contains:
- Proposed code patterns based on TahoeMenuDemo reference
- Info.plist requirements (from documentation)
- Build settings (from documentation)
- Known issues and solutions (from research)

**The TDD becomes authoritative ONLY AFTER Phase 2 succeeds** (verifying TahoeMenuDemo works locally).

**DO NOT treat this as proven until you've verified the reference implementation works.**

---

## Phase 1: Cleanup (MUST DO FIRST)

### 1.1 Kill All Running Processes

> **Note:** This is the ONE exception where `pkill` is allowed. The Server Manager app cannot restart itself via its own API. For all other services, use `/service restart <service-name>`.

```bash
pkill -f "USM.app" 2>/dev/null
pkill -f "MenuDemo" 2>/dev/null
pkill -f "usm" 2>/dev/null
```

### 1.2 Uninstall Test Apps
```bash
rm -rf ~/Applications/USM.app
rm -rf ~/Applications/MenuDemo.app
rm -rf /tmp/TahoeMenuDemo
rm -rf /tmp/MenuDemo*
rm -rf /tmp/USM*
```

### 1.3 Clear Caches
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/USM-*
rm -rf ~/Library/Developer/Xcode/DerivedData/MenuDemo-*
killall SystemUIServer
```

### 1.4 Verify Clean State
```bash
pgrep -fl "USM\|MenuDemo"  # Should return nothing
ls ~/Applications/ | grep -E "USM|MenuDemo"  # Should return nothing
```

---

## Phase 2: Verify Reference Works

### 2.1 Clone TahoeMenuDemo
```bash
cd /tmp
git clone https://github.com/sjhooper/TahoeMenuDemo.git
cd TahoeMenuDemo
```

### 2.2 Build TahoeMenuDemo
```bash
# Use Xcode to build
open MenuDemo.xcodeproj
# OR use xcodebuild:
xcodebuild -project MenuDemo.xcodeproj -scheme MenuDemo -configuration Debug build
```

### 2.3 Run TahoeMenuDemo
- Launch the built app
- **VERIFY:** Menu bar icon appears (circle icon)
- **VERIFY:** Clicking shows dropdown menu
- **VERIFY:** Start/Stop toggle works
- **VERIFY:** Quit terminates app

### 2.4 Document Result
- If TahoeMenuDemo WORKS: Proceed to Phase 3
- If TahoeMenuDemo FAILS: Stop. System-level issue needs investigation.

---

## Phase 3: Build USM Using Verified Pattern

### 3.1 Start Fresh
Do NOT modify existing USMXcode. Create new project following TDD exactly.

### 3.2 Create Minimal Version First
Create `USMApp.swift` with ONLY this code (from TDD Section 13):

```swift
import SwiftUI

@main
struct USMApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("UnaMentis Server Manager")
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "server.rack")
                .renderingMode(.template)  // CRITICAL
        }
        .menuBarExtraStyle(.menu)
    }
}
```

### 3.3 Verify Minimal Version Works
- Build and run
- **VERIFY:** Menu bar icon appears
- **VERIFY:** Clicking shows menu
- **VERIFY:** Quit works

### 3.4 Add ServiceManager Incrementally
Only AFTER minimal version works, add ServiceManager piece by piece:
1. First: Add ServiceManager class with NO initialization logic
2. Verify still works
3. Then: Add service list (static data only)
4. Verify still works
5. Then: Add process monitoring
6. Verify still works

---

## Phase 4: Final Verification

### 4.1 Functional Checklist
- [ ] Menu bar icon visible
- [ ] Icon correct in light mode
- [ ] Icon correct in dark mode
- [ ] Click opens menu
- [ ] All menu items work
- [ ] Services display correctly
- [ ] Start/Stop services work
- [ ] Quit terminates app

### 4.2 System Integration Checklist
- [ ] App in System Settings → Menu Bar list
- [ ] Toggle ON enables icon
- [ ] Toggle OFF hides icon
- [ ] App survives reboot (if set to launch at login)

---

## Key Documents

| Document | Path | Purpose |
|----------|------|---------|
| Technical Design Doc | `server/server-manager/MACOS26_MENUBAR_TDD.md` | Authoritative spec |
| Diagnostic Report | `server/server-manager/USM_DIAGNOSTIC_REPORT.md` | What went wrong |
| This Task List | `server/server-manager/FRESH_SESSION_TASKS.md` | Step-by-step guide |

---

## Rules for This Session

1. **Follow TDD exactly** - No deviations without explicit approval
2. **Test after every change** - Don't batch changes
3. **Document findings** - Update TDD if new information discovered
4. **Stop if stuck** - Don't experiment endlessly, report status

---

## Success Criteria

The task is COMPLETE when:
1. USM menu bar icon is visible
2. All menu functionality works
3. Service management works
4. App persists across rebuilds
5. TDD is updated with any new learnings
