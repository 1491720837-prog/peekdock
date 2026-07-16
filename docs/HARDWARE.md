# Hardware, Firmware, and Desktop Fallback

## Target

- Waveshare ESP32-S3-Touch-LCD-1.47
- 172 × 320 JD9853 display
- AXS5106 touch controller
- USB Serial/JTAG transport
- ESP-IDF 5.x + LVGL

Board configuration and vendor-derived drivers are in `components/`, `sdkconfig.defaults`, and `src/`. The application partition is 6 MiB for pixel assets.

## Build and flash

```bash
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```

Then run PeekDock. The port is normally discovered automatically; an explicit override is supported:

```bash
PEEKDOCK_SERIAL_PORT=/dev/cu.usbmodemXXXX npm start
```

## Firmware behavior

- Four pages: Codex, Claude, Jimeng, Browser Agent.
- Horizontal swipe or edge fallback changes page.
- Agent-specific idle/running/completed frames, status, progress and intervention UI.
- `task_snapshot` restores all pages; `task_update` changes one task.
- Touch actions return as newline-delimited `action_event` JSON.

## Automatic display selection

`npm start` scans `/dev/cu.usbmodem*`, `/dev/cu.usbserial*` and `/dev/cu.wchusbserial*`.

- Device present: Bridge selects `displayTarget=hardware` and streams real Agent state over USB.
- Device absent: Bridge selects `displayTarget=desktop-overlay` and launches the native macOS floating screen.
- Hot plug: Bridge sends a full snapshot and hides the floating screen.
- Unplug: Bridge stays alive and restores the floating screen.

This fallback is not `mock-serial`; only `npm run demo` uses Mock data.

## Verification status

Runtime, API, WebSocket, real-mode webhook, simulator and overlay compilation are covered locally. This delivery environment has no target board attached, so final `idf.py build`, flash, color calibration and touch validation must be completed with the physical device.
