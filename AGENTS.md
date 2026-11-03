# AGENTS.md

Slaps is a macOS app. `Sources/SlapsKit` holds everything that isn't UI and is tested headless; `App/`
is the SwiftUI app.

## Where things are explained

- `DEVELOPMENT.md`: building, signing, testing, releasing, updates.

## Done

The change is done when these pass, and your report names any you did not run:

- `just test`, always.
- `just build` for changes under `App/` or to `project.yml`.
- `just release-check` for changes to `release.toml`, `scripts/release` or `.bumpversion.toml`.

## Generated files

- `Slaps.xcodeproj` and everything in `Generated/` (Info.plists, entitlements) come from `project.yml`
  (`just gen`) and are gitignored. Change settings, Info.plist keys and entitlements there, not in Xcode.
- Version strings come from `just bump` (bump-my-version; `.bumpversion.toml` lists the files).

## Gotchas

- Xcode's build service sometimes hangs at 0% CPU. Give `xcodebuild` and `just build` a timeout.
- To see the app: `just debug-app`, then `just debug snapshot out.png`, then `just debug quit`. It drives a Debug
  build over a socket (`App/DebugDriver.swift`), so it needs no screen-recording permission. Leave other copies of
  the app running; the maintainer may have their own open.
- Sparkle is an Xcode-only dependency (project.yml); keep it out of `Package.swift`, or `swift test` would build it.
- The release tool is app-release, a separate repository pinned in `scripts/release/pyproject.toml`; change it there,
  not here.

## Releases

The maintainer releases with `just ship patch|minor|major|beta`; leave releases, version bumps and pushes to them
unless asked. Every release recipe takes `--dry-run`, which runs the checks and reads and prints the rest.
