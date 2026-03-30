---
name: beta-check
description: Check all TestFlight prerequisites and report readiness status for first beta submission
argument-hint: "[--fix]"
disable-model-invocation: true
---

# /beta-check - TestFlight Readiness Check

## Purpose

Checks all prerequisites for submitting the first TestFlight beta build. Reports a clear PASS/FAIL/WARN status for each item with a blocking count.

## Usage

```
/beta-check             # Run all checks, report status
/beta-check --fix       # Run checks and offer to fix automatable issues
```

## Workflow

### 1. Run App Store Validation Script

```bash
./scripts/validate-for-appstore.sh --quick
```

Capture exit code and output. This checks:
- Privacy manifest (PrivacyInfo.xcprivacy)
- Info.plist required keys
- Entitlements
- Security scan (hardcoded API keys, debug code)
- Release build

### 2. Additional Prerequisite Checks

Run these checks that the script does not cover:

**Build configuration:**
```bash
# Check DEVELOPMENT_TEAM is set
grep "DEVELOPMENT_TEAM" /Users/ramerman/dev/unamentis/project.yml
```
FAIL if empty string or placeholder.

**Code signing:**
```bash
security find-identity -v -p codesigning 2>/dev/null | grep -c "valid identities"
```
FAIL if no valid identities found.

**Privacy policy:**
Check if any of these exist:
- `docs/privacy-policy.md`
- `docs/PRIVACY_POLICY.md`
- A URL referenced in Info.plist or APP_STORE_COMPLIANCE.md
FAIL if no privacy policy found (required for App Store).

**App icons:**
```bash
ls /Users/ramerman/dev/unamentis/UnaMentis/Assets.xcassets/AppIcon.appiconset/*.png 2>/dev/null | wc -l
```
FAIL if no PNG files found.

**Bundled models (Pocket TTS):**
Check that Pocket TTS model files are included in the build:
- Look for model references in project.yml or Copy Bundle Resources
- Verify model files exist in the expected location
FAIL if models not bundled (Pocket TTS must ship with every build).

**TestFlight test notes:**
Check if `docs/testflight-test-info.md` or similar exists.
WARN if not found (recommended but not blocking).

### 3. Cross-Reference APP_STORE_COMPLIANCE.md

Read `/Users/ramerman/dev/unamentis/docs/APP_STORE_COMPLIANCE.md` and check each critical action item:
- PrivacyInfo.xcprivacy: COMPLETE or not
- Remote logging: Hardened for release or not
- App Privacy labels: Documented or not

### 4. Report

```
BETA READINESS CHECK
====================
App Store Validation Script: [PASS/FAIL]

Build & Signing:
  [PASS/FAIL] Release build succeeds
  [PASS/FAIL] DEVELOPMENT_TEAM configured
  [PASS/FAIL] Code signing identity available

Privacy & Compliance:
  [PASS/FAIL] Privacy manifest (PrivacyInfo.xcprivacy)
  [PASS/FAIL] Privacy policy exists
  [PASS/FAIL] Info.plist permission strings
  [PASS/WARN] App Privacy labels documented

Assets & Content:
  [PASS/FAIL] App icons present
  [PASS/FAIL] Pocket TTS models bundled
  [PASS/WARN] TestFlight test notes prepared

Security:
  [PASS/FAIL] No hardcoded API keys
  [PASS/FAIL] Remote logging release-safe
  [PASS/FAIL] No excessive debug code

BLOCKING: X items must be fixed before submission
ADVISORY: Y items recommended but not blocking
```

### 5. Fix Mode (--fix)

When `--fix` is passed, offer to:
- Create template privacy policy from APP_STORE_COMPLIANCE.md data
- Create template TestFlight test notes
- Report what DEVELOPMENT_TEAM should be set to (ask user)

## Success Criteria

- **READY:** Zero blocking items
- **NOT READY:** One or more blocking items

## When to Run

- After completing audio pipeline hardening
- After `/validate --full` passes
- Before attempting TestFlight submission
- When assessing overall project readiness
