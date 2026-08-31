# Security policy

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: **Security → Report a vulnerability** on this repository. Please do not open a public issue for anything exploitable.

Include the affected version, what an attacker can do, and a reproduction if you have one. Expect an acknowledgement within a few days; this is a single-maintainer project.

## Supported versions

Only the [latest release](https://github.com/MisterBrookT/kaji/releases/latest) receives fixes.

## Sensitive surfaces

Kaji touches credentials and a privileged helper, so reports about these are especially welcome:

- **Provider credentials.** Kaji reads `~/.claude/.credentials.json` and Cursor's `state.vscdb` to call those providers' own usage endpoints. The token is used only in that request. It is never written elsewhere, logged, or sent to any host other than the provider's own API. See [how quota works](docs/quota.md).
- **Bundled Python reader.** `Resources/quota.py` runs as your user every 30 seconds and parses local session logs. It is shipped inside the app bundle; the interpreter path can be overridden via the `pythonInterpreter` preference.
- **Loopback control API.** The app listens on `127.0.0.1:37841` with no authentication, on the assumption that anything able to reach it already runs as your user. Reports of a path that escapes that assumption (remote reachability, browser-originated requests, privilege escalation through a route) are in scope.
- **Privileged sleep helper.** Enabling sleep control installs `/Library/PrivilegedHelperTools/dev.kaji.sleep-helper` and a matching LaunchDaemon. Issues in its XPC validation or install path are in scope.
- **Code signing.** Local and CI builds are ad-hoc signed. Kaji is not yet notarized, and the installer clears quarantine only on a bundle it built locally from a release tag.

## Out of scope

- The absence of Developer ID signing / notarization (known, tracked).
- Provider APIs returning inaccurate quota numbers.
- Anything requiring the attacker to already have root on the machine.
