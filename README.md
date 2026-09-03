<p align="center">
  <img src="./docs/assets/flodersync-icon.png" width="152" alt="FloderSync icon">
</p>

<h1 align="center">FloderSync</h1>

<p align="center">
  A native macOS menu bar utility that keeps local Git repositories in sync automatically.
</p>

<p align="center">
  <strong>English</strong> · <a href="./README.zh-CN.md">简体中文</a>
</p>

FloderSync uses the Git installation and authentication already configured on your Mac. It never stores Git passwords, access tokens, or SSH private keys.

## Highlights

- Manage multiple existing local Git repositories and verify their remote connections.
- Reuse automation rules across repositories or keep an independent configuration for one repository.
- Sync manually, at multiple daily times, on a fixed interval, or after detecting a new local commit.
- Automatically commit detected changes with a fixed or dynamic message (`${user}`, `${email}`, `${time}`); author fields can fall back to repository/global Git configuration.
- Choose Rebase or Merge for remote integration; Rebase is the conservative default.
- Detect conflicts, in-progress rebases or merges, detached HEAD, authentication errors, and network failures.
- Serialize operations for the same repository, coalesce repeated triggers, and sync up to two different repositories concurrently.
- See status in the menu bar, start a sync quickly, add repositories, review history and diagnostics, and launch at login.
- Receive notifications for failures and conflicts.
- Switch between English and Simplified Chinese without restarting the app.
- Follow the system appearance or select a light or dark theme.
- Export all repositories, automation rules, and app preferences to one versioned JSON file, or import one after validation and confirmation.

## Requirements

- macOS 14 or later
- Xcode 16 or later (currently verified with Xcode 26.6 and Swift 6.3.3)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A working system Git installation

## Build and test

```bash
xcodegen generate
xcodebuild build \
  -project floderSync.xcodeproj \
  -scheme floderSync \
  -destination 'platform=macOS'
xcodebuild test \
  -project floderSync.xcodeproj \
  -scheme floderSync \
  -destination 'platform=macOS'
```

You can also open `floderSync.xcodeproj` and run the `floderSync` scheme. FloderSync is an `LSUIElement` app, so it appears only in the system menu bar and does not show a Dock icon.

### Install in Applications

Quit any running copy of FloderSync, then run:

```bash
./scripts/install-local.sh
```

The script creates a Release build, installs `FloderSync.app` in `/Applications`, and launches the installed app. After the first install, or after replacing a development build, turn **Launch at Login** off and on again from the installed app so the macOS login item points to `/Applications/FloderSync.app` instead of Xcode's DerivedData directory.

For a login item whose code identity remains stable between builds, open **Signing & Capabilities** for the FloderSync target in Xcode, enable automatic signing, and select your Team.

### Test distribution without a Developer ID

You can create an unnotarized ZIP for trusted testers:

```bash
./scripts/package-unsigned.sh
```

The output is `dist/FloderSync-<version>-macOS-universal-unsigned.zip`. It includes both Apple Silicon and Intel architectures and uses an ad-hoc signature so the app bundle can be checked for damage after packaging. This is not a Developer ID signature and does not pass Gatekeeper's first-download assessment or qualify for Apple notarization.

After extracting the ZIP, move `FloderSync.app` to `/Applications`, remove only its quarantine attribute, and launch it:

```bash
xattr -dr com.apple.quarantine /Applications/FloderSync.app
open /Applications/FloderSync.app
```

`xattr -cr /Applications/FloderSync.app` also works, but recursively clears every extended attribute rather than only `com.apple.quarantine`. Never run either command against `/Applications` itself or another broad directory.

An ad-hoc identity changes with each build. After an upgrade, users may need to turn **Launch at Login** off and on again, and macOS may ask for permissions again. A Developer ID Application certificate from the Apple Developer Program is still required for notarization, stable identity across releases, and a normal installation experience without Terminal commands.

## Git and authentication

FloderSync searches for Git at `/usr/bin/git`, the Apple Silicon Homebrew path, and the Intel Homebrew path, in that order. It reuses your existing Git, SSH, and credential-helper configuration.

Automatic sync runs with `GIT_TERMINAL_PROMPT=0`. If authentication cannot complete non-interactively, the operation stops and FloderSync reports the error instead of asking for or storing credentials. The **Check Connection** action uses `git ls-remote --heads` to validate the selected repository's remote with the same background authentication environment.

## Data location

Configuration and the 100 most recent sync summaries are stored in:

```text
~/Library/Application Support/dev.flodersync.app/
```

Removing a repository from FloderSync deletes only its app configuration. It does not delete the local working tree or any `.git` data.

The Settings page can export repositories, shared automation rules, notification, language, appearance, and launch-at-login intent as JSON. Import replaces the current configuration only after the file passes validation and you confirm the displayed repository and rule counts. Sync history and Git credentials are never included.

## Before release

- Replace the development bundle identifier `dev.flodersync.app` with the final reverse-domain identifier.
- Configure Developer ID signing, Hardened Runtime, notarization, and an update channel.
- Validate real SSH, HTTPS Keychain, launch-at-login, and the complete window appearance matrix in a signed build.

See [docs/README.md](./docs/README.md) for the product requirements, architecture, test plan, and implementation roadmap.
