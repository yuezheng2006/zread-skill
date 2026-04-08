# zread `--stdio` protocol

Every zread command accepts `--stdio`, switching the process from an interactive
TUI into a JSON-line machine protocol on stdin/stdout. This is the contract used
by GUI / programmatic clients to drive zread.

## Architecture

zread internally uses a Driver / Client split:

- **Driver** holds all business logic (loading config, calling LLMs, running the
  doc server, managing drafts). It is framework-agnostic and only talks to a
  `Transport`.
- **Client** is either a Bubbletea TUI or `StdioClient`. With `--stdio`, the
  cobra command instantiates `transport.NewLocalTransport()` (a channel pair),
  spawns the driver in a goroutine, then runs `transport.NewStdioClient(clientT).Run(ctx)`.
- `StdioClient` reads JSON lines from `os.Stdin` and forwards them as commands
  to the driver, while encoding `Event`s from the driver to `os.Stdout` (one
  JSON object per line). It returns when an event with `"done": true` is
  received.

Result: stdin = command stream, stdout = event stream, both newline-delimited
JSON. stderr is reserved for logs/errors and should not be parsed.

## Event format (driver → client, stdout)

```json
{
  "vm": { ... },             // current ViewModel snapshot (shape per-command)
  "waiting_for": ["..."],    // command types accepted in the current state
  "done": false,             // true on the final event; client should exit
  "error": ""                // non-empty when the previous command was rejected
}
```

- An event is emitted after every state transition. The client should treat
  `vm` as the full state (no diffs).
- `waiting_for` enumerates the legal `type` values the client may send right
  now. `quit` is always implicitly accepted.
- The very last event always has `"done": true` and an empty `waiting_for`.

## Command format (client → driver, stdin)

One JSON object per line:

```json
{"type": "<command_type>", "params": { ... }}
```

- `type` is required. `params` may be omitted (treated as `{}`).
- Universal command: `{"type":"quit","params":{}}` — every driver handles it
  and shuts down cleanly.
- Command types prefixed with `_` are driver-internal (async results injected
  by the driver itself) and must never appear in `waiting_for`; clients should
  not send them.
- Sending a command not in `waiting_for` produces an event with `error` set
  while `vm`/`waiting_for` remain unchanged.

## Driving a session

1. Spawn `zread <command> --stdio` with piped stdin/stdout.
2. Read the first event — it carries the initial ViewModel and `waiting_for`.
3. Render or inspect `vm`; pick a legal command from `waiting_for` and write it
   as a single JSON line followed by `\n`.
4. Loop: read next event, react, write next command.
5. Stop when an event arrives with `"done": true`. The process will exit on
   its own; no further input is required. Sending `quit` at any time triggers
   the same shutdown path.

## Per-command notes

The `vm` schema, state machine, and command vocabulary are defined per command
in `pkg/ui/<command>/viewmodel.go` and `driver.go` in the zread_cli repo. The
common ones:

- `zread browse --stdio` — emits loading → serving (with server URL in `vm`),
  or `select_version` when multiple wikis exist. Commands include
  `select_version` (`{"wiki_id":"..."}`) and `quit`.
- `zread generate --stdio` — emits catalog progress, an optional
  `catalog_confirm` gate, then per-page progress. Commands include
  `confirm_catalog`, `retry`, `skip`, `quit`. `--yes` skips the confirm gate.
- `zread config --stdio`, `zread login --stdio`, `zread update --stdio`,
  `zread version --stdio` follow the same envelope; consult the matching
  driver for their `waiting_for` values.

## Practical tips

- Always flush stdin after writing a command (the driver reads line-by-line).
- Treat any line on stdout that fails to parse as JSON as a bug — log it but
  do not crash; zread should not print non-JSON to stdout in `--stdio` mode.
- For long-running commands (`generate`), keep reading events continuously;
  there is no heartbeat, but progress events arrive whenever state changes.
- To cancel cleanly, send `{"type":"quit","params":{}}` and then drain events
  until `done` rather than killing the process.
