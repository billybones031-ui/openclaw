#!/usr/bin/env bash
# laptop-connect-pixel.sh — Open a persistent SSH tunnel from the laptop to
# the Pixel headless server. Run this on your laptop.
#
# Usage:
#   ./scripts/laptop-connect-pixel.sh <pixel-tailscale-ip>
#   ./scripts/laptop-connect-pixel.sh 100.x.x.x
#
# What it does:
#   - Opens SSH tunnel forwarding OpenClaw (:18789), AionUi (:25808), spare (:8080)
#   - Writes ~/.ssh/config entry for 'pixel-isl' if not already present
#   - Prints browser URLs to open on laptop
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PIXEL_IP="${1:-}"
PIXEL_USER="${PIXEL_USER:-droid}"
OPENCLAW_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
AIONUI_PORT="${AIONUI_PORT:-25808}"
OPENCODE_PORT="${OPENCODE_PORT:-8080}"
SSH_CONFIG="$HOME/.ssh/config"
TUNNEL_PID_FILE="$HOME/.pixel-isl-tunnel.pid"
TUNNEL_SOCK="$HOME/.ssh/pixel-isl-tunnel.sock"

if [[ -z "$PIXEL_IP" ]]; then
  echo "Usage: $0 <pixel-tailscale-ip>"
  echo "  Get it from the Pixel with: tailscale ip -4"
  exit 1
fi

echo ""
echo -e "${BOLD}=== Connecting to Pixel ISL (${PIXEL_IP}) ===${NC}"
echo ""

# ── Kill existing tunnel if any ───────────────────────────────────────────────
# Primary: use the ControlMaster socket — precise, no PID guessing.
# Fallback: use PID file, but verify the process is actually an SSH tunnel
# (argv contains "ssh") before killing to avoid hitting a reused PID.
if [[ -S "$TUNNEL_SOCK" ]]; then
  echo "Closing existing tunnel (via control socket)…"
  ssh -S "$TUNNEL_SOCK" -O exit "${PIXEL_USER}@${PIXEL_IP}" 2>/dev/null || true
  rm -f "$TUNNEL_SOCK"
fi
if [[ -f "$TUNNEL_PID_FILE" ]]; then
  OLD_PID="$(cat "$TUNNEL_PID_FILE" 2>/dev/null || true)"
  if [[ -n "${OLD_PID:-}" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    OLD_CMD="$(ps -p "$OLD_PID" -o args= 2>/dev/null || true)"
    if [[ "$OLD_CMD" == *"ssh"* && "$OLD_CMD" == *"${PIXEL_USER}@${PIXEL_IP}"* ]]; then
      echo "Closing existing tunnel (PID $OLD_PID)…"
      kill "$OLD_PID" 2>/dev/null || true
      sleep 1
    fi
  fi
  rm -f "$TUNNEL_PID_FILE"
fi

# ── Write SSH config entry if missing ─────────────────────────────────────────
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if ! grep -qE '^[[:space:]]*Host[[:space:]]+pixel-isl([[:space:]]|$)' "$SSH_CONFIG" 2>/dev/null; then
  cat >> "$SSH_CONFIG" << SSHEOF

# ISL Nexus Terminal — Pixel headless server
Host pixel-isl
  HostName ${PIXEL_IP}
  User ${PIXEL_USER}
  LocalForward ${OPENCLAW_PORT} localhost:${OPENCLAW_PORT}
  LocalForward ${AIONUI_PORT} localhost:${AIONUI_PORT}
  LocalForward ${OPENCODE_PORT} localhost:${OPENCODE_PORT}
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ExitOnForwardFailure yes
SSHEOF
  echo -e "  ${GREEN}written${NC}  ~/.ssh/config → Host pixel-isl"
else
  # Update HostName inside the pixel-isl block only — awk tracks which block
  # we're in so other SSH host entries are never touched.
  tmp_cfg="$(mktemp)"
  awk -v ip="${PIXEL_IP}" '
    BEGIN { in_block=0 }
    /^[[:space:]]*Host[[:space:]]+/ { in_block=($2=="pixel-isl") }
    in_block && /^[[:space:]]*HostName[[:space:]]+/ { $0="  HostName " ip }
    { print }
  ' "$SSH_CONFIG" > "$tmp_cfg" && mv "$tmp_cfg" "$SSH_CONFIG"
  echo -e "  ${GREEN}updated${NC}  ~/.ssh/config pixel-isl → ${PIXEL_IP}"
fi

# ── Open tunnel ───────────────────────────────────────────────────────────────
# Use ControlMaster (-M -S) so the socket is the precise teardown handle.
# Run in background with & so $! captures the real PID without relying on pgrep.
echo "  Opening SSH tunnel…"
ssh -N \
  -M -S "$TUNNEL_SOCK" \
  -L "${OPENCLAW_PORT}:localhost:${OPENCLAW_PORT}" \
  -L "${AIONUI_PORT}:localhost:${AIONUI_PORT}" \
  -L "${OPENCODE_PORT}:localhost:${OPENCODE_PORT}" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  "${PIXEL_USER}@${PIXEL_IP}" &
TUNNEL_PID=$!
echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"

# Brief wait then verify the process is still alive (catches immediate failures
# like ExitOnForwardFailure or bad host key).
sleep 1
if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
  rm -f "$TUNNEL_PID_FILE" "$TUNNEL_SOCK"
  echo ""
  echo "  SSH tunnel failed. Troubleshooting:"
  echo "    1. Confirm Tailscale is up on both machines: tailscale status"
  echo "    2. Confirm SSH server is running on Pixel: pgrep sshd"
  echo "    3. Try manually: ssh ${PIXEL_USER}@${PIXEL_IP}"
  exit 1
fi
echo ""

# ── Verify tunnel ─────────────────────────────────────────────────────────────
sleep 1
HEALTH="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://localhost:${OPENCLAW_PORT}/health" 2>/dev/null || true)"
HEALTH="${HEALTH:-000}"

echo ""
echo -e "${BOLD}=== Tunnel up — access from this laptop ===${NC}"
echo ""
echo -e "  ${CYAN}OpenClaw Gateway${NC}"
echo "    http://localhost:${OPENCLAW_PORT}                          $([ "$HEALTH" = "200" ] && echo "(health: OK)" || echo "(health: ${HEALTH})")"
echo "    http://localhost:${OPENCLAW_PORT}/.well-known/openclaw-gateway"
echo ""
echo -e "  ${CYAN}AionUi${NC}"
echo "    http://localhost:${AIONUI_PORT}"
echo ""
echo -e "  ${CYAN}Spare / OpenCode / Hermes${NC}"
echo "    http://localhost:${OPENCODE_PORT}"
echo ""
echo -e "  ${CYAN}SSH into Pixel directly:${NC}"
echo "    ssh pixel-isl"
echo ""

# Try to open browser (best-effort, non-fatal)
if command -v xdg-open > /dev/null 2>&1; then
  xdg-open "http://localhost:${AIONUI_PORT}" 2>/dev/null &
elif command -v open > /dev/null 2>&1; then
  open "http://localhost:${AIONUI_PORT}" 2>/dev/null &
fi

echo -e "  To close tunnel: ssh -S ~/.ssh/pixel-isl-tunnel.sock -O exit ${PIXEL_USER}@${PIXEL_IP}"
echo ""
