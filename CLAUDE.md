# CuePrompt — LLM Assistant Guidelines

## What This Is

CuePrompt is a macOS-native smart teleprompter. It uses WhisperKit voice recognition to pace scrolling to natural speech. It presents as a Dynamic Island-style pill below the MacBook notch that expands into a full teleprompter overlay. Content comes from a Chrome extension (Google Slides), manual text, or local files.

## Architecture

- **Swift 5.9+**, target **macOS 14+** (Sonoma)
- **Package.swift + Makefile** build system (no Xcode project)
- **@Observable** macro for state management (not ObservableObject)
- **Swift Concurrency** (async/await, AsyncStream, actors) for all async work
- **No SwiftData** — UserDefaults for settings, FileManager for presentation cache
- **VERSION** file in repo root drives `CFBundleShortVersionString` in build script
- Requires **microphone** and **speech recognition** permissions

### Directory Structure

```
Sources/
  App/            — CuePromptApp, AppDelegate, AppState (root coordinator)
  Models/         — AppSettings, PrompterState, Presentation, Script, RecognizedWord, ContentSource
  Resources/      — Bundled app resources/assets
  Services/
    Bridge/       — Chrome extension WebSocket bridge (BridgeCoordinator, WebSocketServer)
    Speech/       — SpeechProvider protocol, WhisperKitProvider, AppleSpeechProvider,
                    SpeechCoordinator, SpeechToScrollEngine, FuzzyMatcher, LandmarkIndex,
                    ModelManager, TextNormalizer
    ContentIngestor, MarkdownParser, WindowManager
  Utilities/      — Constants, ScreenDetector, CodableRect, DesignTokens
  Views/
    MainWindow/   — HomeView
    Onboarding/   — OnboardingView
    Prompter/     — PillView, PrompterContentView, PrompterOverlayView, PrompterTextView,
                    PrompterTextCoordinator, PrompterScrollView, PrompterLayoutManager,
                    CountdownView, MarkdownRenderer
    Settings/     — SettingsView tabs (Appearance, Behavior, Speech)
Tests/            — XCTest files mirroring Services (FuzzyMatcher, LandmarkIndex, Engine, etc.)
scripts/          — build.sh, install.sh, run-tests.sh, create-dmg.sh, gen_icon.py
```

### Key Types

- **AppState** — root `@Observable` coordinator; owns all services, manages prompter lifecycle
- **SpeechToScrollEngine** — converts recognized words into scroll position + highlight
- **SpeechCoordinator** — bridges SpeechProvider output to the engine
- **SpeechProvider** (protocol) — `WhisperKitProvider` (on-device) and `AppleSpeechProvider` (system)
- **ContentIngestor** — normalizes input from text/files/Chrome extension into `EngineContent`
- **BridgeCoordinator** — WebSocket server receiving Google Slides data from Chrome extension
- **WindowManager** — manages the floating prompter panel (pill ↔ expanded)
- **PrompterTextCoordinator** — 60fps display-link scroll coordinator; owns `displayedOffset` (smooth interpolation) and `userScrollOffset` (viewport pan); lives inside `PrompterTextView`
- **PrompterScrollView** — `NSScrollView` subclass; intercepts `scrollWheel` events and routes them to the coordinator without touching the engine
- **PrompterState** — modes: `idle`, `countdown`, `expanded`, `collapsed`, `paused`, `finished`

## Code Style

- Avoid force unwrapping (`!`); prefer `guard let` and optional chaining
- Value types (`struct`/`enum`) by default; `class` only for reference semantics
- Prevent retain cycles with `[weak self]`
- UI updates on `@MainActor`
- Functions ≤ 40 lines, single-purpose
- Self-documenting code; comments only for non-obvious logic
- XCTest for all new logic; TDD where practical
- `swift test --parallel` must pass before committing

## Key Patterns

- **SpeechProvider** protocol has NO ObservableObject conformance — views observe `SpeechCoordinator` instead
- **Audio buffer** access is actor-isolated (data race prevention)
- **WhisperKit** must be initialized with offline env vars:
  ```swift
  setenv("HF_HUB_OFFLINE", "1", 1)
  setenv("TRANSFORMERS_OFFLINE", "1", 1)
  setenv("HF_HUB_DISABLE_IMPLICIT_TOKEN", "1", 1)
  ```
- **Landmark-based tracking** instead of word-by-word matching — see plan for algorithm details
- **Scroll system is two-layer**: `SpeechToScrollEngine.scrollPosition` (Q word / highlight) and `PrompterTextCoordinator.userScrollOffset` (viewport pan) are independent. Trackpad scroll shifts the viewport only — the Q word never moves. `userScrollOffset` decays at ×0.97/frame so speech re-centers automatically.
- **Debug log** written to `/tmp/cueprompt-debug.log` via `debugLog()` in AppState.swift

## Building

```bash
make build           # Release universal binary
make build-notarize  # Release build (notarization not yet implemented)
make test            # Run tests (swift test --parallel)
make install         # Build + install to /Applications
make clean           # Remove .build/, app bundle, DMG
make dmg             # Create distributable DMG
make setup-local-signing  # Create persistent local signing identity
make help            # List common targets
```

## Testing / Debugging

- `--simulate` flag: launches with test text and simulated speech at 3 wps (no mic needed)
  ```bash
  .build/apple/Products/Release/CuePrompt --simulate
  ```
- Debug log: `tail -f /tmp/cueprompt-debug.log`

## Design System
Always read DESIGN.md before making any visual or UI decisions.
All font choices, colors, spacing, and aesthetic direction are defined there.
Do not deviate without explicit user approval.
In QA mode, flag any code that doesn't match DESIGN.md.
