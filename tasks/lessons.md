# Lessons

## Ranges built from two tokenizations trap at runtime

`cursorPosition..<index.wordCount` is a crash, not a mismatch, when the bounds come from
different word arrays — Swift traps with "Range requires lowerBound <= upperBound". It stayed
hidden because it only inverts once the cursor passes the *shorter* array's length, i.e. at the
end of a long script. Symptoms that look like "random crash after a while" are worth checking
for range construction on a hot timer path. Keep one index space (`displayWords`) and clamp at
the boundary as well as fixing the source.

## Timers whose only invalidation is `deinit` never stop

`PrompterTextCoordinator` scheduled a 60fps Timer in `updateNSView` and invalidated it only in
`deinit`, so it kept running while paused, collapsed, or hidden. For `NSViewRepresentable`, tear
down in `dismantleNSView` — it runs when the view leaves the hierarchy, rather than waiting for
SwiftUI to release the coordinator.

## Don't resolve state inside a detached Task you're tearing down

`Task { await activeProvider?.stopListening(); activeProvider = nil }` reads the property when
the Task *runs*, so a stop-then-start sequence stops the new object. Capture the reference
synchronously, then await the captured value.

## No crash report means look for a hang

`~/Library/Logs/DiagnosticReports` had no `.ips` for the app at all, which pointed away from a
signal crash toward a main-thread stall — and the app has two always-on timers plus a hot mic to
account for. (The real crash turned out to be a Swift trap, which also may not leave a report.)
Also note `/tmp/cueprompt-debug.log` gets written by the *test suite*, so a stale log there is not
evidence about the running app.

## Never push code straight to `main`

`.github/workflows/release.yml` fires on every push to `main` that touches a non-`.md` file: it
tags `v$VERSION`, signs, notarizes, and publishes a **public** GitHub Release, auto-bumping the
patch if the tag exists. Branch and PR for anything that isn't a root-level markdown edit.

## SwiftLint: probing with an out-of-tree config silently lints nothing

`swiftlint lint --config /tmp/probe.yml` where the config has relative `included:` paths resolves
them against the config's location, not the repo — it reports "0 violations" instead of erroring.
When probing rules with a temp config, pass the paths explicitly:
`swiftlint lint --config /tmp/probe.yml Sources Tests`.

## Relax lint rules for tests with a nested config, not a global disable

`Tests/.swiftlint.yml` with `parent_config: ../.swiftlint.yml` inherits the root config and lets the
test target disable `force_unwrapping` on its own. Caveat: a child's `disabled_rules` replaces the
parent's list rather than appending, so restate the parent's entries.

## Set lint `error:` thresholds above the current worst offender

CI fails only on `error`-severity violations. Picking thresholds from the measured baseline (rather
than aspirational values) means linting lands green and existing debt shows up as warnings you can
ratchet down, instead of a red pipeline everyone learns to ignore.

## Docs in this repo disagree; know the hierarchy

`CLAUDE.md` + `README.md` are current. `SESSION-STATUS.md` is an April 2026 snapshot (now
bannered), and `CueFlow-Engineering-Spec.md` is the pre-implementation spec — it still calls the app
"CueFlow" and predates the landmark-matching design entirely. Verify against code before trusting
either.
