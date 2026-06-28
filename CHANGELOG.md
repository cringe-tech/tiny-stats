# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] — 2026-06-29

### Added
- **Fan control** — a new *Fan Control* tab in Settings lets you manage fan speed with
  presets (Cool-touch / Balanced / Turbo / Auto) or a custom temperature→speed curve.
  The curve editor shows the live temperature marker and plays a haptic tick on every
  integer step while dragging.
- **Sensor source picker** — choose whether the fan curve follows CPU, GPU or
  Power+Battery temperature (useful when charging from a low state of charge heats the
  machine more than CPU load does).
- **Turbo-while-gaming** — opt-in toggle that switches to Turbo automatically whenever
  macOS Game Mode is active, then reverts when the game exits.
- **Privileged helper** (`TinyStatsFanHelper`) installed once with an admin-password
  prompt. The helper enforces `[F{i}Mn, F{i}Mx]` RPM clamps, a 6-second heartbeat
  watchdog (reverts to Auto on silence), and SIGTERM/connection-loss revert — a stuck
  speed cannot outlive the app session.
- Self-test coverage for fan-curve interpolation, preset shapes, and RPM mapping
  (`swift run TinyStatsSelfTest`).

## [0.1.0] — 2026-06-17

First public release.

### Added
- Menu bar cells for up to 5 metrics (CPU, GPU, memory, network, disk, battery) with a
  drag-to-customize editor and per-cell display modes (icon / label / value).
- Dropdown with Overview, History and Sensors tabs; configurable top-N process lists per
  section; human-readable SMC sensor names per Apple-Silicon generation and Intel.
- Automatic collapse of the leftmost menu bar cells when the notch would clip the status
  item, with a "…" indicator and a Settings warning.
- Diagnostic logging to `~/Library/Logs/TinyStats` (rotated, with crash/signal capture),
  exportable from Settings → General → Diagnostics.
- Multi-language UI, GitHub-release update check, and launch-at-login.
- Distribution: `.dmg` packaging, a GitHub Actions release pipeline, and a Homebrew cask
  (`brew install --cask cringe-tech/apps/tinystats`).

[Unreleased]: https://github.com/cringe-tech/tiny-stats/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/cringe-tech/tiny-stats/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cringe-tech/tiny-stats/releases/tag/v0.1.0
