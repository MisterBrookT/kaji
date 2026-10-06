# Prevent Sleep privileged helper

The first enable prompts for administrator approval and installs an ad-hoc signed
helper in `/Library/PrivilegedHelperTools` with a classic LaunchDaemon plist in
`/Library/LaunchDaemons`. This is **not** SMAppService or Developer ID signing.
The installer provisions the exact installed app executable CDHash as a daemon
argument. The helper fails closed without a valid hash and Foundation checks the
code signing requirement on every XPC message. Replacing/updating the app changes
its hash: SleepHelperInstaller reports repair required and an administrator must
reinstall the helper to provision the new hash. A copied signing identifier alone
is never accepted.

The XPC API only accepts a boolean sleep request and lease renewal; it never
accepts a command or path. Root executes only `/usr/bin/pmset`. Every invocation
has a deadline and forced kill. Install commands use fail-fast shell execution.

## Lease and recovery

Before writing `disablesleep 1`, the daemon reads the existing `pmset -g` value
and writes it atomically to a root-owned marker beside the helper. A live XPC
connection owns a 45-second lease renewed every 15 seconds. Turning Prevent
Sleep off, quitting, disconnecting, or lease expiry restores `0` **only** when
Kaji recorded an original `0` and `pmset -g` still reports `SleepDisabled 1`. An original
`1` stays `1`. The daemon is kept alive by launchd; after a daemon crash it
recovers the marker on restart, and retries restoration if pmset temporarily
fails. If the marker is malformed, it fails closed rather than guessing the
prior value. A concurrent external change to the same binary setting cannot be
reliably distinguished from Kaji's write; avoid changing `disablesleep` by other
means while Kaji's lease is active.

## Manual removal

There is no in-app uninstall button. **Do not remove the daemon or marker first.**
Quit Kaji and verify the marker has disappeared (the helper restores on XPC
invalidation). If the app was already removed, keep the daemon running until the
marker disappears. If it cannot restore, read the root marker (`0` or `1`) and
restore only when it reads `0` and `pmset -g` still reports `disablesleep 1`:

```sh
sudo cat /Library/PrivilegedHelperTools/dev.kaji.sleep-helper.lease
sudo pmset -g
# Only if marker is 0 and current SleepDisabled is 1:
sudo pmset -a disablesleep 0
sudo launchctl bootout system/dev.kaji.sleep-helper
sudo rm -f /Library/LaunchDaemons/dev.kaji.sleep-helper.plist
sudo rm -f /Library/PrivilegedHelperTools/dev.kaji.sleep-helper
sudo rm -f /Library/PrivilegedHelperTools/dev.kaji.sleep-helper.lease
```

If the marker is missing, do not blindly set `disablesleep 0`: the user may have
had it enabled independently. Never remove the marker before restoration.
