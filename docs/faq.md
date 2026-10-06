# FAQ and troubleshooting

## The quota panel says python3 is missing

Kaji's quota reader is a bundled Python script, and an app launched from Finder inherits a minimal `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`) rather than your shell's. Kaji probes, in order:

1. `/opt/homebrew/bin/python3` (Apple Silicon Homebrew)
2. `/usr/local/bin/python3` (Intel Homebrew)
3. `/usr/bin/python3` (system — only a stub until the Xcode command-line tools are installed)

Fix by installing the command-line tools:

```sh
xcode-select --install
```

If you keep Python somewhere else, set an explicit interpreter:

```sh
defaults write dev.kaji pythonInterpreter /path/to/python3
```

## A provider row shows `—`

`—` means no data for that window, which is normal in several cases:

- You have never used that tool on this Mac, so there are no session logs.
- The provider is not logged in locally, so there is no token to read.
- **Codex specifically** needs the `codex` CLI reachable from a minimal `PATH`. If `codex` lives only in a shell-managed directory, the 5h / 7d rings stay empty while token counts still work from the session logs.
- The provider's cache has not refreshed yet (Claude limits cache for 1 hour, others for 3 minutes).

See [how quota works](quota.md) for the exact source of each number.

## How do updates work?

Updates are user-initiated. When a newer release is detected, an **Update** button appears beside Settings in the popover. You can also check in **Settings → General → Version**. From 1.0.1, Sparkle shows release notes, verifies the signed feed and archive, downloads the app and handles installation/relaunch. It does not compile source on each update. Automatic downloads and system-profile submission are disabled.

Versions older than 1.0.1 do not contain Sparkle. Use the source install command once to get it (1.0.0 can also use its source updater). Publishing a feed cannot retroactively change an already-installed updater.

Kaji is ad-hoc signed, not Apple Developer ID signed or notarized. Browser-downloaded ZIPs and DMGs may both be blocked by Gatekeeper. Sparkle's Ed25519 update signatures are separate from Apple signing: they secure updates after Kaji is already running, but do not fix first-install warnings. Use the source installer for initial setup and only install software you trust.

## macOS asks for my password when I enable sleep control

The sleep module installs a privileged helper (`/Library/PrivilegedHelperTools/dev.kaji.sleep-helper` plus `/Library/LaunchDaemons/dev.kaji.sleep-helper.plist`) because changing system sleep behavior requires root. Leave the module off and no sleep helper is installed. Sparkle updates normally need no administrator rights for a user-owned app; a protected install location can require approval to replace the app.

## The popover has a blank strip above the header

That was a layout regression class in older builds — the popover's content height is clamped while the hosting view keeps its full height. Update to the latest release. If it reappears, open an issue with the module you were viewing and the list length, because it only shows up once a page is long enough to hit the scroll cap.

## Where is my data stored?

- Goals, preferences, and module toggles: `UserDefaults` for `dev.kaji` (`~/Library/Preferences/dev.kaji.plist`).
- Quota caches: `~/.helm/sessions/`.
- Nothing is stored outside your Mac.

## How do I uninstall?

```sh
# quit the app; if sleep control was enabled, finish helper removal below FIRST
pkill -f "/Applications/Kaji.app/Contents/MacOS/Kaji" || true

# preferences, goals, quota caches
defaults delete dev.kaji || true
rm -rf ~/.helm/sessions

# the CLI, if you installed it
rm -f ~/.local/bin/kaji
```

If you enabled sleep control, wait for the helper to restore your prior sleep
setting after quitting. Check whether its root-owned lease marker remains:

```sh
sudo cat /Library/PrivilegedHelperTools/dev.kaji.sleep-helper.lease 2>/dev/null || true
sudo pmset -g
```

Older helper versions did not create a marker. If Prevent Sleep was enabled by
an older version and the marker is absent, this version cannot infer your original
setting: inspect `pmset -g` and decide whether to turn it off manually before
removal. Normally a new helper's marker disappears automatically. **If it remains, do not stop or
delete the helper yet.** The marker contains the original `disablesleep` value
(`0` or `1`). If it says `0` and `pmset -g` still shows `SleepDisabled 1`, restore
with `sudo pmset -a disablesleep 0`. If the marker says `1`, leave the setting
alone. If it is missing or unreadable, do not guess; inspect the setting before
making any changes. After restoration, remove the helper, then the app:

```sh
sudo launchctl bootout system/dev.kaji.sleep-helper || true
sudo rm -f /Library/LaunchDaemons/dev.kaji.sleep-helper.plist
sudo rm -f /Library/PrivilegedHelperTools/dev.kaji.sleep-helper
sudo rm -f /Library/PrivilegedHelperTools/dev.kaji.sleep-helper.lease
rm -rf /Applications/Kaji.app
```

There is currently no in-app helper uninstall button. An updated app may need
administrator-approved helper repair because its ad-hoc code hash changes.

## Will Kaji hide my other menu-bar icons, like Ice or Bartender?

No. That is an explicit non-goal — see [product principles](product-principles.md).

## Can I write my own module or plugin?

Not today. Modules are in-tree and first-party; Kaji loads no remote bundles or third-party executables. The reasoning is in [module architecture](module-architecture.md). Open an issue to propose a module.
