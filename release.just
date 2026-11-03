# Release tooling: app-release (https://git.phin.tech/sam/app-release), pinned in scripts/release and run with uv;
# release.toml says what it needs to know. Each recipe takes --dry-run, which checks and reads but only prints what it
# would change.
# `just release-tool --help` lists it all. The project's justfile has `import 'release.just'`; apple-template keeps
# this file up to date (`copier update`), so recipes of the project's own go in the justfile.
release_tool := "uv run --quiet --project scripts/release app-release"

# Run app-release directly
[positional-arguments]
release-tool *args:
    {{release_tool}} "$@"

# Check release.toml and the version files (no network, changes nothing)
release-check:
    {{release_tool}} check

# Check everything a release needs outside the repo: tools, GitHub, 1Password, certificates
[positional-arguments]
doctor *args:
    {{release_tool}} doctor "$@"

# Once: create the public GitHub repo phin-tech/slaps, push main to it, then run doctor
bootstrap:
    gh repo view phin-tech/slaps >/dev/null 2>&1 || gh repo create phin-tech/slaps --public --source . --push --description {{quote("Full-screen meeting alerts you cannot miss")}}
    {{release_tool}} doctor

# Draft release-notes/<version>.md with a cheap model, from the commits since the last release (patch, minor, major, beta [--of patch], or a version)
[positional-arguments]
notes *args:
    {{release_tool}} notes "$@"

# Bump the version (major, minor, patch, or beta: 0.6.1 -> 0.7.0-beta.1 -> -beta.2; beta --of patch: 0.6.2-beta.1) everywhere and the build number; build: only the build number
[positional-arguments]
bump part *args:
    {{release_tool}} bump "$@"

# Build, sign with Developer ID, notarize and staple Slaps.app headless
[positional-arguments]
notarize *args:
    {{release_tool}} notarize "$@"

# Publish the newest notarized Slaps.app (from `just notarize` or Xcode's Distribute App), or a given app, as a GitHub release
[positional-arguments]
release *args:
    {{release_tool}} release "$@"

# Make and upload the Sparkle appcast for a published release (default: the current version); `just release` does this
[positional-arguments]
appcast *args:
    {{release_tool}} appcast "$@"

# The whole release: bump, commit, push, notarize, GitHub release, appcast (`ship beta [--of patch|major]`: a pre-release). Ship from main
[positional-arguments]
ship part *args:
    {{release_tool}} ship "$@"
