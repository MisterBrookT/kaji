# Kaji 1.0.4 (2026-11-22)

## Changed
- Defaults: only Quota is on for a fresh install. Work / Break, Goals and the new GPU monitor are off until you turn them on in Settings > General. Existing users keep their current choices (only unset prefs get the default). Locked by `DefaultModulesTests` (default set = {quota}).

## Added
- GPU monitor (optional, off by default). Shows mlkit's GPU load: avg util in the menu bar; per host up/down and per card util, used/free memory and whose job; plus running jobs. Read-only: Kaji reads `~/.mlkit/gpus.json` written by mlkit's scheduler (or `mk gpus --write`) and never ssh-es. To add a remote, use `mk host add` in mlkit.
