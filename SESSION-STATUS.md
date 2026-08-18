# CuePrompt Session Status — April 15, 2026

> **Historical snapshot — not the current state of the repo.**
>
> Re-verified against the code on 2026-08-17:
> - **BUG 1 (stale phrase buffer) is fixed.** `advanceTo()` now clears `spokenBuffer` down to its last word — a refinement of the fix proposed below, not the literal `spokenBuffer = []`.
> - **BUGs 2 and 3 appear unaddressed.** `lineFragmentPadding = 0` is still set with no `invalidateDisplay` call, and `showPill()` still sets the panel frame before layout.
> - The **file inventory**, **"What's Working"**, and **"Session Changes Made"** sections are history and have drifted (the inventory lists 41 Swift files; `Sources/` now has 43, including `PermissionManager`, which is absent below).
>
> For current architecture and conventions read [`CLAUDE.md`](CLAUDE.md); for build and run instructions read [`README.md`](README.md). Trust the code over this file.

## What CuePrompt Is

A macOS-native teleprompter app. Uses voice recognition (Apple Speech or WhisperKit) to scroll text in sync with the speaker's voice. Presents as a Dynamic Island-style pill that camouflages with the MacBook camera notch, then expands into a full-screen prompter overlay. Content comes from a Chrome extension (Google Slides speaker notes), manual text entry, or local markdown/text files.

## Architecture Overview

- **Swift 5.9+, macOS 14+ (Sonoma)**, built with `swift build` (Package.swift, no Xcode project)
- **@Observable** macro everywhere for state management
- **Swift Concurrency** (async/await, AsyncStream, actors) for speech providers
- Binary at `.build/arm64-apple-macosx/debug/CuePrompt`

### Key Data Flow

```
Speech Provider (Apple Speech / WhisperKit)
  → SpeechCoordinator (receives AsyncStream<[RecognizedWord]>)
    → engine.processWords(words)
      → SpeechToScrollEngine.processOneWord() — two-layer matching
        → advanceTo(position) updates scrollPosition: Double

PrompterContentView (@Bindable appState)
  → PrompterOverlayView (reads appState.engine.scrollPosition)
    → PrompterTextView (NSViewRepresentable wrapping NSTextView)
      → PrompterTextCoordinator (60fps Timer, scrolls to word position)
```

### File Inventory (41 Swift files)

**App Layer:**
- `Sources/App/CuePromptApp.swift` — @main, WindowGroup, menu commands, RootView
- `Sources/App/AppState.swift` — Root observable state, owns engine + coordinators + settings
- `Sources/App/AppDelegate.swift` — Menu bar status item

**Models:**
- `Sources/Models/AppSettings.swift` — Codable settings with UserDefaults persistence
- `Sources/Models/ContentSource.swift` — Enum for content origins
- `Sources/Models/Presentation.swift` — Chrome extension presentation model
- `Sources/Models/PrompterState.swift` — Prompter mode enum (idle/countdown/collapsed/expanded/paused/finished)
- `Sources/Models/RecognizedWord.swift` — Speech recognition output struct
- `Sources/Models/Script.swift` — Script + ScriptSection models

**Speech Engine:**
- `Sources/Services/Speech/SpeechToScrollEngine.swift` — **Core tracking engine**, two-layer phrase/word matching
- `Sources/Services/Speech/SpeechCoordinator.swift` — Provider lifecycle, feeds words to engine
- `Sources/Services/Speech/SpeechProvider.swift` — Protocol for speech providers
- `Sources/Services/Speech/AppleSpeechProvider.swift` — SFSpeechRecognizer with session rotation
- `Sources/Services/Speech/WhisperKitProvider.swift` — WhisperKit local speech-to-text
- `Sources/Services/Speech/TextNormalizer.swift` — Word normalization, homophones, number expansion
- `Sources/Services/Speech/FuzzyMatcher.swift` — Jaro-Winkler similarity
- `Sources/Services/Speech/LandmarkIndex.swift` — N-gram index for recovery search
- `Sources/Services/Speech/ModelManager.swift` — WhisperKit model discovery/download

**Services:**
- `Sources/Services/WindowManager.swift` — NSPanel management, expand/collapse animations
- `Sources/Services/ContentIngestor.swift` — Converts sources to engine content
- `Sources/Services/MarkdownParser.swift` — Markdown to Script/ScriptSection parsing
- `Sources/Services/Bridge/BridgeCoordinator.swift` — WebSocket bridge to Chrome extension
- `Sources/Services/Bridge/BridgeMessageTypes.swift` — Bridge message models
- `Sources/Services/Bridge/WebSocketServer.swift` — WebSocket server

**Prompter Views:**
- `Sources/Views/Prompter/PrompterContentView.swift` — Mode switch: pill/countdown/expanded
- `Sources/Views/Prompter/PrompterOverlayView.swift` — Expanded prompter: text + ear controls + status bar
- `Sources/Views/Prompter/PrompterTextView.swift` — **NSViewRepresentable** wrapping NSTextView
- `Sources/Views/Prompter/PrompterTextCoordinator.swift` — 60fps scroll/highlight interpolation
- `Sources/Views/Prompter/PrompterLayoutManager.swift` — Custom NSLayoutManager for rounded highlight rects
- `Sources/Views/Prompter/MarkdownRenderer.swift` — Inline markdown to NSAttributedString
- `Sources/Views/Prompter/PillView.swift` — Collapsed notch-camouflaged pill
- `Sources/Views/Prompter/CountdownView.swift` — 3-2-1 countdown in pill frame

**Other Views:**
- `Sources/Views/MainWindow/HomeView.swift` — Script editor, file import, Present button
- `Sources/Views/Onboarding/OnboardingView.swift` — First-run onboarding
- `Sources/Views/Settings/SettingsView.swift` — Settings tabs container
- `Sources/Views/Settings/AppearanceSettingsView.swift` — Font, spacing, opacity
- `Sources/Views/Settings/BehaviorSettingsView.swift` — Countdown, auto-expand
- `Sources/Views/Settings/SpeechSettingsView.swift` — Provider, model selection

**Utilities:**
- `Sources/Utilities/Constants.swift` — App constants, animation durations
- `Sources/Utilities/ScreenDetector.swift` — Notch detection, screen frames
- `Sources/Utilities/CodableRect.swift` — Codable NSRect wrapper

## What's Working

1. **App lifecycle**: Launch → HomeView → load script → Present → countdown → expand → prompter → collapse → pill → expand
2. **Pill/notch camouflage**: Pill overlaps the MacBook camera notch, expand button extends left
3. **Expand/collapse animations**: Smooth animations growing from notch position
4. **Speech recognition**: Apple Speech provider delivers incremental words correctly via SFSpeechRecognizer with 55-second session rotation
5. **Basic phrase matching**: The engine's two-layer matching (phrase + single-word) DOES work when the user reads the script in order from the beginning — confirmed in debug logs
6. **Word highlighting**: Rounded-corner highlight with soft glow via custom PrompterLayoutManager
7. **Text drop shadow**: NSShadow on all prompter text for depth
8. **Smooth scrolling**: 60fps Timer-based interpolation with alpha blending
9. **Keyboard shortcuts**: Space (pause/resume), arrows (nudge when paused), Cmd+Enter (present)
10. **Menu bar**: Status item with slide info, pause, stop
11. **File import**: Drag-and-drop or file picker for .md/.txt files
12. **Manual text entry**: TextEditor with live preview
13. **Settings**: Appearance, behavior, speech tabs with UserDefaults persistence
14. **Recovery wiring**: `attemptRecovery()` is now called from the tick timer when `isLost` is true

## What's Broken / Needs Fixing

### BUG 1: Engine gets stuck / stalls on common words (CRITICAL) — ✅ FIXED

**Status (2026-08-17): fixed in `SpeechToScrollEngine.advanceTo()`**, which now retains only the
most recent spoken word instead of the whole stale window:

```swift
if let last = spokenBuffer.last {
    spokenBuffer = [last]      // keep the newest word so phrase matching can rebuild
} else {
    spokenBuffer = []
}
```

The original analysis below is kept for the reasoning; the prescribed one-line fix is superseded.


**Symptom**: Tracking advances for a while then freezes. In the latest test, it got stuck at cursor position 12 after matching "buddy victor solution" at position 9. The user kept reading ("per", "of", "pros"...) but no further matches fired.

**Root cause from debug log analysis**: The phrase buffer (6-word rolling window) retains stale words from previous matches. After "buddy victor solution" matched at position 9, the buffer contains `["on", "board", "buddy", "victor", "solution", "per"]`. The engine searches `matchWords[10..37]` (cursor 12 + nearWindow 25) for the phrase, but the buffer has 5 stale words and only 1 new word. The 3-word phrase subsets extracted from the buffer are all stale combinations that don't match the script going forward.

**The core design flaw**: The phrase buffer should be cleared (or partially cleared) after a successful match, so new words can build a fresh phrase. Currently, old matched words persist in the buffer and poison future phrase matching.

**Suggested fix**: In `advanceTo()`, clear the spoken buffer so the next phrase match starts fresh:
```swift
private func advanceTo(_ position: Int) {
    cursorPosition = min(position, totalWords)
    scrollPosition = Double(cursorPosition)
    lastMatchTime = Date()
    isLost = false
    spokenBuffer = []  // ← ADD THIS: clear buffer after successful match
    updateSlideIndex()
}
```

This is a one-line fix. It means after every successful match, Layer 2 (single-word exact match for next 5 words) handles the first 1-2 words, then once the buffer refills to 3+, phrase matching takes over again. This prevents stale words from poisoning future matches.

### BUG 2: Visual artifacts on highlight (MODERATE)

**Symptom**: Visual artifacts/glitches on the text when the highlight moves to a new word.

**Likely cause**: The custom PrompterLayoutManager draws rounded rects with a glow effect. When the highlight moves, the old highlight position may not be fully invalidated/redrawn. The `removeTemporaryAttribute` call in `updateHighlight()` removes the attribute, but the custom `fillBackgroundRectArray` override may leave stale glow pixels.

**The text system was changed from default to manual creation in this session:**
```swift
// BEFORE (worked):
let textView = NSTextView()

// AFTER (current):
let textStorage = NSTextStorage()
let layoutManager = PrompterLayoutManager()
textStorage.addLayoutManager(layoutManager)
let textContainer = NSTextContainer()
textContainer.widthTracksTextView = true
textContainer.lineFragmentPadding = 0  // ← This changes line layout
layoutManager.addTextContainer(textContainer)
let textView = NSTextView(frame: .zero, textContainer: textContainer)
```

**Possible fixes to investigate:**
1. After removing old highlight, call `layoutManager.invalidateDisplay(forCharacterRange:)` on the old range to force redraw
2. The `lineFragmentPadding = 0` changes line layout compared to the default (5.0) — the original code may have had the default padding
3. The glow rect extends 4px beyond the word bounds (`insetBy(dx: -4, dy: -4)`) — if the text view doesn't redraw that area when the highlight moves, artifacts remain

### BUG 3: First launch pill positioning (MINOR)

**Symptom**: The pill is mis-shaped/positioned on first launch, but correct after collapse/expand.

**Likely cause**: `showPill()` sets the panel frame to `notchFrame(for:)`, but the content view may not be laid out yet when the panel first appears. After collapse/expand, the content is properly laid out.

## Tokenization Alignment (Important Context)

The engine and text view MUST tokenize words identically or scroll positions won't match highlights:

- **Engine** (`SpeechToScrollEngine.loadScript`): Splits `section.text` (raw, with markdown) by whitespace → normalizes with `TextNormalizer.normalize()` for matching
- **Text view** (`PrompterTextView.rebuildContent`): Renders markdown first via `MarkdownRenderer.render()` (strips `**`/`*` markers), then splits the RENDERED string by whitespace

This works because `**bold**` becomes `bold` in rendered text, and `TextNormalizer.normalize("**bold**")` strips the asterisks via `trimmingCharacters(in: .punctuationCharacters)`. Word COUNT is the same. But if markdown ever produces different whitespace, this alignment breaks.

## Session Changes Made

Changes made during this multi-session arc:

1. **Extracted `PrompterTextCoordinator`** from PrompterTextView (was inline)
2. **Extracted `MarkdownRenderer`** from PrompterTextView (was inline)
3. **Created `PrompterLayoutManager`** — custom NSLayoutManager for rounded highlight with glow
4. **Changed text system creation** from default `NSTextView()` to manual `NSTextStorage → PrompterLayoutManager → NSTextContainer → NSTextView(frame:textContainer:)`
5. **Added NSShadow** to all prompter text attributes
6. **Added `lineFragmentPadding = 0`** to the text container
7. **Removed highlight character padding** — visual expansion now handled by PrompterLayoutManager instead of expanding the character range
8. **Widened Layer 2 search** from 3 → 5 words
9. **Added `attemptRecovery()`** overload using internal spoken buffer
10. **Wired recovery** into AppState tick timer
11. **Added diagnostic debug logging** in `processOneWord()`
12. **Cleaned up dead code**: removed unused constants, extracted `formatTime()` to AppConstants
13. **Fixed CountdownView** shape to match pill shape
14. **Fixed green dot** to be pause-aware in PrompterContentView

## Debug Log

Debug output goes to `/tmp/cueprompt-debug.log` and `os_log`. Key prefixes:
- `[Engine]` — Script load, phrase matches, recovery
- `[SpeechCoordinator]` — Provider lifecycle, heard words
- `[AppleSpeech]` — Recognition session, auth, errors
- `[AppState]` — Init

## Build & Run

```bash
swift build                  # Debug build
.build/debug/CuePrompt       # Run directly
# OR
make build   # Release universal (binary at .build/apple/Products/Release/CuePrompt)
make install # Install to /Applications
```

## What to Do Next (Priority Order)

1. ~~**Fix the stale buffer bug**~~ — done, see BUG 1 above.
2. **Fix highlight artifacts** — Investigate adding `invalidateDisplay` call when removing old highlight, or revert `lineFragmentPadding` to default 5.0
3. **Remove verbose debug logging** — The `[Engine] word:` log in `processOneWord` is useful for debugging but very noisy. Remove after tracking is confirmed working.
4. **Polish**: Animation jitter on expand/collapse, first-launch pill positioning
