set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Run SlapsKit's tests (headless)
test:
    swift test

# Regenerate Slaps.xcodeproj from project.yml
gen:
    xcodegen generate --use-cache

# Build the macOS app
build: gen
    xcodebuild -project Slaps.xcodeproj -scheme Slaps build

# Link slaps in ~/.local/bin to the app in /Applications, as Settings › General does
install-cli:
    mkdir -p ~/.local/bin && ln -sf /Applications/Slaps.app/Contents/MacOS/Slaps ~/.local/bin/slaps
    @echo "slaps is in ~/.local/bin; try: slaps help"

# Build and launch the app
run: build
    open "$(xcodebuild -project Slaps.xcodeproj -scheme Slaps -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/Slaps.app"

# Launch a Debug build in the background, listening on a socket for scripts/debug.py to drive (snapshots, menus),
# without taking focus; files are opened with it
[positional-arguments]
debug-app *files: build
    mkdir -p "$HOME/Library/Application Support/Slaps"
    rm -f "$HOME/Library/Application Support/Slaps/debug.sock"
    open -n -g --env DEBUG_SOCKET="$HOME/Library/Application Support/Slaps/debug.sock" -a "$(xcodebuild -project Slaps.xcodeproj -scheme Slaps -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/Slaps.app" "$@"
    scripts/debug.py ping >/dev/null && echo "Slaps is listening; try: just debug snapshot out.png"

# Remake the README's screenshots in docs/screenshots, from a Debug build showing made-up meetings (SLAPS_DEMO)
screenshots: build
    #!/usr/bin/env bash
    set -euo pipefail
    out=docs/screenshots; mkdir -p "$out"
    sock="$HOME/Library/Application Support/Slaps/screenshots.sock"
    debug() { scripts/debug.py --socket "$sock" "$@"; }
    rm -f "$sock"
    # The demo keeps its own settings (tech.phin.slaps.demo); start them afresh, so the pictures show the defaults.
    defaults delete tech.phin.slaps.demo >/dev/null 2>&1 || true
    open -n -g --env DEBUG_SOCKET="$sock" --env SLAPS_DEMO=1 -a "$(xcodebuild -project Slaps.xcodeproj -scheme Slaps -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/Slaps.app"
    trap 'debug quit >/dev/null 2>&1 || true' EXIT
    debug ping >/dev/null
    # The demo's design review starts a minute after launch, so its alert is up within the lead time; or put one up.
    for _ in $(seq 1 20); do debug state | grep -q 'Design review' && break; sleep 1; done
    debug state | grep -q 'Design review' || debug alert >/dev/null
    debug --wait 1 snapshot "$PWD/$out/alert.png" "Slaps alert" >/dev/null
    # The same alert as a banner, in the Custom theme's colours.
    debug style top >/dev/null
    debug theme custom >/dev/null
    debug --wait 1 snapshot "$PWD/$out/banner.png" "Slaps alert" >/dev/null
    debug style fullScreen >/dev/null
    debug theme midnight >/dev/null
    debug dismiss >/dev/null
    debug popover >/dev/null
    debug --wait 1 snapshot "$PWD/$out/menu-bar.png" 0 >/dev/null
    debug popover >/dev/null
    debug onboarding >/dev/null
    debug --wait 1 snapshot "$PWD/$out/welcome.png" "Welcome to Slaps" >/dev/null
    debug menu Slaps "Settings…" >/dev/null
    debug --wait 1 snapshot "$PWD/$out/settings.png" General >/dev/null
    # The alert is the size of the screen; the README doesn't need all of it.
    sips -Z 1600 "$out/alert.png" >/dev/null
    sips -Z 1600 "$out/banner.png" >/dev/null
    ls -1 "$out"

# Send a command to the Debug build started by debug-app (try: just debug help)
[positional-arguments]
debug *args:
    @scripts/debug.py "$@"

# Remove build artifacts and the generated Xcode project
clean:
    rm -rf .build DerivedData Slaps.xcodeproj

# The release recipes (release-check, doctor, bump, ship and the rest): app-release, in release.just, which
# apple-template keeps up to date
import 'release.just'
