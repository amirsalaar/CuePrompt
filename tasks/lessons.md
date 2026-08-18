# Lessons

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
