# PeekDock Competition Demo Guide

## Before going on stage

```bash
cd /path/to/peekdock
npm install
npm test
npm start
```

Open `http://127.0.0.1:4173` in Chrome, allow microphone access if voice will be used, and click “重置为 Idle”. Keep the default mock mode for a deterministic run. A board is optional.

## Recommended 3-minute script

**0:00–0:30 — problem.** “I can delegate work to several AI Agents, but then I spend my time checking four windows. PeekDock turns that polling anxiety into one glance.” Point to the Agent rail and idle simulator.

**0:30–1:10 — voice dispatch.** Select Codex, press the microphone and say “帮我整理 PeekDock 比赛发布清单”. If venue audio is noisy, use the prepared text and explain that voice has a text fallback. Send the task.

**1:10–1:45 — embodied status.** Show the Codex character entering Working, the live progress and event log. Emphasize that the simulator consumes the same state model as the ESP32, not a prerecorded animation.

**1:45–2:15 — intervention and completion.** Let Codex finish and show “老板，我做好啦”. Click “一键装载比赛场景”, then switch to Claude to show Input Required and Jimeng to show Done.

**2:15–2:45 — system.** Explain that one Mac Bridge normalizes Agent events and streams JSON to both the web simulator and an ESP32 over USB. Missing hardware automatically becomes mock serial.

**2:45–3:00 — close.** “The device is not another place to run a model. It is the calm, user-owned front desk for every model already working for you.”

## Controls

- Agent rail or simulator swipe: change Agent.
- `←` / `→`: change Agent when not typing.
- “一键装载比赛场景”: populate four contrasting states.
- “重置为 Idle”: clean start.
- Quick state buttons: force Working, Input, Done, or Error.

## Fallbacks

- **Microphone denied/noisy:** type into the same composer; this is an intentional fallback, not a separate demo path.
- **ESP32 unavailable:** point to `mock-serial` and use the device-sized simulator.
- **Port busy:** run `PORT=4180 npm start` and open that port.
- **Animations feel too fast:** use quick state buttons to pause on each state.
- **Network unavailable:** the runtime, assets, simulator, tests and demo result pages are local.

## What not to demo

Do not show the historical game or describe upward swipe as cross-device play. Do not enable real session monitors on stage unless a controlled real-Agent integration is the purpose of the presentation.
