# PeekDock MVP Architecture

## Design goals

PeekDock turns heterogeneous Agent events into a small, dependable state model. The demo must remain useful without a board or cloud credentials, while the same events can be forwarded to the physical display when present.

## Components

### Mac console

`runtime-bridge/public/` is a dependency-free web app served by the bridge. It owns voice capture/transcription UI, text fallback, Agent and scenario selection, the task queue, event log, toast notifications, and a 172 × 320 simulator. It receives a full state immediately, then incremental state over WebSocket; SSE is the fallback.

### Runtime Bridge

`runtime-bridge/server.mjs` is the canonical state owner. It:

- keeps one visible task slot for each of `codex`, `claude`, `jimeng`, and `browser`;
- exposes local HTTP actions and broadcasts state through WebSocket/SSE;
- runs deterministic mock timelines for the competition demo;
- can opt in to read-only Codex, Claude, and Jimeng monitoring;
- writes the same normalized JSON events to a USB serial device when it exists;
- treats a missing serial device as mock mode rather than an error.

The bridge binds to `127.0.0.1` by default. Local file opens are restricted to repository demo results and known application actions.

### ESP32 firmware

The active firmware path is ESP-IDF + LVGL under `src/`. It parses newline-delimited events into `PeekDockTask`, stores four fixed Agent pages, and renders agent-specific pixel frames. The Mac remains the authority for task and desktop actions; firmware only renders state and emits whitelisted `action_event` messages.

## Unified task model

```text
task_id, source, agent_name, title, task_type,
status, status_text, progress, result_uri, updated_at
```

The public API uses camelCase while USB fixtures use snake_case. Status normalization is:

| Canonical | UI | Meaning |
| --- | --- | --- |
| `idle` | Idle | No current work |
| `running` | Working | Agent is processing |
| `needs_input` | Input required | Human decision or missing detail |
| `completed` | Done | Result is ready |
| `failed` | Error | Retry or investigation required |

## Data flow

1. Voice recognition or text produces a prompt in the console.
2. `POST /api/send-task` creates a task and starts the selected mock adapter.
3. Every transition updates canonical state, broadcasts it, and writes `task_update` / `task_snapshot` to serial when available.
4. Browser simulator and ESP32 independently render the same model.
5. `completed` triggers a visible and audible completion cue; `needs_input` surfaces a review action.

## Reliability choices

- Mock adapters are default-off from real local sessions, making a competition run repeatable.
- Full snapshots are sent on connection/reset so consumers recover without replaying history.
- WebSocket is primary and SSE is a browser fallback.
- Serial absence is a visible transport state, not a startup failure.
- Voice is progressive enhancement; typed text is always available.

## Security and scope

The MVP is a localhost application and has no user account or remote exposure. It does not send prompts to third-party AI services by default. A production version needs authenticated adapters, permission-scoped actions, encrypted wireless transport, and a persistent event store.
