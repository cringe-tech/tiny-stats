# Security Policy

## Reporting a vulnerability

Please report security issues **privately** via GitHub's
[private vulnerability reporting](https://github.com/cringe-tech/tiny-stats/security/advisories/new)
(the repo's **Security** tab → **Report a vulnerability**). Do not open a public issue for a
security report.

We aim to acknowledge within a few days and to ship a fix promptly.

## Threat model / scope

TinyStats is a **read-only** menu bar monitor:

- It writes nothing to disk except its own `UserDefaults` and a local diagnostic log
  (`~/Library/Logs/TinyStats`), which never leaves the machine.
- It never writes to the SMC — sensor access via `Sources/CSMC` is read-only.
- The only outbound network request is an unauthenticated `GET` to `api.github.com` for the
  update check, which can be disabled in Settings.
- Process sampling uses `libproc` and only sees the current user's processes.
- The only privileged integration is the optional launch-at-login item (`SMAppService`).

Builds are currently ad-hoc signed (not yet Developer ID-notarized). Only install builds from
the official [Releases](https://github.com/cringe-tech/tiny-stats/releases) page or the
Homebrew cask.

## Supported versions

Only the latest release receives fixes.
