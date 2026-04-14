# CuePrompt — LLM Assistant Guidelines

## What This Is

CuePrompt is a macOS-native smart teleprompter. It uses WhisperKit voice recognition to pace scrolling to natural speech. It presents as a Dynamic Island-style pill below the MacBook notch that expands into a full teleprompter overlay. Content comes from a Chrome extension (Google Slides), manual text, or local files.

## Architecture

- **Swift 5.9+**, target **macOS 14+** (Sonoma)
- **Package.swift + Makefile** build system (no Xcode project)
- **@Observable** macro for state management (not ObservableObject)
- **Swift Concurrency** (async/await, AsyncStream, actors) for all async work
- **No SwiftData** — UserDefaults for settings, FileManager for presentation cache

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

## Building

```bash
make build    # Release universal binary
make test     # Run tests
make install  # Build + install to /Applications
make dmg      # Create distributable DMG
```
