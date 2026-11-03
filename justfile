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
