# Hardware and Firmware

## Target

- Waveshare ESP32-S3-Touch-LCD-1.47
- 172 × 320 JD9853 display
- AXS5106 touch controller
- USB Serial/JTAG transport
- ESP-IDF 5.x + LVGL

The board configuration and vendor-derived drivers are already in `components/`, `sdkconfig.defaults`, and `src/`. The application partition is 6 MiB to hold the pixel assets.

## Build

Install and activate ESP-IDF 5.x, then run from the repository root:

```bash
idf.py set-target esp32s3
idf.py build
```

Flash and monitor after identifying the port:

```bash
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```

Start the Mac bridge against the same port:

```bash
PEEKDOCK_SERIAL_PORT=/dev/cu.usbmodemXXXX npm start
```

## Firmware behavior

- Four fixed pages: Codex, Claude, Jimeng and Browser Agent.
- Horizontal swipe or left/right edge fallback changes page.
- Agent-specific idle/running/completed frames and status color.
- Progress, input-required action, completion burst and idle micro-copy.
- `task_snapshot` restores all pages; `task_update` changes one task.
- Touch actions return as newline-delimited `action_event` JSON.

## Mock serial

When the configured device is absent, the Bridge stays online and labels the transport `mock-serial`. All state transitions still reach the browser simulator and event log. This is the supported no-hardware development and judging path.

## Verification status

The runtime/API/WebSocket/simulator path is covered by automated tests. The firmware source and CMake manifest include the fourth Browser Agent page and assets. This delivery environment did not expose the target board or a complete activated ESP-IDF toolchain, so final `idf.py build`, flash, color calibration and touch validation must be performed on the physical setup. The documented mock path is not blocked by that limitation.
