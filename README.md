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
- Sync manually, at multiple daily times, on a fixed interval, or after file changes with a five-second debounce.
- Use a conservative `add/commit -> pull --rebase -> push` workflow.
- Detect conflicts, in-progress rebases or merges, detached HEAD, authentication errors, and network failures.
- Serialize operations for the same repository, coalesce repeated triggers, and sync up to two different repositories concurrently.
- See status in the menu bar, start a sync quickly, add repositories, review history and diagnostics, and launch at login.
- Receive notifications for failures and conflicts.
- Switch between English and Simplified Chinese without restarting the app.
- Follow the system appearance or select a light or dark theme.

## Requirements

- macOS 14 or later
- Xcode 16 or later (currently verified with Xcode 26.6 and Swift 6.3.3)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A working system Git installation

## Build and test

```bash
xcodegen generate
xcodebuild build \
  -project obsSync.xcodeproj \
  -scheme obsSync \
  -destination 'platform=macOS'
xcodebuild test \
  -project obsSync.xcodeproj \
  -scheme obsSync \
  -destination 'platform=macOS'
```

You can also open `obsSync.xcodeproj` and run the `obsSync` scheme. FloderSync is an `LSUIElement` app, so it appears only in the system menu bar and does not show a Dock icon.

## Git and authentication

FloderSync searches for Git at `/usr/bin/git`, the Apple Silicon Homebrew path, and the Intel Homebrew path, in that order. It reuses your existing Git, SSH, and credential-helper configuration.

Automatic sync runs with `GIT_TERMINAL_PROMPT=0`. If authentication cannot complete non-interactively, the operation stops and FloderSync reports the error instead of asking for or storing credentials. The **Check Connection** action uses `git ls-remote --heads` to validate the selected repository's remote with the same background authentication environment.

## Data location

Configuration and the 100 most recent sync summaries are stored in:

```text
~/Library/Application Support/dev.obssync.app/
```

Removing a repository from FloderSync deletes only its app configuration. It does not delete the local working tree or any `.git` data.

## Before release

- Replace the development bundle identifier `dev.obssync.app` with the final reverse-domain identifier.
- Configure Developer ID signing, Hardened Runtime, notarization, and an update channel.
- Validate real SSH, HTTPS Keychain, launch-at-login, and the complete window appearance matrix in a signed build.

See [docs/README.md](./docs/README.md) for the product requirements, architecture, test plan, and implementation roadmap.
