# Releasing TinyStats

Distribution is **GitHub Releases → `.dmg`**, consumed by three channels:

| Channel        | Link / command                                                                 |
|----------------|--------------------------------------------------------------------------------|
| Website button | `https://github.com/cringe-tech/tiny-stats/releases/latest/download/TinyStats.dmg` |
| Homebrew       | `brew install --cask cringe-tech/apps/tinystats`                                |
| In-app updates | `UpdateChecker` reads the latest release and offers its `.dmg`                  |

The dmg asset is intentionally named `TinyStats.dmg` (unversioned) so the `latest/download`
link is stable; the version lives in the release tag.

> The build is **ad-hoc signed, not notarized**. Gatekeeper will warn on a plain double-click
> (right-click → Open, or System Settings → Privacy & Security → *Open Anyway*). The Homebrew
> cask strips the quarantine flag in `postflight`, so `brew install` launches cleanly.
> Switching to Developer ID + notarization later removes all of this — see *Going notarized*.

## Cut a release

1. Bump the version in `Resources/Info.plist` (`CFBundleShortVersionString`), commit.
2. Tag and push:
   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```
3. `.github/workflows/release.yml` builds the dmg on a macOS runner, publishes the GitHub
   Release with auto-generated notes, and prints the `sha256` to the run summary.

Build a dmg locally to check before tagging:
```sh
Scripts/dmg.sh           # -> dist/TinyStats.dmg  (+ prints version & sha256)
```

## Homebrew tap (one-time setup)

The official `homebrew-cask` won't take an un-notarized app, so use a personal tap.

1. Create a public repo **`cringe-tech/homebrew-apps`** (the tap is addressed as `apps`, so
   the install path reads `cringe-tech/apps/tinystats`).
2. Copy `Casks/tinystats.rb` (this repo) into `Casks/tinystats.rb` of the tap.
3. To auto-bump the cask on every release, in **tiny-stats** repo settings add:
   - Variable `HOMEBREW_TAP_REPO` = `cringe-tech/homebrew-apps`
   - Secret `HOMEBREW_TAP_TOKEN` = a PAT with `repo` scope on the tap.

   The release workflow then clones the tap, runs `Scripts/update-cask.sh`, and pushes the
   bump. Without these it simply skips the step.

Users then install with:
```sh
brew install --cask cringe-tech/apps/tinystats
```
The cask's `postflight` strips the download quarantine, so no `--no-quarantine` is needed.
Until notarized, a plain `.dmg` double-click still needs *Open Anyway* — Homebrew avoids that.

## Going public (checklist)

The repo is currently **private**. Public download links and Homebrew need it public:

- [ ] Make `cringe-tech/tiny-stats` public.
- [ ] Cut a real release tag (verify the dmg downloads and launches from another Mac).
- [ ] Create the tap repo and wire the `HOMEBREW_TAP_*` variable/secret.
- [ ] Point the website Download button at the `latest/download` link above.

## Going notarized (later)

Requires Apple Developer Program ($99/yr). Then:

1. Add secrets: `Developer ID Application` cert (.p12 + password), and an
   `notarytool` App Store Connect API key (or Apple ID app-specific password).
2. In `Scripts/bundle.sh`, replace the ad-hoc `codesign --sign -` with
   `codesign --sign "Developer ID Application: …" --options runtime --timestamp`.
3. After `Scripts/dmg.sh`, `xcrun notarytool submit dist/TinyStats.dmg --wait` then
   `xcrun stapler staple dist/TinyStats.dmg`.
4. Drop the `--no-quarantine` and the `postflight` quarantine strip from the cask.
