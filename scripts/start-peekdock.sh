#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PEEKDOCK_SERIAL_PORT="${PEEKDOCK_SERIAL_PORT:-}"
export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-4173}"
export PEEKDOCK_HEADLESS="${PEEKDOCK_HEADLESS:-0}"
export PEEKDOCK_REAL_MONITORS="${PEEKDOCK_REAL_MONITORS:-1}"
export PEEKDOCK_DEMO_MODE="${PEEKDOCK_DEMO_MODE:-0}"

if [[ ! -d node_modules ]]; then
  npm install
fi

echo "PeekDock console: http://${HOST}:${PORT}"

HAS_HARDWARE=0
if [[ -n "${PEEKDOCK_SERIAL_PORT:-}" && -e "${PEEKDOCK_SERIAL_PORT}" ]]; then
  HAS_HARDWARE=1
else
  for CANDIDATE in /dev/cu.usbmodem* /dev/cu.usbserial* /dev/cu.wchusbserial*; do
    if [[ -e "$CANDIDATE" ]]; then
      export PEEKDOCK_SERIAL_PORT="$CANDIDATE"
      HAS_HARDWARE=1
      break
    fi
  done
fi

if [[ "$HAS_HARDWARE" == "1" ]]; then
  echo "Display target: USB hardware"
  exec node runtime-bridge/server.mjs
fi

if [[ "${PEEKDOCK_OVERLAY:-auto}" == "0" ]]; then
  echo "Display target: browser console (desktop overlay disabled)"
  exec node runtime-bridge/server.mjs
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Display target: browser fallback (install Xcode Command Line Tools for the floating overlay)"
  node runtime-bridge/server.mjs &
  BRIDGE_PID=$!
  cleanup() {
    kill "$BRIDGE_PID" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT INT TERM
  for _ in {1..50}; do
    if curl -fsS "http://${HOST}:${PORT}/api/state" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  open "http://${HOST}:${PORT}" >/dev/null 2>&1 || true
  wait "$BRIDGE_PID"
fi

OVERLAY_BIN="${TMPDIR:-/tmp}/peekdock-overlay-$(id -u)"
echo "Display target: desktop floating overlay"
swiftc desktop-overlay/PeekDockOverlay.swift -o "$OVERLAY_BIN"

node runtime-bridge/server.mjs &
BRIDGE_PID=$!
cleanup() {
  kill "$BRIDGE_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

for _ in {1..50}; do
  if curl -fsS "http://${HOST}:${PORT}/api/state" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

PEEKDOCK_ROOT="$ROOT_DIR" PEEKDOCK_BRIDGE_URL="http://${HOST}:${PORT}" "$OVERLAY_BIN"
