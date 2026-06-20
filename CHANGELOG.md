# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/cringe-tech/tiny-stats/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cringe-tech/tiny-stats/releases/tag/v0.1.0
