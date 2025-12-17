# VoiceLearn - Detailed Setup Guide

## System Requirements

- **macOS**: 14.0+ (Sonoma or later)
- **Xcode**: 15.4+
- **Swift**: 6.0 (included with Xcode)
- **RAM**: 16GB+ recommended
- **Disk**: 15GB+ free space (10GB for project + 2.4GB for on-device models)
- **iOS Device**: iPhone 15 Pro or later (or simulator)
- **iOS Target**: 18.0+

## Development Tools

### Required

- **Xcode 15.2+**
  ```bash
  # Install from App Store
  # Or download from developer.apple.com
  ```

- **Homebrew**
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

- **GitHub CLI** (optional but recommended)
  ```bash
  brew install gh
  gh auth login
  ```

### Development Dependencies

Installed automatically by `setup-local-env.sh`:

- **SwiftLint** - Code linting
- **SwiftFormat** - Code formatting
- **xcbeautify** - Readable build output

## Project Structure Setup

### 1. Directory Layout

After running the installer, you'll have:

```
VoiceLearn-iOS/
├── .git/                      # Git repository
├── .github/
│   └── workflows/
│       └── ios.yml           # CI/CD configuration
├── .vscode/
│   ├── settings.json         # VS Code settings
│   └── tasks.json            # Build tasks
├── VoiceLearn/               # Main app (after Xcode setup)
│   ├── Core/
│   │   ├── Audio/
│   │   ├── Session/
│   │   ├── Curriculum/
│   │   └── Telemetry/
│   ├── Services/
│   │   ├── STT/
│   │   ├── TTS/
│   │   ├── LLM/
│   │   ├── VAD/
│   │   └── Protocols/
│   └── UI/
├── VoiceLearnTests/          # Tests
│   ├── Unit/
│   ├── Integration/
│   ├── E2E/
│   └── Helpers/
├── scripts/                  # Development scripts
│   ├── setup-local-env.sh
│   ├── test-quick.sh
│   ├── test-all.sh
│   ├── test-e2e.sh
│   ├── lint.sh
│   ├── format.sh
│   └── health-check.sh
├── docs/                     # Documentation
│   ├── QUICKSTART.md
│   ├── SETUP.md
│   ├── TESTING.md
│   └── CONTRIBUTING.md
├── .gitignore               # Git ignore
├── .swiftlint.yml          # Linting config
├── .swiftformat            # Format config
├── .env.example            # Environment template
└── README.md               # Main README
```

### 2. Xcode Project Setup

This must be done manually because Xcode project files are binary:

1. **Open Xcode**
2. **File → New → Project**
3. **iOS → App**
4. **Configure**:
   - Product Name: `VoiceLearn`
   - Team: Your team
   - Organization ID: `com.yourname`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **Core Data** ✓ CRITICAL!
   - Include Tests: ✓ CRITICAL!
5. **Save** to project directory
6. **Don't** check "Create Git repository" (already done)

### 3. Swift Package Manager

The project uses Swift Package Manager. Dependencies are defined in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    .package(url: "https://github.com/StanfordBDHG/llama.cpp.git", from: "0.3.3"),
]
```

Dependencies are resolved automatically when building:

```bash
swift build
# Or open Package.swift in Xcode
```

### 4. On-Device GLM-ASR Models (Optional)

For on-device speech recognition without API costs:

#### Model Files Required

| Model | Size | Format |
|-------|------|--------|
| GLMASRWhisperEncoder | 1.2 GB | .mlpackage |
| GLMASRAudioAdapter | 56 MB | .mlpackage |
| GLMASREmbedHead | 232 MB | .mlpackage |
| glm-asr-nano-q4km | 935 MB | .gguf |

**Total: ~2.4 GB**

#### Setup Steps

1. **Download models** from Hugging Face:
   ```bash
   # Models available at:
   # https://huggingface.co/zai-org/GLM-ASR-Nano-2512
   ```

2. **Create models directory**:
   ```bash
   mkdir -p models/glm-asr-nano
   ```

3. **Place models**:
   ```
   models/glm-asr-nano/
   ├── GLMASRWhisperEncoder.mlpackage/
   ├── GLMASRAudioAdapter.mlpackage/
   ├── GLMASREmbedHead.mlpackage/
   └── glm-asr-nano-q4km.gguf
   ```

4. **Add to Xcode** (for device builds):
   - Right-click VoiceLearn folder
   - Add Files to VoiceLearn
   - Select model files
   - Check "Copy items if needed"
   - Check "Add to targets: VoiceLearn"

See [GLM_ASR_ON_DEVICE_GUIDE.md](GLM_ASR_ON_DEVICE_GUIDE.md) for complete setup.

## Configuration

### API Keys

1. Copy template:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env`:
   ```bash
   code .env  # Or nano .env
   ```

3. Add your keys:
   ```
   ASSEMBLYAI_API_KEY=your_key_here
   DEEPGRAM_API_KEY=your_key_here
   OPENAI_API_KEY=your_key_here
   ANTHROPIC_API_KEY=your_key_here
   ELEVENLABS_API_KEY=your_key_here
   ```

4. **Never commit** `.env` - it's in `.gitignore`

### VS Code Configuration

Already configured in `.vscode/`:

- Format on save
- Swift language support
- Build tasks (⌘ + Shift + B)
- Test tasks

## Verification

### Build Test

```bash
# From command line
xcodebuild -scheme VoiceLearn build

# Or in Xcode
⌘ + B
```

### Run Tests

```bash
# Quick tests
./scripts/test-quick.sh

# All tests
./scripts/test-all.sh

# Health check
./scripts/health-check.sh
```

### Check Code Quality

```bash
# Lint
./scripts/lint.sh

# Format
./scripts/format.sh
```

## Troubleshooting

### Issue: Xcode project won't build

**Solution**:
```bash
# Clean build folder
xcodebuild clean

# Delete derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Issue: Tests won't run

**Check**:
1. Test target is enabled in scheme
2. iOS Simulator is available
3. Xcode Command Line Tools installed:
   ```bash
   xcode-select --install
   ```

### Issue: SwiftLint errors

**Solution**:
```bash
# Reinstall SwiftLint
brew reinstall swiftlint

# Check version (should be 0.50+)
swiftlint version
```

### Issue: API keys not working

**Check**:
1. `.env` file exists in project root
2. Keys have no quotes or spaces
3. Keys are valid (test on provider websites)

### Issue: Git hooks not running

**Solution**:
```bash
# Reinstall hooks
./scripts/setup-local-env.sh

# Check hook is executable
ls -l .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Advanced Setup

### Custom Xcode Schemes

Create schemes for different configurations:

1. **Development** - Local testing, mock APIs
2. **Staging** - Real APIs, test data
3. **Production** - Production APIs, real data

### Test Fixtures

Generate test audio:
```bash
cd Tests/Fixtures
./generate-test-audio.sh
```

### Code Coverage

Enable in Xcode:
1. Edit Scheme (⌘ + <)
2. Test → Options
3. ✓ Gather coverage for all targets

View coverage:
```bash
open DerivedData/.../coverage.lcov
```

## CI/CD Setup

GitHub Actions is configured in `.github/workflows/ios.yml`.

**To enable**:
1. Push to GitHub
2. Actions run automatically on push/PR
3. View results in GitHub Actions tab

**Requirements**:
- GitHub repository
- Secrets configured (if using real API keys in CI)

## AI Simulator Testing Setup

VoiceLearn supports AI-driven iOS Simulator testing via MCP (Model Context Protocol).

### Install ios-simulator-mcp

```bash
claude mcp add ios-simulator npx ios-simulator-mcp
```

### Capabilities

With the MCP server installed, Claude Code can:
- Boot/shutdown simulators
- Install and launch apps
- Tap, swipe, type
- Take screenshots
- Inspect accessibility elements

### Usage

After restarting Claude Code, simulator tools become available. See [AI_SIMULATOR_TESTING.md](AI_SIMULATOR_TESTING.md) for workflow details.

---

## Next Steps

- Read [TESTING.md](TESTING.md) for testing strategy
- Read [DEBUG_TESTING_UI.md](DEBUG_TESTING_UI.md) for built-in troubleshooting tools
- Read [GLM_ASR_ON_DEVICE_GUIDE.md](GLM_ASR_ON_DEVICE_GUIDE.md) for on-device speech recognition
- Read [AI_SIMULATOR_TESTING.md](AI_SIMULATOR_TESTING.md) for AI testing workflow
- Read [CONTRIBUTING.md](CONTRIBUTING.md) for workflow
- Review [TASK_STATUS.md](TASK_STATUS.md) for current implementation status

---

**Need help?** Open an issue on GitHub.
