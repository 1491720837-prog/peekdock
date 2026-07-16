# PeekDock Competition Demo Guide

## Before going on stage

```bash
cd /path/to/peekdock
npm install
npm run doctor
npm test
npm start
```

Log into the Agents you will show. For JiMeng, open its Chrome page and enable Chrome “View → Developer → Allow JavaScript from Apple Events”. Open <http://127.0.0.1:4173> and allow microphone access if voice will be used.

## Recommended 3-minute script

**0:00–0:30 — problem.** “I delegate to several AI Agents, then waste attention checking four windows. PeekDock turns that polling anxiety into one glance.”

**0:30–1:10 — real dispatch.** Select Codex and say or type “帮我整理 PeekDock 比赛发布清单”. Send it and point out `Real agents`, adapter health and the real CLI task ID.

**1:10–1:45 — embodied status.** Show the Codex character moving through real phases such as analyzing, using tool and reviewing. Emphasize that hardware, overlay and simulator consume the same state.

**1:45–2:15 — completion/intervention.** Show “老板，我做好啦”; switch Agent. A missing login/permission is shown honestly as Input required. If JiMeng is prepared, send an image prompt and show its page-driven status.

**2:15–2:45 — two forms.** Connect the board to show automatic USB takeover, or explain that no hardware automatically becomes the desktop floating small screen without changing the Agent source.

**2:45–3:00 — close.** “PeekDock is not another place to run a model. It is the calm, user-owned front desk for every model already working for you.”

## Fallbacks

- **Microphone denied/noisy:** use the same text composer.
- **ESP32 unavailable:** use the native floating screen; it is the supported no-hardware product form.
- **Claude missing:** do not fake it; show `npm run doctor` and use Codex/JiMeng.
- **JiMeng login expired:** the screen shows Input required; complete login manually or use a prepared authenticated session.
- **Port busy:** run `PORT=4180 npm start`.
- **Network unavailable:** real cloud Agent execution cannot run; use explicit `npm run demo` only if you clearly label it offline Demo mode.

## What not to demo

Do not show the historical game or describe upward swipe as cross-device play. Do not claim a missing or unauthenticated adapter is connected. Do not call the desktop overlay Mock: it displays the same real state as the physical screen.
