# Todo

## 2026-08-19 — Crash/hang after finishing a speech (branch `fix/recovery-index-space`)

Reported: app crashes or stops responding after finishing a full speech, clicking pause, and
sitting in the background. Intermittent, hard to reproduce.

- [x] **Root cause (crash): recovery index built in the wrong index space.** `LandmarkIndex` came
      from `TextNormalizer.normalizeText(text)` (fillers dropped, numbers expanded) while
      `cursorPosition` walks `displayWords`. `attemptRecovery` built
      `cursorPosition..<index.wordCount` from both, which **traps** once the cursor passes the
      shorter count — i.e. at the end of a script, ~15s after the speaker stops, when the tick
      timer fires recovery. Reproduced deterministically, then fixed by indexing `matchWords`.
- [x] **Recovery ran while paused** — the 1s tick calls `attemptRecovery()` whenever `isLost` is
      set, with no pause guard, so it re-scanned the script every second and could jump the
      cursor under a stopped speaker. Added the guard; `resume()` now clears `isLost`.
- [x] **60fps interpolation timer never stopped** — scheduled in `updateNSView`, invalidated only
      in `deinit`. Now stopped while paused and in `dismantleNSView`.
- [x] **Provider teardown race** — `stopListening()` resolved `activeProvider` inside a detached
      Task, so stop-then-start (switchProvider) killed the new provider. Captured synchronously.
- [x] 15 new tests (113 total, was 98); lint and release build clean.

### Still open — needs a product decision

**The mic stays hot while paused.** `togglePause()` calls `engine.pause()` but never
`speechCoordinator.stopListening()`, so the audio engine keeps running and
`AppleSpeechProvider`'s watchdog keeps rotating recognition sessions every few seconds for as
long as the app sits paused in the background. The engine discards the words, so this is a
power/privacy cost, not a correctness bug.

Stopping the mic on pause is a one-line change in `togglePause()` (now safe, given the provider
teardown fix), but it trades instant resume for a ~200-500ms recognizer restart and would need a
real-mic test. Left for the user to choose.

## 2026-08-17 — Linting, README, doc reconciliation (branch `chore/lint-and-docs`)

Follow-on from `/init`, which refreshed `CLAUDE.md`.

- [x] **CLAUDE.md corrections** — added a CI & Releasing section (pushing non-`.md` to `main` cuts a
      release), documented that bundle `Info.plist` is generated in two places and the root one is
      dead, explained why `make setup-local-signing` matters, replaced the stale 30-line file tree
      with a compact map, added `--filter` / `Tests/Fixtures` notes, and repointed the landmark
      reference at the source files (the spec never mentions landmarks).
- [x] **SwiftLint setup** — `.swiftlint.yml` opts into the rules CLAUDE.md asserts
      (`force_unwrapping`, `function_body_length: 40`); `Tests/.swiftlint.yml` relaxes
      `force_unwrapping` for XCTest fixtures via `parent_config`. Thresholds chosen so the current
      baseline has **0 error-severity** violations, so CI is green from day one.
- [x] **Autocorrected mechanical violations** — `swiftlint --fix` touched 9 files (brace placement,
      `_` for unused closure params, redundant `= nil`). Verified: `swift build` clean,
      98 XCTest cases pass.
- [x] **CI + Makefile** — added a `lint` job to `.github/workflows/ci.yml`, plus `make lint` and
      `make lint-fix`.
- [x] **README.md** — written from scratch: install, build, speech providers, extension loading,
      dev loop, repo map, release behavior.
- [x] **SESSION-STATUS.md reconciled** — banner marking it a historical snapshot, BUG 1 marked
      fixed with the actual implementation, corrected the hardcoded `/Users/jacobsurber/...` path
      and the wrong debug binary path.

### Known debt left deliberately (warnings, not errors)

| Rule | Count | Note |
| --- | --- | --- |
| `force_unwrapping` | 15 | all in `Sources/`; CLAUDE.md forbids these, so they're real drift |
| `non_optional_string_data_conversion` | 11 | `str.data(using:.utf8)!` → `Data(str.utf8)`; not autocorrectable |
| `function_body_length` | 4 | worst: `PrompterTextView.makeNSView` at 128 lines |
| `cyclomatic_complexity` | 4 | worst: `FuzzyMatcher` and `WhisperKitProvider.start` at 14 |

Ratchet plan: fix a category, then lower the matching `error:` threshold in `.swiftlint.yml`.

### Open defects found but not fixed (need a decision)

1. **`Extension/icons/` is missing** while `manifest.json` declares `icon16/48/128.png` — Chrome
   refuses to load the unpacked extension. Either add the icons or drop the `icons` /
   `action.default_icon` keys.
2. **`AppSettings.preferredProvider` has two different defaults** — the property initializer says
   `"Apple Speech"`, but `init(from:)`'s `decodeIfPresent` fallback says `"WhisperKit"`. A fresh
   install and a settings blob missing that key disagree.
