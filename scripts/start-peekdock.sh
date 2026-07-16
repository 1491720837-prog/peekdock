#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PEEKDOCK_SERIAL_PORT="${PEEKDOCK_SERIAL_PORT:-/dev/cu.usbmodem1301}"
export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-4173}"
export PEEKDOCK_HEADLESS="${PEEKDOCK_HEADLESS:-0}"

if [[ ! -d node_modules ]]; then
  npm install
fi

echo "PeekDock console: http://${HOST}:${PORT}"
exec node runtime-bridge/server.mjs
