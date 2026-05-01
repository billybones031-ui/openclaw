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

# Kill any existing managed instance.
if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE")"
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Stopping existing OpenClaw Gateway (PID $OLD_PID)…"
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$PID_FILE"
fi

# Start bound to all interfaces (--bind lan → 0.0.0.0).
cd "$REPO_ROOT"
pnpm openclaw gateway --bind lan >> "$LOG" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"

# Give the server a moment to bind before printing URLs.
sleep 0.5

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
