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
- **Bundle `Info.plist` is generated, not read** — heredocs in `scripts/build.sh` AND `.github/workflows/release.yml`. Edit both. The root `Info.plist` is vestigial; nothing reads it.
- Requires **microphone** and **speech recognition** permissions

### Layout

- `Sources/App` — `AppState` is the root coordinator; owns every service
- `Sources/Services/Speech` — providers + matching engine (the heart of the app)
- `Sources/Services/Bridge` — WebSocket server for the Chrome extension
- `Sources/Views/{MainWindow,Onboarding,Prompter,Settings}` — SwiftUI with AppKit interop
- `Extension/` — Chrome MV3 extension (plain JS) that scrapes Google Slides speaker notes
- `Entitlements/`, `scripts/` — signing + build tooling

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
- **Install the input tap exactly once** — in `AppleSpeechProvider.startListening()`, before `engine.start()`, and remove it only after `engine.stop()`. Swapping a tap on a running engine races CoreAudio's render thread against AVFAudio freeing the old block (`EXC_BAD_ACCESS`, `pc=0x0` on `com.apple.audio.IOThread.client`). Session rotation retargets `SpeechAudioSink` instead of touching the tap.
- **WhisperKit** must be initialized with offline env vars:
  ```swift
  setenv("HF_HUB_OFFLINE", "1", 1)
  setenv("TRANSFORMERS_OFFLINE", "1", 1)
  setenv("HF_HUB_DISABLE_IMPLICIT_TOKEN", "1", 1)
  ```
- **Landmark-based tracking** instead of word-by-word matching — algorithm lives in `LandmarkIndex.swift` + `SpeechToScrollEngine.swift`; read their tests first. `CueFlow-Engineering-Spec.md` predates this design and never mentions landmarks.
- **Scroll system is two-layer**: `SpeechToScrollEngine.scrollPosition` (Q word / highlight) and `PrompterTextCoordinator.userScrollOffset` (viewport pan) are independent. Trackpad scroll shifts the viewport only — the Q word never moves. `userScrollOffset` decays at ×0.97/frame so speech re-centers automatically.
- **Engine and text view must tokenize identically** — `SpeechToScrollEngine.loadScript` splits raw markdown on whitespace then normalizes via `TextNormalizer`; `PrompterTextView.rebuildContent` splits the *rendered* string (markers stripped) on whitespace. The word **counts** must stay equal or the highlight desyncs from the scroll position. Any `MarkdownRenderer` change that alters whitespace breaks this silently.
- **One index space: `displayWords`.** `cursorPosition`, `scrollPosition`, `matchWords`, the text view's word positions, and the recovery `LandmarkIndex` are all indexed the same way. `TextNormalizer.normalizeText` (used by `LandmarkIndex(scriptText:)`) drops fillers and expands numbers, so it produces a *different* count — never map its positions onto a cursor. Build the index with `LandmarkIndex(normalizedWords: matchWords)`.
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

- Run `make setup-local-signing` **once per machine**: otherwise `build.sh` ad-hoc signs and macOS resets Microphone permission on every rebuild.
- `make build` reveals the bundle in Finder on completion and does **not** run tests.

## CI & Releasing

- `ci.yml` — PRs to `main` run `swift build -c release` and `swift test --parallel`
- `release.yml` — **any push to `main` touching a non-`.md` file cuts a public release**: tests, universal build, sign + notarize, tag `v$VERSION`, upload .zip + .dmg. If `v$VERSION` already exists it silently auto-bumps the patch.
- So: branch + PR for all code work. Bump `VERSION` only in the change that should ship.

## Testing / Debugging

- `--simulate` flag: launches with test text and simulated speech at 3 wps (no mic needed)
  ```bash
  .build/apple/Products/Release/CuePrompt --simulate
  ```
- Debug log: `tail -f /tmp/cueprompt-debug.log`
- Single test: `swift test --filter FuzzyMatcherTests` (or `--filter FuzzyMatcherTests/testName`)
- Non-Swift test data goes in `Tests/Fixtures/` only — it's the sole path excluded in `Package.swift`

## Design System
Always read DESIGN.md before making any visual or UI decisions.
All font choices, colors, spacing, and aesthetic direction are defined there.
Do not deviate without explicit user approval.
In QA mode, flag any code that doesn't match DESIGN.md.
