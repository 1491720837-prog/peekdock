#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

pass() { printf '  [OK] %s\n' "$1"; }
warn() { printf '  [--] %s\n' "$1"; }

printf 'PeekDock environment doctor\n\n'

if command -v node >/dev/null 2>&1; then
  pass "Node.js $(node --version)"
else
  warn "Node.js missing (requires Node 20+)"
fi

if command -v swiftc >/dev/null 2>&1; then
  pass "Swift compiler available — desktop floating screen can run"
else
  warn "Swift compiler missing — no-hardware mode will use the browser simulator"
fi

if command -v codex >/dev/null 2>&1; then
  pass "Codex CLI available at $(command -v codex)"
else
  warn "Codex CLI missing — install/login Codex before sending Codex tasks"
fi

if [[ -d "${PEEKDOCK_CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}" ]]; then
  pass "Codex session data directory found"
else
  warn "Codex session directory not found yet"
fi

if command -v claude >/dev/null 2>&1; then
  pass "Claude Code CLI available at $(command -v claude)"
else
  warn "Claude Code CLI missing — install/login Claude Code to enable dispatch"
fi

if [[ -d "${PEEKDOCK_CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}" ]]; then
  pass "Claude Code session directory found"
else
  warn "Claude Code session directory not found yet"
fi

if [[ -d "/Applications/Google Chrome.app" ]]; then
  pass "Google Chrome found — JiMeng page adapter is available after login"
else
  warn "Google Chrome missing — JiMeng page adapter requires Chrome"
fi

SERIAL="${PEEKDOCK_SERIAL_PORT:-}"
if [[ -n "$SERIAL" && -e "$SERIAL" ]]; then
  pass "ESP32 serial device found at $SERIAL"
else
  FOUND=""
  for CANDIDATE in /dev/cu.usbmodem* /dev/cu.usbserial* /dev/cu.wchusbserial*; do
    if [[ -e "$CANDIDATE" ]]; then FOUND="$CANDIDATE"; break; fi
  done
  if [[ -n "$FOUND" ]]; then
    pass "ESP32-compatible serial device found at $FOUND"
  else
    warn "No ESP32 serial device — PeekDock will use the desktop floating screen"
  fi
fi

printf '\nRun: npm start\n'
printf 'Explicit offline demo only: npm run demo\n'
