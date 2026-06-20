# Contributing to tiny-stats

Thanks for taking the time to contribute! tiny-stats is a small, focused macOS menu bar
system monitor, and contributions of all sizes are welcome — bug reports, fixes, docs and
features.

## Before you start

- For anything non-trivial, **open an issue first** so we can agree on the approach before
  you write code: <https://github.com/cringe-tech/tiny-stats/issues>.
- Keep the scope tight. tiny-stats deliberately stays minimal and HIG-friendly; features
  that add weight, telemetry, or background work need a good justification.
- v1 is **monitoring only** (read-only). Fan control / anything that writes to the SMC is
  out of scope until phase 2 (see the Roadmap in the README) — please don't send PRs for it.

## Building

**Xcode is not required** — the Command Line Tools and a Swift 6 toolchain are enough.

```sh
# Run straight from SwiftPM (debug):
swift run TinyStats

# Build a proper TinyStats.app bundle (ad-hoc signed):
Scripts/bundle.sh --debug      # debug build
Scripts/bundle.sh              # release build
open TinyStats.app
```

The app is a menu bar agent (`LSUIElement`) — no Dock icon. Quit from the popover's **Quit**
button or `⌘Q`.

## Tests

The math-heavy and table-driven parts run as an offline self-test (no Xcode/XCTest):

```sh
swift run TinyStatsSelfTest          # offline unit checks (CPU/network math, sensor tables)
swift run TinyStatsSelfTest --live   # sample the real engine once (incl. SMC sensors)
swift run TinyStatsSelfTest --smc    # dump raw SMC keys for debugging
```

Please run `swift build` and `swift run TinyStatsSelfTest` before opening a PR, and add or
update checks in `Sources/TinyStatsSelfTest` when you touch the parsing/formatting/sensor
logic.

## Code style

- Match the surrounding code — naming, spacing, and comment density. Don't reformat or
  refactor unrelated code in the same change.
- Prefer the smallest change that solves the problem; avoid speculative abstractions.
- Comments should explain *why* something non-obvious is done, not restate the code.
- New user-facing strings go through the `Loc` localization layer
  (`Sources/TinyStats/Localization.swift`) — add a key and translations for all supported
  languages (fall back to English if you can't translate, and note it in the PR).

## Project layout

```
Sources/
  CSMC/              read-only C bridge to the AppleSMC IOKit service
  SMCKit/            SMC connection, sensor discovery, naming tables, classifier
  TinyStatsCore/     collectors (CPU/mem/net/disk/gpu/battery/processes) + polling engine
  TinyStats/         SwiftUI app: menu bar label, popover, settings, view models
  TinyStatsSelfTest/ offline test runner
```

## Pull requests

- Branch off `main`, keep PRs focused on a single concern.
- Describe **what** changed and **why**; link the issue it addresses.
- Make sure the build is clean and the self-test passes.
- By contributing, you agree your contributions are licensed under the project's
  [MIT License](LICENSE).

## Reporting bugs & ideas

Open an issue: <https://github.com/cringe-tech/tiny-stats/issues>. For bugs, include your
macOS version and chip (e.g. M3 Pro / Intel), what you expected, what happened, and steps to
reproduce. Sensor naming issues are especially helpful with the output of
`swift run TinyStatsSelfTest --smc`.
