# Todo

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
