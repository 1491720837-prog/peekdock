# PeekDock Runtime Architecture

## Design goals

PeekDock normalizes real AI activity into a glanceable five-state model and keeps data acquisition independent from the display. A physical board and the desktop floating screen are two render targets for the same state; absence of hardware must never imply fake Agent data.

## Components

### Mac console

`runtime-bridge/public/` provides voice/transcription UI, text fallback, Agent selection, adapter diagnostics, task queue, event log and a 172 × 320 browser simulator. WebSocket is primary; SSE is the fallback.

### Runtime Bridge

`runtime-bridge/server.mjs` is the canonical state owner. It:

- keeps one task slot for `codex`, `claude`, `jimeng` and `browser`;
- dispatches Codex through `codex exec --json` and Claude through `claude -p`;
- tails Codex and Claude session JSONL for work started outside PeekDock;
- submits prompts to an authenticated JiMeng Chrome page and polls its real page/API state;
- accepts normalized events from other Agent runtimes through `POST /api/ingest`;
- broadcasts HTTP, WebSocket and SSE state;
- discovers USB serial devices and reconnects without restarting;
- exposes `dataMode`, `displayTarget`, serial path and per-adapter health.

Real mode is default. `PEEKDOCK_REAL_MONITORS=0 PEEKDOCK_DEMO_MODE=1` explicitly enables deterministic Mock timelines for offline demos/tests.

### Desktop overlay

`desktop-overlay/PeekDockOverlay.swift` is the no-hardware display. It is an always-on-top AppKit panel, polls `/api/state`, renders the same four character assets, and switches Agent on left/right click. When hardware connects it hides; when hardware disconnects it reappears.

### ESP32 firmware

The ESP-IDF + LVGL firmware under `src/` parses JSON Lines into `PeekDockTask`, stores four Agent pages, renders pixel frames and emits whitelisted `action_event` messages. The Mac remains authoritative for tasks and desktop actions.

## Unified task model

```text
task_id, source, agent_name, title, task_type,
status, status_text, progress, result_uri, updated_at
```

| Canonical | UI | Meaning |
| --- | --- | --- |
| `idle` | Idle | No current work |
| `running` | Working | Agent is processing |
| `needs_input` | Input required | Login, permission or human decision required |
| `completed` | Done | Result is ready |
| `failed` | Error | Retry or investigation required |

Unknown progress is `-1`; renderers do not invent a precise percentage.

## Real data flow

1. Voice recognition or text produces a prompt.
2. `POST /api/send-task` invokes the selected real adapter.
3. CLI JSON/session JSONL, JiMeng page state or webhook events update canonical state.
4. Bridge broadcasts the update and, when present, writes `task_update` / `task_snapshot` to serial.
5. The active render target is ESP32 hardware or the desktop overlay; the browser simulator remains available for inspection.
6. `completed` triggers visible/audible feedback; authorization or login gaps become `needs_input`.

## Reliability and boundaries

- Full snapshots recover reconnecting consumers.
- Serial discovery polls for hot plug/unplug.
- CLI dispatch output is consumed directly while session monitors also detect work started elsewhere.
- A short dispatch hold prevents a second active Codex session from immediately overwriting a completion notice.
- Adapter health distinguishes `connected`, `waiting`, `missing`, `error` and `disabled`.
- Bridge binds to `127.0.0.1` by default; `/api/ingest` is therefore local-only unless the operator deliberately changes the host.
- Account login, CAPTCHA and OS/browser permissions remain human-controlled.
