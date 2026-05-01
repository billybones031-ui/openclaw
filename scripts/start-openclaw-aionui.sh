#!/usr/bin/env bash
# Start OpenClaw Gateway bound to all interfaces so AionUi can discover it
# over LAN and Tailscale.
#
# Usage:
#   ./scripts/start-openclaw-aionui.sh
#
# Auto-start on login — add to ~/.bashrc:
#   if ! pgrep -f "openclaw gateway" > /dev/null; then
#     <repo-root>/scripts/start-openclaw-aionui.sh
#   fi
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$HOME/openclaw-aionui.log"
PID_FILE="$HOME/.openclaw-aionui.pid"
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

# Kill any existing managed instance, but only if the PID still points at a
# gateway process. PIDs get reused after the previous gateway exits, so blindly
# killing whatever is in the pidfile can take out an unrelated process.
if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${OLD_PID:-}" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    OLD_CMD="$(ps -p "$OLD_PID" -o args= 2>/dev/null || true)"
    if [[ "$OLD_CMD" == *"openclaw"*"gateway"* ]]; then
      echo "Stopping existing OpenClaw Gateway (PID $OLD_PID)…"
      kill "$OLD_PID" 2>/dev/null || true
      # Wait up to 5s for graceful exit, then SIGKILL.
      for _ in 1 2 3 4 5; do
        kill -0 "$OLD_PID" 2>/dev/null || break
        sleep 1
      done
      kill -0 "$OLD_PID" 2>/dev/null && kill -9 "$OLD_PID" 2>/dev/null || true
    else
      echo "Stale pidfile — PID $OLD_PID is not an openclaw gateway, skipping kill."
    fi
  fi
  rm -f "$PID_FILE"
fi

# Start bound to all interfaces (--bind lan → 0.0.0.0).
cd "$REPO_ROOT"
pnpm openclaw gateway --bind lan >> "$LOG" 2>&1 &
NEW_PID=$!

# Give the server a moment to bind, then verify it is still alive before
# persisting the pidfile and printing success — startup can fail fast on port
# conflicts or config errors, which would otherwise produce a false success.
sleep 1
if ! kill -0 "$NEW_PID" 2>/dev/null; then
  echo "❌ OpenClaw Gateway failed to start. Last log lines:" >&2
  tail -n 30 "$LOG" >&2 || true
  exit 1
fi
echo "$NEW_PID" > "$PID_FILE"

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")"
TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo "not-connected")"

echo "✅ OpenClaw Gateway started (PID $NEW_PID)"
echo ""
echo "  Local:      http://localhost:${PORT}"
echo "  LAN:        http://${LAN_IP}:${PORT}"
echo "  Tailscale:  http://${TAILSCALE_IP}:${PORT}"
echo "  Discovery:  http://localhost:${PORT}/.well-known/openclaw-gateway"
echo ""
echo "  Log:        $LOG"
echo "  PID file:   $PID_FILE"
