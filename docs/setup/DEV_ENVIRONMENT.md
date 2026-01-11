# UnaMentis Developer Environment Setup

This guide covers the complete setup for developing UnaMentis on macOS. Follow these steps to configure your development environment from scratch.

## Prerequisites

- **macOS 14.5+** (Sonoma or later)
- **Apple Silicon Mac** (M1/M2/M3/M4) recommended for on-device ML
- **16GB+ RAM** recommended
- **50GB+ free disk space** for Xcode, simulators, and models

---

## 1. Core Development Tools

### 1.1 Xcode

**Required Version:** Xcode 16.x+

```bash
# Install from Mac App Store, or:
xcode-select --install

# Verify installation
xcodebuild -version
# Should show: Xcode 16.x, Build version xxxxx
```

After installing Xcode:
1. Open Xcode and accept the license agreement
2. Install additional components when prompted
3. Go to Settings > Platforms and install **iOS 18** simulator runtime

### 1.2 Homebrew

```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add to PATH (Apple Silicon)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# Verify
brew --version
```

### 1.3 Swift Development Tools

```bash
# Install Swift linting and formatting
brew install swiftlint swiftformat xcbeautify

# Verify
swiftlint version
swiftformat --version
```

### 1.4 Node.js (for Operations Console)

```bash
# Install Node.js 18+ via Homebrew
brew install node@20

# Or use nvm for version management
brew install nvm
nvm install 20
nvm use 20

# Verify
node --version  # Should be 20.x or higher
npm --version
```

### 1.5 Python (for Management Console)

```bash
# macOS comes with Python 3, but install latest via Homebrew
brew install python@3.12

# Verify
python3 --version  # Should be 3.12.x

# Install required Python packages
pip3 install aiohttp aiofiles
```

---

## 2. Editor Setup

### 2.1 VS Code / Antigravity / Cursor

This project uses **VS Code** or a VS Code fork (Antigravity, Cursor) with the **Claude Code extension**.

**Required Extensions:**
- **Claude Code** (Anthropic) - AI coding assistant
- **Swift** (Swift Server Work Group) - Swift language support
- **SwiftLint** - Inline linting

**Recommended Extensions:**
- **GitLens** - Git history and blame
- **Error Lens** - Inline error display
- **Todo Tree** - Track TODOs

### 2.2 Claude Code Extension Setup

1. Install the Claude Code extension from the VS Code marketplace
2. Sign in with your Anthropic account
3. The extension will use the project's `.claude/settings.local.json` for permissions

---

## 3. MCP Server Setup (Critical for AI Development)

MCP (Model Context Protocol) servers enable Claude to interact directly with Xcode and the iOS Simulator. **This is mandatory for effective development.**

### 3.1 Install MCP Servers

```bash
# Install XcodeBuildMCP (Xcode integration)
claude mcp add XcodeBuildMCP -- npx xcodebuildmcp@latest

# Install ios-simulator MCP (Simulator control)
claude mcp add ios-simulator -- npx -y ios-simulator-mcp
```

### 3.2 Verify MCP Servers

```bash
claude mcp list

# Expected output:
# ios-simulator: npx -y ios-simulator-mcp - ✓ Connected
# XcodeBuildMCP: npx xcodebuildmcp@latest - ✓ Connected
```

If servers show as disconnected, restart your Claude Code session.

### 3.3 MCP Capabilities

| Server | Capabilities |
|--------|-------------|
| **XcodeBuildMCP** | Build, test, clean, install apps, capture logs, device management |
| **ios-simulator** | Screenshots, UI taps, swipes, typing, accessibility info |
| **slack** | Post messages, read channels, reply to threads, add reactions |
| **trello** | Create/update cards, add comments, manage boards and lists |

### 3.4 Slack & Trello MCP Setup (Team Communication)

These MCP servers enable Claude to post to Slack channels and manage Trello cards. Credentials are securely managed via GitHub Actions and age encryption.

#### Prerequisites

```bash
# Install age encryption tool
brew install age jq

# Verify gh CLI is authenticated
gh auth status
```

#### Generate Encryption Keypair (One-time per machine)

```bash
mkdir -p ~/.config/unamentis
age-keygen -o ~/.config/unamentis/age-key.txt
chmod 600 ~/.config/unamentis/age-key.txt
```

**Important:** Back up this key securely. Without it, you cannot decrypt credentials.

#### Fetch Credentials

The project includes scripts that fetch encrypted credentials from the private `sirfifer/unamentis-learning` repository:

```bash
# First-time or refresh credentials
./scripts/refresh-mcp-creds.sh

# Verify credentials are cached
cat ~/.cache/unamentis/creds.json | jq 'keys'
# Should show: ["slack_bot_token", "slack_team_id", "trello_api_key", "trello_token"]
```

#### Verify Slack & Trello MCP Servers

```bash
claude mcp list

# Expected output should include:
# slack: ./scripts/mcp-slack.sh - ✓ Connected
# trello: ./scripts/mcp-trello.sh - ✓ Connected
```

If servers show as disconnected, restart your Claude Code session.

### 3.5 The /comms Skill

The `/comms` skill enables natural language communication with Slack and Trello without requiring exact channel names or board IDs.

#### Usage

```
/comms post to android: feature complete
/comms create card on server list: fix API bug
/comms add comment to card: resolved
```

#### Key Behaviors

- **Fuzzy Matching**: "android" resolves to tech-android channel or Android list
- **Smart Defaults**: Tech topics default to tech-general channel and Tech Work board
- **Trello Comments**: Automatically prefixed with "From Claude Code:" for attribution

#### Skill Files Location

The skill files are in `.claude/skills/comms/`:
- `SKILL.md` - Instructions and examples
- `RESOURCES.md` - Channel/board ID mappings

See the full reference in [MCP_SETUP.md](../explorations/MCP_SETUP.md).

---

## 4. iOS Simulator Setup

### 4.1 Create Required Simulators

The project uses **iPhone 16 Pro** as the default simulator to match CI. The test runner will automatically fall back to available simulators if needed.

```bash
# List available runtimes
xcrun simctl list runtimes

# List existing devices
xcrun simctl list devices

# Create iPhone 16 Pro simulator (if not exists)
xcrun simctl create "iPhone 16 Pro" "iPhone 16 Pro" iOS18.0
```

### 4.2 Boot Simulator

```bash
# Boot the simulator
xcrun simctl boot "iPhone 16 Pro"

# Open Simulator app
open -a Simulator
```

---

## 5. Project Setup

### 5.1 Clone Repository

```bash
git clone <repository-url> unamentis
cd unamentis
```

### 5.2 Environment Configuration

```bash
# Copy example environment file
cp .env.example .env

# Edit and add your API keys
# Required keys:
# - OPENAI_API_KEY (for embeddings and cloud LLM)
# - ANTHROPIC_API_KEY (for Claude LLM)
```

### 5.3 Install Dependencies

```bash
# iOS/Swift dependencies (via Swift Package Manager)
# These are fetched automatically on first build

# Operations Console (Next.js)
cd server/web
npm install
cd ../..

# Management Console (Python)
# No separate install needed - uses system Python
```

### 5.4 Install Git Hooks (Recommended)

Git hooks automatically run quality checks before commits and pushes. This prevents broken code from being committed.

```bash
# Install pre-commit and pre-push hooks
./scripts/install-hooks.sh
```

This installs:
- **Pre-commit hook**: Runs SwiftLint, SwiftFormat, Ruff (Python), ESLint (JS/TS) on staged files
- **Pre-push hook**: Runs quick tests before pushing

**Optional tools for hooks** (install as needed):
```bash
# Swift linting and formatting (recommended)
brew install swiftlint swiftformat

# Python linting (for server work)
pip install ruff

# Secrets detection (optional but recommended)
brew install gitleaks
```

The hooks will skip checks for tools that aren't installed, but will run what's available.

### 5.5 Verify Setup

```bash
# Run the setup script
./scripts/setup-local-env.sh

# Run health check
./scripts/health-check.sh
```

---

## 6. Running the Project

### 6.1 Start Log Server (ALWAYS FIRST)

```bash
# Start the remote log server
python3 scripts/log_server.py &

# Verify it's running
curl -s http://localhost:8765/health  # Should return "OK"

# View logs in browser
open http://localhost:8765/
```

### 6.2 Build and Run iOS App

```bash
# Build for simulator (iPhone 16 Pro for CI parity)
xcodebuild -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Install on simulator
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/UnaMentis-*/Build/Products/Debug-iphonesimulator/UnaMentis.app

# Launch
xcrun simctl launch booted com.unamentis.app
```

Or use Xcode directly: Open `UnaMentis.xcodeproj` and press Cmd+R.

### 6.3 Start Management Console (Port 8766)

```bash
cd server/management
python3 server.py &

# Access at http://localhost:8766/
```

### 6.4 Start Operations Console (Port 3000)

```bash
cd server/web
npm run dev

# Access at http://localhost:3000/
```

---

## 7. Development Workflow

### 7.1 Before Making Changes

1. Ensure log server is running
2. Pull latest changes: `git pull`
3. Check task status: `cat docs/TASK_STATUS.md`

### 7.2 Making Changes

1. Create a feature branch: `git checkout -b feat/my-feature`
2. Make your changes
3. Run lint: `./scripts/lint.sh`
4. Run tests: `./scripts/test-quick.sh`

### 7.3 Before Committing

```bash
# Must pass before committing
./scripts/lint.sh && ./scripts/test-quick.sh
```

### 7.4 Debugging UI Issues

With MCP servers, Claude can autonomously:
1. Build the app
2. Install and launch on simulator
3. Capture runtime logs
4. Take screenshots
5. Interact with the UI
6. Analyze and iterate

---

## 8. Project Structure

```
unamentis/
├── UnaMentis/              # iOS app source
│   ├── Core/               # Business logic (actors, services)
│   ├── Services/           # External integrations (LLM, STT, TTS)
│   ├── UI/                 # SwiftUI views
│   └── Persistence/        # Core Data stack
├── UnaMentisTests/         # Unit and integration tests
├── server/
│   ├── management/         # Python backend (port 8766)
│   ├── web/                # Next.js frontend (port 3000)
│   ├── importers/          # Curriculum import plugins
│   └── database/           # SQLite curriculum DB
├── curriculum/             # UMCF format specification
├── scripts/                # Build, test, utility scripts
├── docs/                   # Documentation
├── .claude/                # Claude Code settings
├── CLAUDE.md               # Claude Code instructions
└── AGENTS.md               # AI development guidelines
```

---

## 9. Troubleshooting

### Xcode Build Fails

```bash
# Clean build folder
rm -rf ~/Library/Developer/Xcode/DerivedData/UnaMentis-*

# Clean and rebuild
xcodebuild clean -project UnaMentis.xcodeproj -scheme UnaMentis
xcodebuild -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

### Simulator Issues

```bash
# Reset simulator
xcrun simctl erase "iPhone 16 Pro"

# Restart CoreSimulatorService
sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService
```

### MCP Servers Not Connecting

1. Ensure Node.js 18+ is installed
2. Restart Claude Code session
3. Check `claude mcp list` output
4. Re-add servers if needed

### Log Server Not Receiving Logs

1. Check iOS app is configured for correct port (8765)
2. For simulator: uses localhost automatically
3. For device: set log server IP in Settings > Debug

---

## 10. Quick Reference

| Service | Port | URL |
|---------|------|-----|
| Log Server | 8765 | http://localhost:8765/ |
| Management Console | 8766 | http://localhost:8766/ |
| Operations Console | 3000 | http://localhost:3000/ |

| Command | Purpose |
|---------|---------|
| `./scripts/install-hooks.sh` | Install git pre-commit hooks |
| `./scripts/hook-audit.sh` | Audit for hook bypasses (`--no-verify`) |
| `./scripts/lint.sh` | Run SwiftLint |
| `./scripts/format.sh` | Run SwiftFormat |
| `./scripts/test-quick.sh` | Run unit tests (fast, no coverage) |
| `./scripts/test-all.sh` | Run all tests + 80% coverage enforcement |
| `./scripts/test-integration.sh` | Run integration tests only |
| `./scripts/test-ci.sh` | Unified test runner (CI parity) |
| `./scripts/health-check.sh` | Lint + quick tests |
| `./scripts/refresh-mcp-creds.sh` | Refresh Slack/Trello credentials |
| `claude mcp list` | Check MCP server status |

---

## 11. Additional Resources

- [CLAUDE.md](../../CLAUDE.md) - Claude Code instructions
- [AGENTS.md](../../AGENTS.md) - AI development guidelines
- [IOS_STYLE_GUIDE.md](../ios/IOS_STYLE_GUIDE.md) - Swift/SwiftUI coding standards
- [UnaMentis_TDD.md](../architecture/UnaMentis_TDD.md) - Technical design document
- [MCP_SETUP.md](../explorations/MCP_SETUP.md) - Slack/Trello MCP setup (detailed reference)
- [CODE_QUALITY_INITIATIVE.md](../quality/CODE_QUALITY_INITIATIVE.md) - Quality infrastructure and testing
- [CHAOS_ENGINEERING_RUNBOOK.md](../testing/CHAOS_ENGINEERING_RUNBOOK.md) - Voice pipeline resilience testing
