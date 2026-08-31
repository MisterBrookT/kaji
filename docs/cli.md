# CLI reference

`kaji` drives the running app's Goals module from a shell — which is mostly useful for letting a coding agent record and close your goals. It is a thin client over a loopback control API; the app must be running.

## Install

`./scripts/build-local.sh` builds the CLI and copies it to `~/.local/bin/kaji`. The one-line installer does not install it. From a clone:

```sh
swift build -c release --product kaji-cli
cp .build/release/kaji-cli ~/.local/bin/kaji
```

## Commands

```text
kaji list                                        # today's goals: [x] id tag title # note
kaji add <title> [tag] [note]                    # tag defaults to "personal"
kaji done <id>                                   # mark complete
kaji undone <id>                                 # reopen
kaji update <id> [--title T] [--tag T] [--note N]
kaji delete <id>
kaji state                                       # full app state as JSON
kaji raw <METHOD> <path> [json-body]             # escape hatch
```

Mutating commands print the resulting JSON object. Errors go to stderr as `kaji: <message>` with exit status 1.

`<id>` accepts any unambiguous prefix of a goal id, which is why `list` prints the first 8 characters. An ambiguous or unknown prefix is an error, never a guess.

## Examples

```sh
kaji add "ship the launch post" work "draft in .dev/"
kaji list
kaji done 3f9a1c02
kaji update 3f9a1c02 --tag personal --note "moved to weekend"
kaji state | jq '.quota'
```

## Endpoint

The CLI talks to `http://127.0.0.1:37841/v1` by default. Override with `KAJI_ENDPOINT`. The API binds loopback only; there is no remote access and no authentication because nothing off-machine can reach it.

## Using it from an agent

Point your agent at `kaji --help` and let it build its own wrapper — the help output is the source of truth for the supported surface. Kaji deliberately does not ship an MCP server; the reasoning is in [CLI integration](cli-integration.md).
