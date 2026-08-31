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

## Why is there no download on Releases?

Kaji is not yet signed with an Apple Developer ID. An unsigned `.app.zip` downloaded through a browser is quarantined by Gatekeeper and refuses to launch, which is a worse first experience than building from source. The installer builds locally and clears quarantine on a bundle it just built itself.

## macOS asks for my password when I enable sleep control

The sleep module installs a privileged helper (`/Library/PrivilegedHelperTools/dev.kaji.sleep-helper` plus `/Library/LaunchDaemons/dev.kaji.sleep-helper.plist`) because changing system sleep behavior requires root. Nothing else in Kaji asks for elevation. Leave the module off and no helper is installed.

## The popover has a blank strip above the header

That was a layout regression class in older builds — the popover's content height is clamped while the hosting view keeps its full height. Update to the latest release. If it reappears, open an issue with the module you were viewing and the list length, because it only shows up once a page is long enough to hit the scroll cap.

## Where is my data stored?

- Goals, preferences, and module toggles: `UserDefaults` for `dev.kaji` (`~/Library/Preferences/dev.kaji.plist`).
- Quota caches: `~/.helm/sessions/`.
- Nothing is stored outside your Mac.

## How do I uninstall?

```sh
# quit and remove the app
pkill -f "/Applications/Kaji.app/Contents/MacOS/Kaji" || true
rm -rf /Applications/Kaji.app

# preferences, goals, quota caches
defaults delete dev.kaji || true
rm -rf ~/.helm/sessions

# the CLI, if you installed it
rm -f ~/.local/bin/kaji
```

If you enabled sleep control, also remove the privileged helper:

```sh
sudo launchctl bootout system/dev.kaji.sleep-helper || true
sudo rm -f /Library/LaunchDaemons/dev.kaji.sleep-helper.plist
sudo rm -f /Library/PrivilegedHelperTools/dev.kaji.sleep-helper
```

## Will Kaji hide my other menu-bar icons, like Ice or Bartender?

No. That is an explicit non-goal — see [product principles](product-principles.md).

## Can I write my own module or plugin?

Not today. Modules are in-tree and first-party; Kaji loads no remote bundles or third-party executables. The reasoning is in [module architecture](module-architecture.md). Open an issue to propose a module.
