# Prevent Sleep privileged helper

Kaji uses an embedded `SMAppService` LaunchDaemon for `pmset` changes. Registration
is requested on the first Prevent Sleep enable. Later toggles reuse the registered
service.

The XPC contract accepts one `Bool`. The helper maps it to exactly one of:

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
```

No executable path, argument array, command string, or shell text crosses XPC.
After every request, Kaji reads `pmset -g`; UI and preferences only commit that
observed state.

## Build layout

`scripts/build-app.sh` embeds:

```text
Kaji.app/Contents/Library/HelperTools/KajiSleepHelper
Kaji.app/Contents/Library/LaunchDaemons/dev.kaji.sleep-helper.plist
```

The local build script ad-hoc signs `KajiSleepHelper` before sealing the outer
app so `SMAppService` can inspect a valid bundle. Distribution builds must replace
that identity with the same Apple Developer team for helper and app.

## Removal

Before deleting the app, call `SleepController.restoreAndRemoveHelper()`. It first
requests `disablesleep 0`, verifies command success, then calls
`SMAppService.unregister()`. Never remove the app bundle while its helper remains
registered.
