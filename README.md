# CuePrompt

A macOS-native smart teleprompter that paces itself to your voice.

CuePrompt lives as a Dynamic Island-style pill camouflaged against the MacBook camera notch. Start presenting and it expands into a full-screen prompter that scrolls in time with what you actually say — on-device speech recognition matches your words against the script, so pauses, ad-libs and re-reads don't desync you.

Scripts come from Google Slides speaker notes (via the bundled Chrome extension), typed text, or local `.md` / `.txt` files.

## Requirements

- macOS 14 (Sonoma) or later
- Microphone and Speech Recognition permissions
- Apple silicon or Intel (releases ship a universal binary)

## Install

Grab the `.dmg` from the [latest release](https://github.com/amirsalaar/CuePrompt/releases) and drag **CuePrompt.app** into `/Applications`.

If macOS blocks the app on first launch, clear the quarantine attribute once:

```bash
sudo xattr -cr /Applications/CuePrompt.app
```

On first launch, grant **Microphone** (to hear you) and **Speech Recognition** (to match words to the script). All recognition happens on-device.

## Build from source

```bash
make setup-local-signing   # once per machine — see note below
make build                 # universal release binary + app bundle
make install               # build, then install to /Applications
```

Run `make setup-local-signing` before your first build. Without a stable signing identity the build falls back to ad-hoc signing, and macOS resets your Microphone permission on **every** rebuild — which looks exactly like the app being broken.

`make help` lists the rest (`dmg`, `clean`, `test`, `lint`).

## Speech providers

Two backends, switchable in Settings → Speech:

- **WhisperKit** — on-device Whisper models, more accurate on domain jargon. Models are stored in a shared `~/Documents/Models/WhisperKit/` so they survive reinstalls and can be shared with other WhisperKit apps.
- **Apple Speech** — the system `SFSpeechRecognizer`, no download required.

## Chrome extension (Google Slides)

`Extension/` holds an unpacked MV3 extension that scrapes speaker notes from an open Google Slides deck and pushes them to the app over `ws://localhost:19876`.

To load it: Chrome → `chrome://extensions` → enable **Developer mode** → **Load unpacked** → select the `Extension/` directory.

> **Heads up:** `manifest.json` declares `icons/icon16.png`, `icon48.png` and `icon128.png`, but the `Extension/icons/` directory isn't in the repo — Chrome will refuse to load the extension until those files are added or the `icons` / `action.default_icon` keys are removed.

## Development

```bash
make test                              # swift test --parallel
swift test --filter FuzzyMatcherTests  # a single suite
make lint                              # SwiftLint (brew install swiftlint)
make lint-fix                          # autocorrect the mechanical violations
```

Drive the prompter without a microphone using simulated speech at 3 words/sec:

```bash
.build/apple/Products/Release/CuePrompt --simulate
```

Runtime diagnostics stream to a log file — tail it while presenting:

```bash
tail -f /tmp/cueprompt-debug.log
```

Prefixes: `[Engine]` (matching + recovery), `[SpeechCoordinator]` (provider lifecycle), `[AppleSpeech]`, `[AppState]`.

## Repo map

| Path | What's in it |
| --- | --- |
| `Sources/App` | `AppState`, the root coordinator that owns every service |
| `Sources/Services/Speech` | Providers plus the word-matching / scroll engine |
| `Sources/Services/Bridge` | WebSocket server for the Chrome extension |
| `Sources/Views/Prompter` | The pill, the overlay, and the AppKit text view it wraps |
| `Extension/` | Chrome MV3 companion extension |
| `scripts/`, `Entitlements/` | Build, signing, and packaging |

Further reading: [`CLAUDE.md`](CLAUDE.md) for architecture and conventions, [`DESIGN.md`](DESIGN.md) for the design system (typography, color, motion).

## Releasing

Pushing a non-`.md` change to `main` triggers `.github/workflows/release.yml`, which tests, builds, signs, notarizes, tags `v$VERSION` from the `VERSION` file, and publishes a GitHub Release with the `.zip` and `.dmg`. If the tag already exists the patch version is auto-bumped. Do code work on a branch and merge via PR.
