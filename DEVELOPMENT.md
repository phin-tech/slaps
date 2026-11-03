# Developing Slaps

## Building

Needs Xcode 26.6 or later, [xcodegen](https://github.com/yonaskolb/XcodeGen), [just](https://just.systems)
and, for releasing, [uv](https://docs.astral.sh/uv/), `gh` and the 1Password CLI `op`:
`brew install xcodegen just uv gh 1password-cli`.

```sh
just build           # generate the Xcode project and build the app
just run             # build and launch it
just test            # SlapsKit's tests, headless
just release-check   # release.toml and the version files make sense
```

`Slaps.xcodeproj` is generated from `project.yml` and gitignored, so change settings there, not in Xcode. The
same goes for the Info.plists and entitlements in `Generated/` (also gitignored), which xcodegen writes from
`project.yml`'s `info` and `entitlements` properties.

**Signing.** Builds are signed to run locally unless a gitignored `Signing.local.xcconfig` sets `DEVELOPMENT_TEAM`
and `CODE_SIGN_IDENTITY = Apple Development` (see `Signing.xcconfig`). Set the team there rather than in Xcode's
Signing & Capabilities pane, which is lost when the project is regenerated.

**Looking at the running app.** `just debug-app` builds and launches a Debug copy in the background, listening on
`~/Library/Application Support/Slaps/debug.sock`; `just debug <command>` drives it with `scripts/debug.py`.
`just debug snapshot out.png` renders the front window to a PNG (the app draws it itself, so no screen-recording
permission is needed), `just debug windows` lists the windows, `just debug menu File "New Window"` chooses a menu item,
and `just debug quit` quits it. `just debug help` lists the rest. The driver (`App/DebugDriver.swift`) is only
compiled into Debug builds and only listens when the app is launched with `DEBUG_SOCKET` set.

## Releasing

**One command:** `just ship patch` (or `minor`, `major`, `beta`). It bumps the version (`just bump`), commits and
pushes to `main`, builds the app headless, signs it with the Developer ID Application certificate, notarizes it with
Apple and staples the ticket (`just notarize`), then publishes the GitHub release, its Sparkle appcast (`just release`). Write `release-notes/<next version>.md` first for curated notes: `just notes patch` (or `minor`, `beta --of patch`, …) drafts it with a cheap model on OpenRouter from the commits since the last release, to read and edit. It must run on a Mac
with the certificate in its keychain, from a clean, pushed `main`. Every release recipe takes `--dry-run`, which runs
the checks and reads but only prints what it would change: `just ship beta --dry-run`.

**Betas.** `just ship beta` makes the next beta: from 0.6.1, `0.7.0-beta.1`, then `-beta.2`. For a beta of a
patch or a major instead, `just ship beta --of patch` (0.6.1 → `0.6.2-beta.1`) or `--of major` (`1.0.0-beta.1`);
later betas carry on with plain `just ship beta`, and `just ship patch` releases it. A beta is a GitHub
pre-release, so GitHub's "latest", the download link stay on the last release. Its appcast entry
is added to the latest release's appcast in Sparkle's `beta` channel, which only copies with Settings › Updates › Get
beta versions turned on take (on by default in a beta build). A later `just ship minor` (or `patch`) releases the
beta's version, `0.7.0`, and beta testers move on to it, since the build number only goes up. A beta needs a release
to join, so the first thing shipped must be a release.

**The tooling** is [app-release](https://git.phin.tech/sam/app-release), shared with Dottie and every app made from
the same template: a Python program pinned to a tag in `scripts/release/pyproject.toml` and run with uv, which fetches it
with your git credentials for git.phin.tech. What it knows about Slaps is in `release.toml`. Versions are written
by [bump-my-version](https://github.com/callowayproject/bump-my-version) (`.bumpversion.toml` lists the files), and
the appcast by Sparkle's own `generate_appcast`. Settings come from the environment (`NOTARY_OP_ITEM`,
`DEVELOPMENT_TEAM`, `NOTARY_PROFILE`), so a build machine can run it unattended; `op` works there with a 1Password
service account (`OP_SERVICE_ACCOUNT_TOKEN`). `just doctor` checks everything it needs outside the repository.

Credentials come from 1Password (`op://Development/lc6wrq7lltjd47uue26cdxttzu`: `apple_id`, `team_id`, `app_specific_password`, `p12` and
`p12_passphrase` (the Developer ID certificate), and `sparkle_private_key`), so a Mac needs only the 1Password CLI signed in (`op signin`) to release. The certificate
goes into a keychain made for each run and deleted afterwards; without `p12` in the item, the login keychain's is used.
To keep the secrets in Infisical, or in a CI tool's environment, instead, add `[secrets]` to `release.toml` (see
app-release's README). Without any notarization credentials, `just notarize` falls
back to a notarytool keychain profile: `xcrun notarytool store-credentials slaps-notary --apple-id <apple id>
--team-id J35P7AJDN7`.

The steps by hand, if one fails halfway:

1. `just bump patch`, commit and push.
2. `just notarize` (or in Xcode: Product ▸ Archive, then Distribute App ▸ Direct Distribution). It leaves the app in
   `build/release/<version>/export/Slaps.app`. Run again, it redoes only the stages (archive, export,
   notarize) whose inputs changed, so a rejected or interrupted notarization doesn't archive again; `--verbose` shows
   xcodebuild's full output.
3. `just release` (or `just release <path to Slaps.app>`; with no argument it takes the newest notarized app):
   checks it is a stapled, notarized Developer ID build of the version in `project.yml` and that `main` is clean and
   pushed, then publishes `Slaps-<version>.zip` as a GitHub release tagged `v<version>`. Then it makes the
   appcast (`just appcast` redoes that).

## Updates

The app updates itself in place with [Sparkle](https://sparkle-project.org) (`App/UpdateChecker.swift`). Its feed,
`SUFeedURL`, is `releases/latest/download/appcast.xml`: an asset of the newest release (GitHub skips drafts and
pre-releases), made by Sparkle's `generate_appcast` in `just appcast`. Entries are signed with the EdDSA key in
1Password (`sparkle_private_key`, given to the tool on stdin; the public half is `SUPublicEDKey` in `project.yml`), so
installed copies only accept updates signed by it. Do not lose or replace that key: copies already out there would
reject every later update. `just appcast` checks every entry is signed and the new one verifies before it uploads.
Sparkle's tools are downloaded, pinned, into `~/Library/Caches/app-release`. Debug builds do not check for updates.

## First release

Once, before the first `just ship`:

1. `just bootstrap`: creates the GitHub repository `phin-tech/slaps` (public: Sparkle and Homebrew download the
   release zips without credentials), pushes `main` to it, and runs `just doctor`, which checks `gh`,
   every 1Password field and the Developer ID certificate.
2. Fix whatever `just doctor` lists, and run it again until it is clean.
3. The Sparkle key in `op://Development/lc6wrq7lltjd47uue26cdxttzu` must be the other half of `SUPublicEDKey` in `project.yml` (`just appcast` checks
   this before uploading anything). For a key of its own, run Sparkle's `generate_keys -x <file>` from
   `~/Library/Caches/app-release/sparkle/*/bin`, put the private key in a new item, and switch to it with
   `uvx copier update --defaults -d op_item=<item> -d sparkle_public_key=<public key>`.

Then `just ship minor --dry-run`, and if that reads right, `just ship minor`.
