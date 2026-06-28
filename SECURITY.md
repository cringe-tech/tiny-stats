# Security Policy

## Reporting a vulnerability

Please report security issues **privately** via GitHub's
[private vulnerability reporting](https://github.com/cringe-tech/tiny-stats/security/advisories/new)
(the repo's **Security** tab → **Report a vulnerability**). Do not open a public issue for a
security report.

We aim to acknowledge within a few days and to ship a fix promptly.

## Threat model / scope

TinyStats is a menu bar monitor that is **read-only by default**:

- It writes nothing to disk except its own `UserDefaults` and a local diagnostic log
  (`~/Library/Logs/TinyStats`), which never leaves the machine.
- Sensor access via `Sources/CSMC` is read-only **unless Fan Control is enabled** (see below).
- The only outbound network request is an unauthenticated `GET` to `api.github.com` for the
  update check, which can be disabled in Settings.
- Process sampling uses `libproc` and only sees the current user's processes.
- The only always-on privileged integration is the optional launch-at-login item
  (`SMAppService`).

Builds are currently ad-hoc signed (not yet Developer ID-notarized). Only install builds from
the official [Releases](https://github.com/cringe-tech/tiny-stats/releases) page or the
Homebrew cask.

## Fan control (opt-in, off by default)

Enabling Fan Control installs a privileged LaunchDaemon — `TinyStatsFanHelper`, the **only**
component that writes SMC keys — via a one-time admin-password prompt (no Developer ID). The
app talks to it over XPC; all curve/preset logic stays in the app, while the helper owns
hardware safety:

- **Value clamping** — every target RPM is clamped to the fan's own `[F{i}Mn, F{i}Mx]` range,
  so no caller can drive a fan past its hardware limits.
- **Fail-safe revert to Auto** — the helper reverts all fans to system (Auto) control on
  connection loss/invalidation, on `SIGTERM` (launchd unload), and via a heartbeat watchdog
  (~6 s) if the app stops responding. A stuck forced speed cannot outlive a normal app quit,
  crash, or daemon unload.
- **XPC peer validation** — the helper enforces a code-signing requirement
  (`NSXPCConnection.setCodeSigningRequirement`, audit-token based) so an arbitrary local
  process can't reach the root daemon.

**Known limitations (residual risk):**

- *Ad-hoc signing makes peer validation best-effort.* The requirement pins the packaged app's
  signing identifier, but an ad-hoc signature isn't anchored to a trusted authority, so a local
  attacker who already runs code as the user could ad-hoc-sign a binary with the same
  identifier and reach the daemon. The helper-side clamp + watchdog remain the real safety
  boundary; the worst a forged caller can do is move fans *within* their hardware-safe range.
  This is resolved by moving to Developer ID signing and a team-ID/anchor requirement.
- *`SIGKILL` bypasses the graceful revert.* The watchdog runs inside the helper, so if the
  helper is force-killed (`SIGKILL`) while the app is also gone, fans can remain in their last
  forced state until the app reconnects (it then reverts within ~2 s) or the Mac reboots.
  Graceful unload (`launchctl bootout`, app quit) is unaffected.

If you have Fan Control concerns specifically, please include your Mac model and macOS version
in the report.

## Supported versions

Only the latest release receives fixes.
